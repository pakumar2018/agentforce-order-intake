/**
 * REST endpoint MuleSoft calls after reading a purchase order, either from the PDF (Azure Document
 * Intelligence) or from the email body (Extract_Order_From_Email prompt template).
 * Builds the intake lines, matches customer and products, and sets the exceptions and
 * status with the same rules the agent uses (OrderIntakeService).
 * With autoCreateOrder, a clean intake becomes an order straight away and the response carries the
 * confirmation email MuleSoft sends back to the customer. Intakes that need review get a Case (OrderIntakeTrigger).
 *
 * POST /services/apexrest/orderintake/v1/extraction
 */
@RestResource(urlMapping='/orderintake/v1/extraction')
global with sharing class OrderIntakeExtractionApi {
    /** Extraction confidence below this (percent) flags the intake as Low Confidence. */
    public static final Decimal LOW_CONFIDENCE_THRESHOLD = 80;

    global class ExtractionLine {
        public Integer lineNo;
        public String sku;
        public String description;
        public Decimal quantity;
        public Decimal unitPrice;
    }

    global class ExtractionRequest {
        public Id intakeId;
        public Decimal extractionConfidence;
        public String poNumber;
        public String customerName;
        public String customerNumber;
        public List<ExtractionLine> lines;
        public String rawPayload;
        public String error;
        /** Where the details were read from, for example "PDF" or "email body" */
        public String source;
        /** Create the Salesforce order when the intake has no exceptions */
        public Boolean autoCreateOrder;
    }

    global class ExtractionResponse {
        public String intakeNumber;
        public String status;
        public String exceptions;
        public Integer lineCount;
        public String orderNumber;
        /** Order confirmation for the customer, set when the order was created */
        public String replySubject;
        public String replyBody;
    }

    @HttpPost
    global static ExtractionResponse receive() {
        ExtractionRequest req = (ExtractionRequest) JSON.deserialize(RestContext.request.requestBody.toString(), ExtractionRequest.class);
        try {
            return apply(req);
        } catch (Exception e) {
            RestContext.response.statusCode = 400;
            ExtractionResponse res = new ExtractionResponse();
            res.status = 'Error';
            res.exceptions = e.getMessage();
            return res;
        }
    }

    public static ExtractionResponse apply(ExtractionRequest req) {
        Order_Intake__c intake = [
            SELECT Id, Name, Status__c, Account__c, Source_Email_From__c, Exception_Reason__c, Order__c
            FROM Order_Intake__c WHERE Id = :req.intakeId WITH USER_MODE
        ];
        if (intake.Order__c != null) {
            throw new IllegalArgumentException(intake.Name + ' already has an order; extraction was not applied.');
        }
        Set<String> reasons = new Set<String>();

        if (String.isNotBlank(req.error)) {
            reasons.add('Missing Field');
            intake.Processing_Error__c = req.error.left(255);
        }
        intake.Extraction_Confidence__c = req.extractionConfidence;
        intake.Extraction_Source__c = String.isBlank(req.source) ? null : req.source.left(80);
        if (req.extractionConfidence != null && req.extractionConfidence < LOW_CONFIDENCE_THRESHOLD) {
            reasons.add('Low Confidence');
        }
        intake.Customer_PO_Number__c = String.isBlank(req.poNumber) ? null : req.poNumber.trim().left(80);
        if (intake.Customer_PO_Number__c == null) {
            reasons.add('Missing Field');
        }
        if (String.isNotBlank(req.rawPayload)) {
            intake.Extracted_Payload__c = req.rawPayload.left(131072);
        }
        if (intake.Account__c == null) {
            intake.Account__c = matchAccount(intake.Source_Email_From__c, req.customerNumber, req.customerName);
        }
        if (intake.Account__c == null) {
            reasons.add('Unknown Customer');
        }

        List<Order_Intake_Line__c> lines = buildLines(intake.Id, req.lines == null ? new List<ExtractionLine>() : req.lines);
        if (lines.isEmpty()) {
            reasons.add('Missing Field');
        }
        for (Order_Intake_Line__c line : lines) {
            if (line.Quantity__c == null || line.Unit_Price_On_PO__c == null) {
                reasons.add('Missing Field');
            }
        }

        // Re-extraction replaces earlier lines
        delete as user [SELECT Id FROM Order_Intake_Line__c WHERE Order_Intake__c = :intake.Id WITH USER_MODE];
        insert as user lines;

        intake.Exception_Reason__c = reasons.isEmpty() ? null : String.join(new List<String>(reasons), ';');
        intake.Status__c = OrderIntakeService.STATUS_EXTRACTED;
        OrderIntakeService.refreshExceptions(intake, lines);
        if (String.isNotBlank(intake.Exception_Reason__c)) {
            intake.Status__c = OrderIntakeService.STATUS_NEEDS_REVIEW;
        }
        update as user intake;

        ExtractionResponse res = new ExtractionResponse();
        res.intakeNumber = intake.Name;
        res.status = intake.Status__c;
        res.exceptions = intake.Exception_Reason__c;
        res.lineCount = lines.size();
        if (req.autoCreateOrder == true && intake.Status__c == OrderIntakeService.STATUS_EXTRACTED) {
            createOrder(intake, res);
        }
        return res;
    }

    private static void createOrder(Order_Intake__c intake, ExtractionResponse res) {
        CreateOrderFromIntake.Request orderReq = new CreateOrderFromIntake.Request();
        orderReq.intakeReference = intake.Name;
        CreateOrderFromIntake.Result created = CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ orderReq })[0];
        if (created.success != true) {
            // Lines are clean but the order could not be created: the rep takes it from here
            update as user new Order_Intake__c(Id = intake.Id, Status__c = OrderIntakeService.STATUS_NEEDS_REVIEW,
                Processing_Error__c = created.message.left(255));
            res.status = OrderIntakeService.STATUS_NEEDS_REVIEW;
            res.exceptions = created.message;
            return;
        }
        res.status = OrderIntakeReviewCases.STATUS_ORDER_CREATED;
        res.orderNumber = created.orderNumber;

        DraftOrderConfirmationEmail.Request draftReq = new DraftOrderConfirmationEmail.Request();
        draftReq.intakeReference = intake.Name;
        DraftOrderConfirmationEmail.Result draft = DraftOrderConfirmationEmail.draft(new List<DraftOrderConfirmationEmail.Request>{ draftReq })[0];
        if (draft.ready == true) {
            res.replySubject = draft.subject;
            res.replyBody = draft.body;
        }
    }

    /** Sender's contact first, then the customer number on the PO, then the exact customer name. */
    private static Id matchAccount(String senderEmail, String customerNumber, String customerName) {
        if (String.isNotBlank(senderEmail)) {
            List<Contact> contacts = [
                SELECT AccountId FROM Contact WHERE Email = :senderEmail AND AccountId != null WITH USER_MODE LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                return contacts[0].AccountId;
            }
        }
        if (String.isNotBlank(customerNumber)) {
            List<Account> byNumber = [SELECT Id FROM Account WHERE AccountNumber = :customerNumber.trim() WITH USER_MODE LIMIT 1];
            if (!byNumber.isEmpty()) {
                return byNumber[0].Id;
            }
        }
        if (String.isNotBlank(customerName)) {
            List<Account> byName = [SELECT Id FROM Account WHERE Name = :customerName.trim() WITH USER_MODE LIMIT 1];
            if (!byName.isEmpty()) {
                return byName[0].Id;
            }
        }
        return null;
    }

    private static List<Order_Intake_Line__c> buildLines(Id intakeId, List<ExtractionLine> extracted) {
        Map<String, Product2> productsByCode = new Map<String, Product2>();
        Set<String> codes = new Set<String>();
        for (ExtractionLine l : extracted) {
            if (String.isNotBlank(l.sku)) {
                codes.add(l.sku.trim());
            }
        }
        for (Product2 p : [
            SELECT Id, ProductCode, Name FROM Product2 WHERE ProductCode IN :codes AND IsActive = true WITH USER_MODE
        ]) {
            productsByCode.put(p.ProductCode.toUpperCase(), p);
        }
        Map<Id, Product2> matched = new Map<Id, Product2>();
        for (Product2 p : productsByCode.values()) {
            matched.put(p.Id, p);
        }
        Map<Id, PricebookEntry> prices = OrderIntakeService.listPrices(matched.keySet());

        List<Order_Intake_Line__c> lines = new List<Order_Intake_Line__c>();
        Integer position = 0;
        for (ExtractionLine l : extracted) {
            position++;
            Product2 product = String.isBlank(l.sku) ? null : productsByCode.get(l.sku.trim().toUpperCase());
            PricebookEntry price = product == null ? null : prices.get(product.Id);
            Order_Intake_Line__c line = new Order_Intake_Line__c(
                Order_Intake__c = intakeId,
                Line_No__c = l.lineNo != null ? l.lineNo : position,
                Raw_SKU__c = l.sku == null ? null : l.sku.left(100),
                Raw_Description__c = l.description == null ? null : l.description.left(255),
                Quantity__c = l.quantity,
                Unit_Price_On_PO__c = l.unitPrice,
                Product__c = product == null ? null : product.Id,
                List_Price__c = price == null ? null : price.UnitPrice
            );
            OrderIntakeService.applyMatchStatus(line);
            lines.add(line);
        }
        return lines;
    }
}

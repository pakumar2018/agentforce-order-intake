@IsTest
private class OrderIntakeExtractionApiTest {
    @TestSetup
    static void setup() {
        Product2 bearing = new Product2(Name = 'Ball Bearing 6204-2RS', ProductCode = 'BRG-2001', IsActive = true);
        Product2 valve = new Product2(Name = 'Ball Valve 1/2 inch Brass', ProductCode = 'VLV-5001', IsActive = true);
        insert new List<Product2>{ bearing, valve };
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = bearing.Id, UnitPrice = 4.20, IsActive = true),
            new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = valve.Id, UnitPrice = 34.90, IsActive = true)
        };
        Account acct = new Account(Name = 'Test Buyer Co', AccountNumber = 'CUST-9');
        insert acct;
        insert new Contact(LastName = 'Buyer', Email = 'buyer@test.example', AccountId = acct.Id);
        insert new List<Order_Intake__c>{
            new Order_Intake__c(Gmail_Message_Id__c = 'x-known', Source_Email_From__c = 'buyer@test.example', Status__c = 'Classified'),
            new Order_Intake__c(Gmail_Message_Id__c = 'x-unknown', Source_Email_From__c = 'someone@else.example', Status__c = 'Classified')
        };
    }

    private static OrderIntakeExtractionApi.ExtractionLine line(String sku, Decimal qty, Decimal price) {
        OrderIntakeExtractionApi.ExtractionLine l = new OrderIntakeExtractionApi.ExtractionLine();
        l.sku = sku;
        l.description = sku + ' item';
        l.quantity = qty;
        l.unitPrice = price;
        return l;
    }

    private static OrderIntakeExtractionApi.ExtractionResponse post(OrderIntakeExtractionApi.ExtractionRequest req) {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(req));
        return OrderIntakeExtractionApi.receive();
    }

    @IsTest
    static void cleanExtractionIsReadyForOrder() {
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'x-known'].Id;
        req.extractionConfidence = 96;
        req.poNumber = 'PO-1';
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line('BRG-2001', 100, 4.20), line('vlv-5001', 10, 34.90) };
        OrderIntakeExtractionApi.ExtractionResponse res = post(req);

        Assert.areEqual('Extracted', res.status, 'Unexpected exceptions: ' + res.exceptions);
        Assert.areEqual(2, res.lineCount);
        Order_Intake__c intake = [SELECT Account__r.Name, Customer_PO_Number__c FROM Order_Intake__c WHERE Id = :req.intakeId];
        Assert.areEqual('Test Buyer Co', intake.Account__r.Name);
        Assert.areEqual(2, [SELECT COUNT() FROM Order_Intake_Line__c WHERE Order_Intake__c = :req.intakeId AND Match_Status__c = 'Matched']);
    }

    @IsTest
    static void flagsEveryExceptionType() {
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'x-unknown'].Id;
        req.extractionConfidence = 55;
        req.customerName = 'Nobody Ltd';
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line('ZZZ-1', 5, 1), line('VLV-5001', null, 20) };
        OrderIntakeExtractionApi.ExtractionResponse res = post(req);

        Assert.areEqual('Needs Review', res.status);
        for (String reason : new List<String>{ 'Low Confidence', 'Unknown Customer', 'Missing Field', 'Unknown SKU', 'Price Mismatch' }) {
            Assert.isTrue(res.exceptions.contains(reason), reason + ' missing from ' + res.exceptions);
        }
    }

    @IsTest
    static void cleanEmailBodyOrderIsCreatedWithConfirmation() {
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'x-known'].Id;
        req.extractionConfidence = 100;
        req.poNumber = '7801';
        req.source = 'email body';
        req.autoCreateOrder = true;
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line('BRG-2001', 40, 4.20) };
        OrderIntakeExtractionApi.ExtractionResponse res = post(req);

        Assert.areEqual('Order Created', res.status, 'Unexpected: ' + res.exceptions);
        Assert.isNotNull(res.orderNumber);
        Assert.isTrue(res.replyBody.contains('Your order has been created as order ' + res.orderNumber), res.replyBody);
        Assert.isTrue(res.replyBody.contains('40 x BRG-2001'), res.replyBody);
        Order_Intake__c intake = [SELECT Order__c, Extraction_Source__c FROM Order_Intake__c WHERE Id = :req.intakeId];
        Assert.isNotNull(intake.Order__c);
        Assert.areEqual('email body', intake.Extraction_Source__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Order_Intake__c = :req.intakeId]);
    }

    @IsTest
    static void reviewCaseOpensAndClosesWithTheOrder() {
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'x-known'].Id;
        req.extractionConfidence = 90;
        req.poNumber = '7802';
        req.autoCreateOrder = true;
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line('ZZZ-1', 5, 1) };
        OrderIntakeExtractionApi.ExtractionResponse res = post(req);

        Assert.areEqual('Needs Review', res.status);
        Assert.isNull(res.orderNumber);
        Case review = [SELECT Subject, Description, Status, SuppliedEmail, ContactId, AccountId FROM Case WHERE Order_Intake__c = :req.intakeId];
        Assert.isTrue(review.Subject.contains('PO 7802') && review.Subject.contains('Unknown SKU'), review.Subject);
        Assert.isTrue(review.Description.contains('ZZZ-1'), review.Description);
        Assert.areEqual('buyer@test.example', review.SuppliedEmail);
        Assert.isNotNull(review.ContactId);

        // A second review status does not open a second case
        update new Order_Intake__c(Id = req.intakeId, Status__c = 'Error');
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Order_Intake__c = :req.intakeId]);

        // The rep fixes the line and creates the order: the case closes
        UpdateOrderIntakeLine.Request fix = new UpdateOrderIntakeLine.Request();
        update new Order_Intake__c(Id = req.intakeId, Status__c = 'Needs Review');
        fix.intakeReference = '7802';
        fix.lineNumber = 1;
        fix.productCode = 'BRG-2001';
        fix.useListPrice = true;
        UpdateOrderIntakeLine.updateLine(new List<UpdateOrderIntakeLine.Request>{ fix });
        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = '7802';
        Assert.isTrue(CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create })[0].success);
        Assert.areEqual('Closed', [SELECT Status FROM Case WHERE Order_Intake__c = :req.intakeId].Status);
    }

    @IsTest
    static void matchesCustomerByNumberAndReturnsErrorsAs400() {
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'x-unknown'].Id;
        req.customerNumber = 'CUST-9';
        req.poNumber = 'PO-2';
        req.error = 'IDP could not read page 2';
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line('BRG-2001', 1, 4.20) };
        OrderIntakeExtractionApi.ExtractionResponse res = post(req);
        Assert.isTrue(res.exceptions.contains('Missing Field'), res.exceptions);
        Assert.isNotNull([SELECT Account__c FROM Order_Intake__c WHERE Id = :req.intakeId].Account__c);

        req.intakeId = null;
        OrderIntakeExtractionApi.ExtractionResponse bad = post(req);
        Assert.areEqual('Error', bad.status);
        Assert.areEqual(400, RestContext.response.statusCode);
    }
}

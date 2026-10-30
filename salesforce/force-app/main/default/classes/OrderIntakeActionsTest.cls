@IsTest
private class OrderIntakeActionsTest {
    @TestSetup
    static void setup() {
        Id stdPb = Test.getStandardPricebookId();
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Ball Bearing 6204-2RS', ProductCode = 'BRG-2001', IsActive = true),
            new Product2(Name = 'Industrial Widget 10mm', ProductCode = 'WID-1001', IsActive = true),
            new Product2(Name = 'Centrifugal Pump 0.5 HP', ProductCode = 'PMP-6001', IsActive = true)
        };
        insert products;
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = stdPb, Product2Id = products[0].Id, UnitPrice = 4.20, IsActive = true),
            new PricebookEntry(Pricebook2Id = stdPb, Product2Id = products[1].Id, UnitPrice = 12.50, IsActive = true),
            new PricebookEntry(Pricebook2Id = stdPb, Product2Id = products[2].Id, UnitPrice = 449.00, IsActive = true)
        };
        Account acct = new Account(Name = 'Test Buyer Co', AccountNumber = 'CUST-9');
        insert acct;
        insert new Contact(LastName = 'Buyer', Email = 'buyer@test.example', AccountId = acct.Id);

        Order_Intake__c review = new Order_Intake__c(
            Gmail_Message_Id__c = 'test-review', Status__c = 'Needs Review', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-100', Source_Email_From__c = 'buyer@test.example',
            Subject__c = 'PO 100', Exception_Reason__c = 'Unknown SKU;Price Mismatch',
            Classification__c = 'Purchase Order', Classification_Confidence__c = 97, Received_At__c = System.now()
        );
        Order_Intake__c big = new Order_Intake__c(
            Gmail_Message_Id__c = 'test-big', Status__c = 'Extracted', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-200', Source_Email_From__c = 'other@test.example', Subject__c = 'Pumps'
        );
        insert new List<Order_Intake__c>{ review, big };
        insert new List<Order_Intake_Line__c>{
            new Order_Intake_Line__c(Order_Intake__c = review.Id, Line_No__c = 1, Raw_SKU__c = 'WID-1001', Quantity__c = 10,
                Unit_Price_On_PO__c = 12.50, Product__c = products[1].Id, List_Price__c = 12.50, Match_Status__c = 'Matched'),
            new Order_Intake_Line__c(Order_Intake__c = review.Id, Line_No__c = 2, Raw_SKU__c = 'BRG6204',
                Raw_Description__c = 'ball bearing 6204 sealed', Quantity__c = 100, Unit_Price_On_PO__c = 4.20, Match_Status__c = 'Unmatched'),
            new Order_Intake_Line__c(Order_Intake__c = big.Id, Line_No__c = 1, Raw_SKU__c = 'PMP-6001', Quantity__c = 80,
                Unit_Price_On_PO__c = 449.00, Product__c = products[2].Id, List_Price__c = 449.00, Match_Status__c = 'Matched')
        };
    }

    private static String intakeName(String poNumber) {
        return [SELECT Name FROM Order_Intake__c WHERE Customer_PO_Number__c = :poNumber].Name;
    }

    @IsTest
    static void findsIntakesByTextAndStatus() {
        FindOrderIntakes.Request req = new FindOrderIntakes.Request();
        req.statusFilter = 'open';
        FindOrderIntakes.Result res = FindOrderIntakes.find(new List<FindOrderIntakes.Request>{ req })[0];
        Assert.areEqual(1, res.matchCount);
        Assert.isTrue(res.summary.contains('PO-100'));

        req.statusFilter = null;
        req.searchText = 'Test Buyer';
        Assert.areEqual(2, FindOrderIntakes.find(new List<FindOrderIntakes.Request>{ req })[0].matchCount);
    }

    @IsTest
    static void describesIntakeWithLines() {
        GetOrderIntakeDetails.Request req = new GetOrderIntakeDetails.Request();
        req.intakeReference = 'PO-100';
        GetOrderIntakeDetails.Result res = GetOrderIntakeDetails.getDetails(new List<GetOrderIntakeDetails.Request>{ req })[0];
        Assert.isTrue(res.found);
        Assert.isTrue(res.details.contains('BRG6204'), res.details);
        // Quantities must be plain digits; stripTrailingZeros alone renders 100 as 1E+2
        Assert.isTrue(res.details.contains('qty 100 @'), res.details);
        Assert.isTrue(res.details.contains('Unmatched'), res.details);

        req.intakeReference = 'OI-99999';
        Assert.isFalse(GetOrderIntakeDetails.getDetails(new List<GetOrderIntakeDetails.Request>{ req })[0].found);
    }

    @IsTest
    static void suggestsBearingForUnknownSku() {
        SuggestProductMatches.Request req = new SuggestProductMatches.Request();
        req.skuText = 'BRG6204';
        req.descriptionText = 'ball bearing 6204 sealed';
        SuggestProductMatches.Result res = SuggestProductMatches.suggest(new List<SuggestProductMatches.Request>{ req })[0];
        Assert.isTrue(res.suggestions.startsWith('1. BRG-2001'), res.suggestions);
    }

    @IsTest
    static void fixesLineThenCreatesOrder() {
        String name = intakeName('PO-100');

        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = name;
        CreateOrderFromIntake.Result blocked = CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create })[0];
        Assert.isFalse(blocked.success);
        Assert.isTrue(blocked.message.contains('line 2'), blocked.message);

        UpdateOrderIntakeLine.Request fix = new UpdateOrderIntakeLine.Request();
        fix.intakeReference = name;
        fix.lineNumber = 2;
        fix.productCode = 'BRG-2001';
        UpdateOrderIntakeLine.Result fixed = UpdateOrderIntakeLine.updateLine(new List<UpdateOrderIntakeLine.Request>{ fix })[0];
        Assert.isTrue(fixed.success, fixed.message);
        Order_Intake__c afterFix = [SELECT Status__c, Exception_Reason__c FROM Order_Intake__c WHERE Customer_PO_Number__c = 'PO-100'];
        Assert.areEqual('Extracted', afterFix.Status__c);
        Assert.isNull(afterFix.Exception_Reason__c);

        CreateOrderFromIntake.Result created = CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create })[0];
        Assert.isTrue(created.success, created.message);
        Order_Intake__c afterOrder = [SELECT Status__c, Order__r.TotalAmount FROM Order_Intake__c WHERE Customer_PO_Number__c = 'PO-100'];
        Assert.areEqual('Order Created', afterOrder.Status__c);
        Assert.areEqual(545.00, afterOrder.Order__r.TotalAmount);
    }

    @IsTest
    static void flagsAndAcceptsPriceMismatch() {
        UpdateOrderIntakeLine.Request req = new UpdateOrderIntakeLine.Request();
        req.intakeReference = 'PO-100';
        req.lineNumber = 2;
        req.productCode = 'BRG-2001';
        req.quantity = 120;
        update new Order_Intake_Line__c(
            Id = [SELECT Id FROM Order_Intake_Line__c WHERE Raw_SKU__c = 'BRG6204'].Id, Unit_Price_On_PO__c = 3.00
        );
        UpdateOrderIntakeLine.Result mismatch = UpdateOrderIntakeLine.updateLine(new List<UpdateOrderIntakeLine.Request>{ req })[0];
        Assert.isTrue(mismatch.message.contains('Price Mismatch'), mismatch.message);

        req.productCode = null;
        req.acceptPoPrice = true;
        UpdateOrderIntakeLine.Result accepted = UpdateOrderIntakeLine.updateLine(new List<UpdateOrderIntakeLine.Request>{ req })[0];
        Assert.isTrue(accepted.message.contains('no open exceptions'), accepted.message);
    }

    @IsTest
    static void simulatedErpConfirmsSmallAndRejectsLargeOrders() {
        OrderIntakeErpClient.muleConfiguredOverride = false;
        String bigName = intakeName('PO-200');
        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = bigName;
        Assert.isTrue(CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create })[0].success);

        SubmitOrderToErp.Request submit = new SubmitOrderToErp.Request();
        submit.intakeReference = bigName;
        SubmitOrderToErp.Result rejected = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submit })[0];
        Assert.isFalse(rejected.success);
        Assert.isTrue(rejected.message.contains('Credit limit'), rejected.message);

        CheckErpStatus.Request check = new CheckErpStatus.Request();
        check.intakeReference = bigName;
        CheckErpStatus.Result status = CheckErpStatus.check(new List<CheckErpStatus.Request>{ check })[0];
        Assert.isTrue(status.canResubmit);

        update new Order_Intake_Line__c(Id = [SELECT Id FROM Order_Intake_Line__c WHERE Raw_SKU__c = 'PMP-6001'].Id, Quantity__c = 5);
        Order bigOrder = [SELECT Id FROM Order WHERE PoNumber = 'PO-200'];
        OrderItem item = [SELECT Id FROM OrderItem WHERE OrderId = :bigOrder.Id];
        update new OrderItem(Id = item.Id, Quantity = 5);
        SubmitOrderToErp.Result confirmed = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submit })[0];
        Assert.isTrue(confirmed.success, confirmed.message);
        Assert.isTrue(confirmed.erpOrderNumber.startsWith('ERP-'));
    }

    private class MuleMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        MuleMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void muleConfirmsOrderAndReportsLiveStatus() {
        OrderIntakeErpClient.muleConfiguredOverride = false;
        String bigName = intakeName('PO-200');
        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = bigName;
        CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create });

        OrderIntakeErpClient.muleConfiguredOverride = true;
        Test.setMock(HttpCalloutMock.class, new MuleMock(200, '{"status":"Confirmed","erpOrderNumber":"SAP-4711"}'));
        Test.startTest();
        SubmitOrderToErp.Request submit = new SubmitOrderToErp.Request();
        submit.intakeReference = bigName;
        SubmitOrderToErp.Result res = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submit })[0];
        Assert.areEqual('SAP-4711', res.erpOrderNumber, res.message);

        CheckErpStatus.Request check = new CheckErpStatus.Request();
        check.intakeReference = bigName;
        CheckErpStatus.Result status = CheckErpStatus.check(new List<CheckErpStatus.Request>{ check })[0];
        Test.stopTest();
        Assert.isTrue(status.statusSummary.contains('SAP-4711'), status.statusSummary);
        Assert.isFalse(status.canResubmit);
    }

    @IsTest
    static void muleErrorMarksErpFailed() {
        OrderIntakeErpClient.muleConfiguredOverride = false;
        String bigName = intakeName('PO-200');
        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = bigName;
        CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create });

        OrderIntakeErpClient.muleConfiguredOverride = true;
        Test.setMock(HttpCalloutMock.class, new MuleMock(503, 'Service unavailable'));
        Test.startTest();
        SubmitOrderToErp.Request submit = new SubmitOrderToErp.Request();
        submit.intakeReference = bigName;
        SubmitOrderToErp.Result res = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submit })[0];

        CheckErpStatus.Request check = new CheckErpStatus.Request();
        check.intakeReference = bigName;
        CheckErpStatus.Result status = CheckErpStatus.check(new List<CheckErpStatus.Request>{ check })[0];
        Test.stopTest();
        Assert.isFalse(res.success);
        Assert.isTrue(res.message.contains('HTTP 503'), res.message);
        Assert.isTrue(status.canResubmit);
    }

    @IsTest
    static void handlesUnknownIntakesAndMissingOrders() {
        CheckErpStatus.Request check = new CheckErpStatus.Request();
        check.intakeReference = 'PO-100';
        Assert.isTrue(CheckErpStatus.check(new List<CheckErpStatus.Request>{ check })[0].statusSummary.contains('no Salesforce order'));
        check.intakeReference = 'nope';
        Assert.isTrue(CheckErpStatus.check(new List<CheckErpStatus.Request>{ check })[0].statusSummary.startsWith('No order intake'));

        SubmitOrderToErp.Request submit = new SubmitOrderToErp.Request();
        submit.intakeReference = 'PO-100';
        Assert.isFalse(SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ submit })[0].success);

        SendIntakeCustomerEmail.Request mail = new SendIntakeCustomerEmail.Request();
        mail.intakeReference = 'nope';
        mail.subject = 's';
        mail.body = 'b';
        Assert.isFalse(SendIntakeCustomerEmail.send(new List<SendIntakeCustomerEmail.Request>{ mail })[0].success);
    }

    @IsTest
    static void emailsSenderWithoutContact() {
        SendIntakeCustomerEmail.Request mail = new SendIntakeCustomerEmail.Request();
        mail.intakeReference = 'PO-200';
        mail.subject = 'Order received';
        mail.body = 'We received your PO.';
        SendIntakeCustomerEmail.Result res = SendIntakeCustomerEmail.send(new List<SendIntakeCustomerEmail.Request>{ mail })[0];
        if (res.success) {
            Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Subject = 'Email: Order received']);
        } else {
            Assert.isTrue(res.message.contains('could not be sent'), res.message);
        }
    }

    @IsTest
    static void draftsConfirmationWithExactOrderLines() {
        DraftOrderConfirmationEmail.Request req = new DraftOrderConfirmationEmail.Request();
        req.intakeReference = 'PO-200';
        DraftOrderConfirmationEmail.Result noOrder = DraftOrderConfirmationEmail.draft(new List<DraftOrderConfirmationEmail.Request>{ req })[0];
        Assert.isFalse(noOrder.ready);

        CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
        create.intakeReference = 'PO-200';
        CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create });
        DraftOrderConfirmationEmail.Result draft = DraftOrderConfirmationEmail.draft(new List<DraftOrderConfirmationEmail.Request>{ req })[0];
        Assert.isTrue(draft.ready, 'Confirmation should be ready once the order exists');
        Assert.isTrue(draft.body.contains('80 x PMP-6001'), draft.body);
        Assert.isTrue(draft.subject.contains('PO-200'), draft.subject);

        req.intakeReference = 'nope';
        Assert.isFalse(DraftOrderConfirmationEmail.draft(new List<DraftOrderConfirmationEmail.Request>{ req })[0].ready);
    }

    @IsTest
    static void escalatesAndEmails() {
        EscalateOrderIntake.Request esc = new EscalateOrderIntake.Request();
        esc.intakeReference = 'PO-100';
        esc.team = 'Pricing';
        esc.reason = 'Customer price below list';
        Assert.isTrue(EscalateOrderIntake.escalate(new List<EscalateOrderIntake.Request>{ esc })[0].success);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Priority = 'High']);

        SendIntakeCustomerEmail.Request mail = new SendIntakeCustomerEmail.Request();
        mail.intakeReference = 'PO-100';
        mail.subject = 'Your order';
        mail.body = 'Thank you for your order.';
        SendIntakeCustomerEmail.Result res = SendIntakeCustomerEmail.send(new List<SendIntakeCustomerEmail.Request>{ mail })[0];
        // Deliverability may be off in the org running the test; either outcome must return a message.
        Assert.isNotNull(res.message);
    }
}

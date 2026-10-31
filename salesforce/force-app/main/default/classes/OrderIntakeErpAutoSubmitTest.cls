@IsTest
private class OrderIntakeErpAutoSubmitTest {
    @TestSetup
    static void setup() {
        Product2 pump = new Product2(Name = 'Centrifugal Pump 0.5 HP', ProductCode = 'PMP-6001', IsActive = true);
        insert pump;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = pump.Id, UnitPrice = 449.00, IsActive = true);
        Account acct = new Account(Name = 'Test Buyer Co', AccountNumber = 'CUST-9');
        insert acct;
        insert new Contact(LastName = 'Buyer', Email = 'buyer@test.example', AccountId = acct.Id);

        Order_Intake__c small = new Order_Intake__c(Gmail_Message_Id__c = 'auto-small', Status__c = 'Extracted', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-600', Source_Email_From__c = 'buyer@test.example', Subject__c = 'Pumps');
        Order_Intake__c big = new Order_Intake__c(Gmail_Message_Id__c = 'auto-big', Status__c = 'Extracted', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-700', Source_Email_From__c = 'buyer@test.example', Subject__c = 'Many pumps');
        Order_Intake__c email = new Order_Intake__c(Gmail_Message_Id__c = 'auto-email', Status__c = 'Classified',
            Source_Email_From__c = 'buyer@test.example', Subject__c = 'PO 800');
        insert new List<Order_Intake__c>{ small, big, email };
        insert new List<Order_Intake_Line__c>{
            new Order_Intake_Line__c(Order_Intake__c = small.Id, Line_No__c = 1, Raw_SKU__c = 'PMP-6001', Quantity__c = 5,
                Unit_Price_On_PO__c = 449.00, Product__c = pump.Id, List_Price__c = 449.00, Match_Status__c = 'Matched'),
            new Order_Intake_Line__c(Order_Intake__c = big.Id, Line_No__c = 1, Raw_SKU__c = 'PMP-6001', Quantity__c = 80,
                Unit_Price_On_PO__c = 449.00, Product__c = pump.Id, List_Price__c = 449.00, Match_Status__c = 'Matched')
        };
    }

    private class MuleMock implements HttpCalloutMock {
        public Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"Confirmed","erpOrderNumber":"S00077"}');
            return res;
        }
    }

    private static CreateOrderFromIntake.Result createOrder(String poNumber) {
        CreateOrderFromIntake.Request req = new CreateOrderFromIntake.Request();
        req.intakeReference = poNumber;
        return CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ req })[0];
    }

    private static Order_Intake__c intake(String poNumber) {
        return [SELECT Id, Status__c, ERP_Order_Number__c, ERP_Error__c FROM Order_Intake__c WHERE Customer_PO_Number__c = :poNumber];
    }

    @IsTest
    static void orderCreatedAfterReviewGoesToErpOnItsOwn() {
        OrderIntakeErpClient.muleConfiguredOverride = true;
        MuleMock mule = new MuleMock();
        Test.setMock(HttpCalloutMock.class, mule);

        Test.startTest();
        CreateOrderFromIntake.Result created = createOrder('PO-600');
        Assert.isTrue(created.success, created.message);
        Assert.isTrue(created.message.contains('being sent to the ERP automatically'), created.message);
        Test.stopTest();

        Order_Intake__c after = intake('PO-600');
        Assert.areEqual('ERP Confirmed', after.Status__c);
        Assert.areEqual('S00077', after.ERP_Order_Number__c);
        Assert.areEqual(1, mule.calls);
    }

    @IsTest
    static void erpRejectionOpensReviewCase() {
        // Simulated ERP (no named credential): orders above the credit limit are rejected
        OrderIntakeErpClient.muleConfiguredOverride = false;
        Test.startTest();
        Assert.isTrue(createOrder('PO-700').success);
        Test.stopTest();

        Order_Intake__c after = intake('PO-700');
        Assert.areEqual('ERP Failed', after.Status__c);
        Assert.isTrue(after.ERP_Error__c.contains('Credit limit'), after.ERP_Error__c);
        Case review = [SELECT Subject, Priority, IsClosed FROM Case WHERE Order_Intake__c = :after.Id];
        Assert.isFalse(review.IsClosed);
        Assert.isTrue(review.Subject.contains('ERP rejected the order'), review.Subject);
    }

    @IsTest
    static void muleStraightThroughOrderIsNotSentTwice() {
        OrderIntakeErpClient.muleConfiguredOverride = true;
        MuleMock mule = new MuleMock();
        Test.setMock(HttpCalloutMock.class, mule);
        OrderIntakeExtractionApi.ExtractionLine line = new OrderIntakeExtractionApi.ExtractionLine();
        line.sku = 'PMP-6001';
        line.quantity = 2;
        line.unitPrice = 449.00;
        OrderIntakeExtractionApi.ExtractionRequest req = new OrderIntakeExtractionApi.ExtractionRequest();
        req.intakeId = [SELECT Id FROM Order_Intake__c WHERE Gmail_Message_Id__c = 'auto-email'].Id;
        req.extractionConfidence = 98;
        req.poNumber = 'PO-800';
        req.autoCreateOrder = true;
        req.autoSubmitErp = true;
        req.lines = new List<OrderIntakeExtractionApi.ExtractionLine>{ line };

        Test.startTest();
        OrderIntakeExtractionApi.ExtractionResponse res = OrderIntakeExtractionApi.apply(req);
        Test.stopTest();

        Assert.areEqual('Order Created', res.status, 'Exceptions: ' + res.exceptions);
        // MuleSoft calls /erp-submit itself, so nothing was queued
        Assert.areEqual('Order Created', intake('PO-800').Status__c);
        Assert.areEqual(0, mule.calls);
        Assert.isFalse(OrderIntakeErpAutoSubmit.suppress, 'suppress is reset after the request');
    }

    @IsTest
    static void resendOfConfirmedOrderReturnsItsErpNumber() {
        OrderIntakeErpClient.muleConfiguredOverride = true;
        MuleMock mule = new MuleMock();
        Test.setMock(HttpCalloutMock.class, mule);
        Test.startTest();
        createOrder('PO-600');
        Test.stopTest();

        SubmitOrderToErp.Request again = new SubmitOrderToErp.Request();
        again.intakeReference = 'PO-600';
        SubmitOrderToErp.Result res = SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ again })[0];
        Assert.isTrue(res.success, res.message);
        Assert.areEqual('S00077', res.erpOrderNumber);
        Assert.isTrue(res.message.contains('already in the ERP'), res.message);
        Assert.areEqual(1, mule.calls, 'no second callout');
    }
}

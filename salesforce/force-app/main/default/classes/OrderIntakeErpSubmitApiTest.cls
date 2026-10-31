@IsTest
private class OrderIntakeErpSubmitApiTest {
    @TestSetup
    static void setup() {
        Product2 pump = new Product2(Name = 'Centrifugal Pump 0.5 HP', ProductCode = 'PMP-6001', IsActive = true);
        insert pump;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = pump.Id, UnitPrice = 449.00, IsActive = true);
        Account acct = new Account(Name = 'Test Buyer Co', AccountNumber = 'CUST-9');
        insert acct;
        insert new Contact(LastName = 'Buyer', Email = 'buyer@test.example', AccountId = acct.Id);

        Order_Intake__c small = new Order_Intake__c(Gmail_Message_Id__c = 'erp-small', Status__c = 'Extracted', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-300', Source_Email_From__c = 'buyer@test.example', Subject__c = 'Pumps');
        Order_Intake__c big = new Order_Intake__c(Gmail_Message_Id__c = 'erp-big', Status__c = 'Extracted', Account__c = acct.Id,
            Customer_PO_Number__c = 'PO-400', Source_Email_From__c = 'buyer@test.example', Subject__c = 'Many pumps');
        Order_Intake__c noOrder = new Order_Intake__c(Gmail_Message_Id__c = 'erp-none', Status__c = 'Classified',
            Customer_PO_Number__c = 'PO-500', Source_Email_From__c = 'buyer@test.example');
        insert new List<Order_Intake__c>{ small, big, noOrder };
        insert new List<Order_Intake_Line__c>{
            new Order_Intake_Line__c(Order_Intake__c = small.Id, Line_No__c = 1, Raw_SKU__c = 'PMP-6001', Quantity__c = 5,
                Unit_Price_On_PO__c = 449.00, Product__c = pump.Id, List_Price__c = 449.00, Match_Status__c = 'Matched'),
            new Order_Intake_Line__c(Order_Intake__c = big.Id, Line_No__c = 1, Raw_SKU__c = 'PMP-6001', Quantity__c = 80,
                Unit_Price_On_PO__c = 449.00, Product__c = pump.Id, List_Price__c = 449.00, Match_Status__c = 'Matched')
        };
        // As OrderIntakeExtractionApi does for a clean intake: the order exists before MuleSoft calls erp-submit
        for (String poNumber : new List<String>{ 'PO-300', 'PO-400' }) {
            CreateOrderFromIntake.Request create = new CreateOrderFromIntake.Request();
            create.intakeReference = poNumber;
            CreateOrderFromIntake.Result created = CreateOrderFromIntake.create(new List<CreateOrderFromIntake.Request>{ create })[0];
            Assert.isTrue(created.success, created.message);
        }
    }

    private class MuleMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        MuleMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            Assert.isTrue(req.getEndpoint().endsWith('/erp-submit'), req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static Id intakeId(String poNumber) {
        return [SELECT Id FROM Order_Intake__c WHERE Customer_PO_Number__c = :poNumber].Id;
    }

    private static OrderIntakeErpSubmitApi.SubmitResponse post(Id intakeId) {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'intakeId' => intakeId }));
        return OrderIntakeErpSubmitApi.receive();
    }

    @IsTest
    static void erpConfirmedReturnsConfirmationWithErpNumber() {
        OrderIntakeErpClient.muleConfiguredOverride = true;
        Test.setMock(HttpCalloutMock.class, new MuleMock(200, '{"status":"Confirmed","erpOrderNumber":"S00042"}'));
        Id smallId = intakeId('PO-300');
        Test.startTest();
        OrderIntakeErpSubmitApi.SubmitResponse res = post(smallId);
        Test.stopTest();

        Assert.areEqual('ERP Confirmed', res.status, res.message);
        Assert.areEqual('S00042', res.erpOrderNumber);
        Assert.isTrue(res.replySubject.contains('S00042'), res.replySubject);
        Assert.isTrue(res.replyBody.contains('Your order has been created as order S00042'), res.replyBody);
        Assert.isTrue(res.replyBody.contains('5 x PMP-6001'), res.replyBody);
        Order_Intake__c intake = [SELECT Status__c, ERP_Order_Number__c FROM Order_Intake__c WHERE Id = :smallId];
        Assert.areEqual('S00042', intake.ERP_Order_Number__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Order_Intake__c = :smallId]);
    }

    @IsTest
    static void erpFailedOpensReviewCaseWithoutReply() {
        OrderIntakeErpClient.muleConfiguredOverride = true;
        Test.setMock(HttpCalloutMock.class, new MuleMock(200,
            '{"status":"Failed","error":"Credit limit exceeded for Test Buyer Co"}'));
        Id bigId = intakeId('PO-400');
        Test.startTest();
        OrderIntakeErpSubmitApi.SubmitResponse res = post(bigId);
        Test.stopTest();

        Assert.areEqual('ERP Failed', res.status);
        Assert.isNull(res.erpOrderNumber);
        Assert.isNull(res.replyBody);
        Assert.isTrue(res.message.contains('Credit limit exceeded'), res.message);
        Case review = [SELECT Subject, Description, Priority, Status FROM Case WHERE Order_Intake__c = :bigId];
        Assert.isTrue(review.Subject.contains('ERP rejected the order'), review.Subject);
        Assert.isTrue(review.Description.contains('Credit limit exceeded'), review.Description);
        Assert.areEqual('High', review.Priority);
    }

    @IsTest
    static void reviewCaseClosesWhenErpConfirmsAResend() {
        // Simulated ERP (no named credential): orders above the credit limit are rejected
        OrderIntakeErpClient.muleConfiguredOverride = false;
        Id bigId = intakeId('PO-400');
        Assert.areEqual('ERP Failed', post(bigId).status);
        Assert.isFalse([SELECT IsClosed FROM Case WHERE Order_Intake__c = :bigId].IsClosed);

        // The credit team lowers the order; the rep resends it
        Order bigOrder = [SELECT Id FROM Order WHERE PoNumber = 'PO-400'];
        update new OrderItem(Id = [SELECT Id FROM OrderItem WHERE OrderId = :bigOrder.Id].Id, Quantity = 5);
        OrderIntakeErpSubmitApi.SubmitResponse res = post(bigId);
        Assert.areEqual('ERP Confirmed', res.status, res.message);
        Assert.isTrue(res.erpOrderNumber.startsWith('ERP-'), res.erpOrderNumber);
        Assert.areEqual('Closed', [SELECT Status FROM Case WHERE Order_Intake__c = :bigId].Status);
    }

    @IsTest
    static void intakeWithoutOrderIsNotSentAndBadRequestsReturn400() {
        OrderIntakeErpClient.muleConfiguredOverride = false;
        Id noOrderId = intakeId('PO-500');
        OrderIntakeErpSubmitApi.SubmitResponse res = post(noOrderId);
        Assert.areEqual('Classified', res.status);
        Assert.isNull(res.replyBody);
        Assert.isTrue(res.message.contains('no order has been created yet'), res.message);

        OrderIntakeErpSubmitApi.SubmitResponse bad = post(null);
        Assert.areEqual('Error', bad.status);
        Assert.areEqual(400, RestContext.response.statusCode);
    }
}

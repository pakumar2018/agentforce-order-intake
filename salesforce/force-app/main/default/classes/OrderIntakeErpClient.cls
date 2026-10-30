/**
 * Talks to the ERP through the MuleSoft API behind the Order_Intake_Mule named credential.
 * Until that named credential exists, ERP responses are simulated so the demo runs end to end:
 * orders above the simulated credit limit are rejected, everything else is confirmed.
 */
public with sharing class OrderIntakeErpClient {
    public static final String NAMED_CREDENTIAL = 'Order_Intake_Mule';
    public static final Decimal SIMULATED_CREDIT_LIMIT = 25000;

    @TestVisible
    private static Boolean muleConfiguredOverride;

    public class ErpResponse {
        public Boolean success = false;
        public String erpOrderNumber;
        public String error;
        public Boolean simulated = false;
    }

    public static Boolean isMuleConfigured() {
        if (muleConfiguredOverride != null) {
            return muleConfiguredOverride;
        }
        return ![SELECT Id FROM NamedCredential WHERE DeveloperName = :NAMED_CREDENTIAL LIMIT 1].isEmpty();
    }

    public static ErpResponse submit(Order_Intake__c intake) {
        if (!isMuleConfigured()) {
            return simulateSubmit(intake);
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/orders/' + intake.Order__c + '/erp-submit');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);
        // The approved lines travel with the request, so the ERP API needs no Salesforce access
        List<Map<String, Object>> lines = new List<Map<String, Object>>();
        for (OrderItem item : [
            SELECT Quantity, UnitPrice, Product2.ProductCode, Product2.Name
            FROM OrderItem WHERE OrderId = :intake.Order__c WITH USER_MODE ORDER BY CreatedDate
        ]) {
            lines.add(new Map<String, Object>{
                'sku' => item.Product2.ProductCode,
                'name' => item.Product2.Name,
                'quantity' => item.Quantity,
                'unitPrice' => item.UnitPrice
            });
        }
        req.setBody(JSON.serialize(new Map<String, Object>{
            'intakeNumber' => intake.Name,
            'orderId' => intake.Order__c,
            'orderNumber' => intake.Order__r.OrderNumber,
            'poNumber' => intake.Customer_PO_Number__c,
            'accountNumber' => intake.Account__r.AccountNumber,
            'total' => intake.Order__r.TotalAmount,
            'lines' => lines
        }));
        return parse(new Http().send(req));
    }

    public static ErpResponse fetchStatus(Order_Intake__c intake) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/orders/' + intake.Order__c + '/erp-status');
        req.setMethod('GET');
        req.setTimeout(30000);
        return parse(new Http().send(req));
    }

    /** Expects {"status": "Confirmed" | "Failed", "erpOrderNumber": "...", "error": "..."}. */
    private static ErpResponse parse(HttpResponse httpRes) {
        ErpResponse res = new ErpResponse();
        if (httpRes.getStatusCode() >= 300) {
            res.error = 'MuleSoft returned HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getBody().left(200);
            return res;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
        res.success = 'Confirmed'.equalsIgnoreCase((String) body.get('status'));
        res.erpOrderNumber = (String) body.get('erpOrderNumber');
        res.error = (String) body.get('error');
        return res;
    }

    private static ErpResponse simulateSubmit(Order_Intake__c intake) {
        ErpResponse res = new ErpResponse();
        res.simulated = true;
        Decimal total = intake.Order__r.TotalAmount == null ? 0 : intake.Order__r.TotalAmount;
        if (total > SIMULATED_CREDIT_LIMIT) {
            res.error = 'Credit limit exceeded: order total ' + OrderIntakeService.money(total)
                + ' is above the customer credit limit of ' + OrderIntakeService.money(SIMULATED_CREDIT_LIMIT) + '. Credit team approval required.';
        } else {
            res.success = true;
            res.erpOrderNumber = 'ERP-' + intake.Order__r.OrderNumber;
        }
        return res;
    }
}

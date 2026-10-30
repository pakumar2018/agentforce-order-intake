/**
 * Agent action: build the order confirmation email from the order data itself, so quantities,
 * prices and order numbers in the email are always exact.
 */
public with sharing class DraftOrderConfirmationEmail {
    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
    }

    public class Result {
        @InvocableVariable(label='Ready' description='True when a confirmation could be drafted')
        public Boolean ready;
        @InvocableVariable(label='Subject' description='Email subject')
        public String subject;
        @InvocableVariable(label='Body' description='Plain-text email body with the exact order lines')
        public String body;
        @InvocableVariable(label='Message' description='Why no confirmation could be drafted, when Ready is false')
        public String message;
    }

    @InvocableMethod(
        label='Draft Order Confirmation Email'
        description='Builds the order confirmation email for an intake that has a Salesforce order, using the exact order lines, quantities, prices, total and ERP order number.'
    )
    public static List<Result> draft(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(draftOne(req));
        }
        return results;
    }

    private static Result draftOne(Request req) {
        Result res = new Result();
        res.ready = false;
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        if (intake.Order__c == null) {
            res.message = intake.Name + ' has no order yet, so there is nothing to confirm. Create the order first.';
            return res;
        }

        List<String> lines = new List<String>();
        for (OrderItem item : [
            SELECT Quantity, UnitPrice, TotalPrice, Product2.ProductCode, Product2.Name
            FROM OrderItem WHERE OrderId = :intake.Order__c WITH USER_MODE ORDER BY CreatedDate
        ]) {
            lines.add('- ' + item.Quantity.stripTrailingZeros().toPlainString() + ' x ' + item.Product2.ProductCode + ' ' + item.Product2.Name
                + ' @ ' + OrderIntakeService.money(item.UnitPrice) + ' = ' + OrderIntakeService.money(item.TotalPrice));
        }
        String reference = String.isNotBlank(intake.ERP_Order_Number__c)
            ? 'order ' + intake.ERP_Order_Number__c
            : 'order ' + intake.Order__r.OrderNumber;
        String poNumber = String.isBlank(intake.Customer_PO_Number__c) ? intake.Name : intake.Customer_PO_Number__c;

        res.ready = true;
        res.subject = 'Order confirmation - PO ' + poNumber + ' (' + reference.removeStart('order ') + ')';
        res.body = 'Hello,\n\n'
            + 'Thank you for your purchase order ' + poNumber + '. Your order has been created as ' + reference + '.\n\n'
            + 'Order lines:\n' + String.join(lines, '\n') + '\n\n'
            + 'Order total: ' + OrderIntakeService.money(intake.Order__r.TotalAmount) + '\n\n'
            + 'Please reply to this email if anything needs to change.\n\n'
            + 'Kind regards,\nOrder Desk';
        return res;
    }
}
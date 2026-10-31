/**
 * Agent action: send (or resend) the intake's order to the ERP through MuleSoft.
 */
public with sharing class SubmitOrderToErp {
    private static final Set<String> SUBMITTABLE = new Set<String>{ 'Order Created', 'ERP Failed' };

    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the ERP confirmed the order')
        public Boolean success;
        @InvocableVariable(label='ERP Order Number' description='Order number assigned by the ERP, empty on failure')
        public String erpOrderNumber;
        @InvocableVariable(label='Message' description='ERP confirmation, or the ERP error and suggested next step')
        public String message;
    }

    @InvocableMethod(
        label='Submit Order To ERP'
        description='Sends the Salesforce order of an order intake to the ERP through MuleSoft, or resends it after an ERP failure. Records the ERP order number or the ERP error on the intake.'
    )
    public static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(submitOne(req));
        }
        return results;
    }

    private static Result submitOne(Request req) {
        Result res = new Result();
        res.success = false;
        res.erpOrderNumber = '';
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        // Already sent (for example automatically once the order was created): report it, never send twice
        if (intake.Status__c == 'ERP Confirmed' && String.isNotBlank(intake.ERP_Order_Number__c)) {
            res.success = true;
            res.erpOrderNumber = intake.ERP_Order_Number__c;
            res.message = 'Order ' + intake.Order__r.OrderNumber + ' is already in the ERP as ' + intake.ERP_Order_Number__c
                + '. Intake ' + intake.Name + ' is ERP Confirmed.';
            return res;
        }
        if (intake.Order__c == null || !SUBMITTABLE.contains(intake.Status__c)) {
            res.message = intake.Name + ' cannot be sent to the ERP: status is ' + intake.Status__c
                + (intake.Order__c == null ? ' and no order has been created yet.' : '.');
            return res;
        }

        OrderIntakeErpClient.ErpResponse erp;
        try {
            erp = OrderIntakeErpClient.submit(intake);
        } catch (Exception e) {
            erp = new OrderIntakeErpClient.ErpResponse();
            erp.error = 'Could not reach MuleSoft: ' + e.getMessage();
        }

        Order_Intake__c toSave = new Order_Intake__c(Id = intake.Id);
        if (erp.success) {
            toSave.Status__c = 'ERP Confirmed';
            toSave.ERP_Order_Number__c = erp.erpOrderNumber;
            toSave.ERP_Error__c = null;
        } else {
            toSave.Status__c = 'ERP Failed';
            toSave.ERP_Error__c = erp.error == null ? null : erp.error.left(255);
        }
        update as user toSave;

        res.success = erp.success;
        res.erpOrderNumber = erp.success ? erp.erpOrderNumber : '';
        String suffix = erp.simulated ? ' (simulated ERP: MuleSoft endpoint not configured yet)' : '';
        res.message = erp.success
            ? 'ERP accepted order ' + intake.Order__r.OrderNumber + ' as ' + erp.erpOrderNumber + '. Intake ' + intake.Name + ' is now ERP Confirmed.' + suffix
            : 'ERP rejected order ' + intake.Order__r.OrderNumber + ': ' + erp.error + ' Intake ' + intake.Name + ' is now ERP Failed.' + suffix;
        return res;
    }
}
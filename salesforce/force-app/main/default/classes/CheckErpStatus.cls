/**
 * Agent action: report the ERP state of an intake's order, refreshing it from MuleSoft when configured.
 */
public with sharing class CheckErpStatus {
    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
    }

    public class Result {
        @InvocableVariable(label='Status Summary' description='Intake status, Salesforce order, ERP order number and any ERP error')
        public String statusSummary;
        @InvocableVariable(label='Can Resubmit' description='True when the order failed in the ERP and can be sent again')
        public Boolean canResubmit;
    }

    @InvocableMethod(
        label='Check ERP Status'
        description='Reports whether the order of an order intake reached the ERP: ERP order number when confirmed, or the ERP error when it failed.'
    )
    public static List<Result> check(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(checkOne(req));
        }
        return results;
    }

    private static Result checkOne(Request req) {
        Result res = new Result();
        res.canResubmit = false;
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.statusSummary = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        if (intake.Order__c == null) {
            res.statusSummary = intake.Name + ' has no Salesforce order yet (status ' + intake.Status__c + '), so nothing has been sent to the ERP.';
            return res;
        }

        String erpNumber = intake.ERP_Order_Number__c;
        String erpError = intake.ERP_Error__c;
        String status = intake.Status__c;
        if (OrderIntakeErpClient.isMuleConfigured() && (status == 'Sent to ERP' || status == 'ERP Failed' || status == 'ERP Confirmed')) {
            try {
                OrderIntakeErpClient.ErpResponse live = OrderIntakeErpClient.fetchStatus(intake);
                if (live.success) {
                    erpNumber = live.erpOrderNumber;
                    erpError = null;
                    status = 'ERP Confirmed';
                }
            } catch (Exception e) {
                erpError = (erpError == null ? '' : erpError + ' ') + '(live ERP status unavailable: ' + e.getMessage() + ')';
            }
        }

        res.canResubmit = status == 'ERP Failed';
        res.statusSummary = intake.Name + ' | Order ' + intake.Order__r.OrderNumber + ' (total ' + OrderIntakeService.money(intake.Order__r.TotalAmount) + ')'
            + ' | Status: ' + status
            + (String.isBlank(erpNumber) ? '' : ' | ERP order: ' + erpNumber)
            + (String.isBlank(erpError) ? '' : ' | ERP error: ' + erpError);
        return res;
    }
}
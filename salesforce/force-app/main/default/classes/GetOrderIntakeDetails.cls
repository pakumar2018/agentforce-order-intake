/**
 * Agent action: full details of one order intake, including every extracted line.
 */
public with sharing class GetOrderIntakeDetails {
    public class Request {
        @InvocableVariable(
            label='Intake Reference'
            description='Intake number such as OI-00012 (or just 12), or the customer PO number'
            required=true
        )
        public String intakeReference;
    }

    public class Result {
        @InvocableVariable(label='Details' description='Intake status, customer, email, classification, order, ERP state and every line with its match status')
        public String details;
        @InvocableVariable(label='Intake Number' description='Canonical intake number, for example OI-00012; empty when not found')
        public String intakeNumber;
        @InvocableVariable(label='Found' description='True when the intake exists')
        public Boolean found;
    }

    @InvocableMethod(
        label='Get Order Intake Details'
        description='Returns the full details of one order intake: status, customer, sender, classification, exceptions, order, ERP status and every extracted PO line with its product match and price check.'
    )
    public static List<Result> getDetails(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result res = new Result();
            Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
            res.found = intake != null;
            res.intakeNumber = intake == null ? '' : intake.Name;
            res.details = intake == null ? OrderIntakeService.notFoundMessage(req.intakeReference) : OrderIntakeService.describe(intake);
            results.add(res);
        }
        return results;
    }
}
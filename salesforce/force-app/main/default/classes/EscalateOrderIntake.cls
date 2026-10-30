/**
 * Agent action: hand an intake to a human team by creating a high-priority follow-up task.
 */
public with sharing class EscalateOrderIntake {
    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
        @InvocableVariable(label='Team' description='Team that should take over: Credit, Pricing, Customer Master Data, or Order Desk Supervisor' required=true)
        public String team;
        @InvocableVariable(label='Reason' description='Why the agent or user could not resolve the intake, with the relevant details' required=true)
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the escalation task was created')
        public Boolean success;
        @InvocableVariable(label='Message' description='Confirmation of the escalation')
        public String message;
    }

    @InvocableMethod(
        label='Escalate Order Intake'
        description='Escalates an order intake to a human team (Credit, Pricing, Customer Master Data, or Order Desk Supervisor) by creating a high-priority task on the intake with the reason.'
    )
    public static List<Result> escalate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result res = new Result();
            res.success = false;
            Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
            if (intake == null) {
                res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            } else {
                insert as user new Task(
                    WhatId = intake.Id,
                    Subject = ('Escalation to ' + req.team + ': ' + intake.Name).left(255),
                    Description = req.reason,
                    Priority = 'High',
                    Status = 'Not Started',
                    ActivityDate = Date.today()
                );
                res.success = true;
                res.message = intake.Name + ' escalated to the ' + req.team + ' team with a high-priority task due today.';
            }
            results.add(res);
        }
        return results;
    }
}
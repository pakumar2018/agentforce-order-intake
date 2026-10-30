/**
 * Agent action: email the customer who sent an order intake (confirmation or request for missing details).
 */
public with sharing class SendIntakeCustomerEmail {
    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
        @InvocableVariable(label='Subject' description='Email subject approved by the user' required=true)
        public String subject;
        @InvocableVariable(label='Body' description='Plain-text email body approved by the user' required=true)
        public String body;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the email was sent')
        public Boolean success;
        @InvocableVariable(label='Message' description='Who the email went to, or why it could not be sent')
        public String message;
    }

    @InvocableMethod(
        label='Send Intake Customer Email'
        description='Sends an approved plain-text email to the sender of an order intake and logs it on the intake record.'
    )
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(sendOne(req));
        }
        return results;
    }

    private static Result sendOne(Request req) {
        Result res = new Result();
        res.success = false;
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        if (String.isBlank(intake.Source_Email_From__c)) {
            res.message = intake.Name + ' has no sender email address.';
            return res;
        }
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE Email = :intake.Source_Email_From__c WITH USER_MODE LIMIT 1
        ];
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(req.subject);
        mail.setPlainTextBody(req.body);
        if (contacts.isEmpty()) {
            mail.setToAddresses(new List<String>{ intake.Source_Email_From__c });
            mail.setSaveAsActivity(false);
        } else {
            mail.setTargetObjectId(contacts[0].Id);
            mail.setWhatId(intake.Id);
            mail.setSaveAsActivity(true);
        }
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            res.message = 'The email could not be sent: ' + e.getMessage()
                + ' If email deliverability is off, an admin can set Setup > Deliverability > Access level to All email.';
            return res;
        }
        if (contacts.isEmpty()) {
            insert as user new Task(
                WhatId = intake.Id, Subject = 'Email: ' + req.subject.left(240), Description = req.body,
                Status = 'Completed', ActivityDate = Date.today(), TaskSubtype = 'Email'
            );
        }
        res.success = true;
        res.message = 'Email "' + req.subject + '" sent to ' + intake.Source_Email_From__c + ' and logged on ' + intake.Name + '.';
        return res;
    }
}
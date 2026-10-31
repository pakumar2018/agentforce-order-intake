/**
 * Keeps one review Case per order email that needs a person (OrderIntakeTrigger).
 * Opens a Case when an intake becomes Needs Review, Error or ERP Failed, and closes it once the order is
 * created or the ERP confirms it.
 */
public with sharing class OrderIntakeReviewCases {
    public static final String STATUS_ORDER_CREATED = 'Order Created';
    public static final String STATUS_ERP_CONFIRMED = 'ERP Confirmed';
    public static final String STATUS_ERP_FAILED = 'ERP Failed';
    public static final Set<String> REVIEW_STATUSES = new Set<String>{ OrderIntakeService.STATUS_NEEDS_REVIEW, 'Error', STATUS_ERP_FAILED };
    public static final Set<String> DONE_STATUSES = new Set<String>{ STATUS_ORDER_CREATED, STATUS_ERP_CONFIRMED };

    public static void sync(List<Order_Intake__c> intakes, Map<Id, Order_Intake__c> oldMap) {
        Set<Id> toOpen = new Set<Id>();
        Set<Id> toClose = new Set<Id>();
        for (Order_Intake__c intake : intakes) {
            String oldStatus = oldMap == null ? null : oldMap.get(intake.Id).Status__c;
            if (intake.Status__c == oldStatus) {
                continue;
            }
            if (REVIEW_STATUSES.contains(intake.Status__c)) {
                toOpen.add(intake.Id);
            } else if (DONE_STATUSES.contains(intake.Status__c)) {
                toClose.add(intake.Id);
            }
        }
        if (toOpen.isEmpty() && toClose.isEmpty()) {
            return;
        }

        Set<Id> all = new Set<Id>(toOpen);
        all.addAll(toClose);
        Map<Id, Case> openCaseByIntake = new Map<Id, Case>();
        for (Case c : [SELECT Id, Order_Intake__c FROM Case WHERE Order_Intake__c IN :all AND IsClosed = false]) {
            openCaseByIntake.put(c.Order_Intake__c, c);
        }

        toOpen.removeAll(openCaseByIntake.keySet());
        if (!toOpen.isEmpty()) {
            List<Case> opened = newCases(toOpen);
            insert opened;
            shareFiles(opened);
        }
        List<Case> closed = new List<Case>();
        for (Id intakeId : toClose) {
            Case open = openCaseByIntake.get(intakeId);
            if (open != null) {
                closed.add(new Case(Id = open.Id, Status = 'Closed'));
            }
        }
        update closed;
    }

    /** The email's attachments (on the intake) also appear on the review case. */
    private static void shareFiles(List<Case> cases) {
        Map<Id, Id> caseByIntake = new Map<Id, Id>();
        for (Case c : cases) {
            caseByIntake.put(c.Order_Intake__c, c.Id);
        }
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :caseByIntake.keySet()
        ]) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = link.ContentDocumentId,
                LinkedEntityId = caseByIntake.get(link.LinkedEntityId),
                ShareType = 'V'
            ));
        }
        insert links;
    }

    private static List<Case> newCases(Set<Id> intakeIds) {
        List<Order_Intake__c> intakes = OrderIntakeService.intakesWithLines(intakeIds);
        Set<String> senders = new Set<String>();
        for (Order_Intake__c intake : intakes) {
            if (String.isNotBlank(intake.Source_Email_From__c)) {
                senders.add(intake.Source_Email_From__c);
            }
        }
        Map<String, Contact> contactByEmail = new Map<String, Contact>();
        for (Contact c : [SELECT Id, Email, AccountId FROM Contact WHERE Email IN :senders]) {
            contactByEmail.put(c.Email.toLowerCase(), c);
        }

        List<Case> cases = new List<Case>();
        for (Order_Intake__c intake : intakes) {
            Contact contact = intake.Source_Email_From__c == null ? null : contactByEmail.get(intake.Source_Email_From__c.toLowerCase());
            String topic = String.isNotBlank(intake.Customer_PO_Number__c)
                ? 'PO ' + intake.Customer_PO_Number__c
                : '"' + (intake.Subject__c == null ? 'no subject' : intake.Subject__c) + '"';
            String why = intake.Status__c == 'Error'
                ? 'processing error'
                : intake.Status__c == STATUS_ERP_FAILED
                ? 'ERP rejected the order'
                : (String.isBlank(intake.Exception_Reason__c) ? 'needs review' : intake.Exception_Reason__c.replace(';', ', '));
            cases.add(new Case(
                Order_Intake__c = intake.Id,
                Subject = ('Order email review: ' + topic + ' (' + intake.Name + ') - ' + why).left(255),
                Description = (nextStep(intake) + '\n\n' + OrderIntakeService.describe(intake)
                    + '\n\nEmail body:\n' + (intake.Email_Body__c == null ? '' : intake.Email_Body__c)).left(32000),
                Origin = 'Email',
                Priority = intake.Status__c == 'Error' || intake.Status__c == STATUS_ERP_FAILED ? 'High' : 'Medium',
                SuppliedEmail = intake.Source_Email_From__c,
                AccountId = intake.Account__c != null ? intake.Account__c : (contact == null ? null : contact.AccountId),
                ContactId = contact == null ? null : contact.Id
            ));
        }
        return cases;
    }

    private static String nextStep(Order_Intake__c intake) {
        if (intake.Status__c == 'Error') {
            return 'The order email could not be processed automatically. Check the processing error, then fix or re-send the email.';
        }
        if (intake.Status__c == STATUS_ERP_FAILED) {
            return 'Order ' + intake.Order__r.OrderNumber + ' was created, but the ERP rejected it: ' + intake.ERP_Error__c
                + '\nResolve the problem (for example a credit approval), then resend the order with the Order Intake Assistant '
                + '(for example "Resend ' + intake.Name + ' to the ERP"); this case closes when the ERP confirms the order.';
        }
        return 'The order email could not be turned into an order automatically. Resolve the exceptions with the Order Intake Assistant '
            + '(for example "Show me ' + intake.Name + '"), then create the order; this case closes when the order is created.';
    }
}

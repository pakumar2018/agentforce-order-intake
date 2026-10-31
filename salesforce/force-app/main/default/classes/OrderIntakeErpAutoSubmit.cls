/**
 * Sends an order to the ERP as soon as its intake becomes Order Created (OrderIntakeTrigger), for example when a
 * rep creates the order with the agent after a review. It reuses SubmitOrderToErp, so the intake becomes
 * ERP Confirmed or ERP Failed (with a review Case) exactly as when the rep sends it.
 * Runs as a Queueable: the ERP callout cannot follow the order DML in the same transaction. One intake per job,
 * the rest chained, for the same reason.
 * MuleSoft's straight-through path sends its own orders through /orderintake/v1/erp-submit and waits for the
 * result to reply to the customer, so OrderIntakeExtractionApi sets suppress for those.
 */
public with sharing class OrderIntakeErpAutoSubmit implements Queueable, Database.AllowsCallouts {
    /** Set by a caller that sends the order to the ERP itself. */
    public static Boolean suppress = false;

    private final List<Id> intakeIds;

    public OrderIntakeErpAutoSubmit(List<Id> intakeIds) {
        this.intakeIds = intakeIds;
    }

    public static void enqueue(List<Order_Intake__c> intakes, Map<Id, Order_Intake__c> oldMap) {
        if (suppress) {
            return;
        }
        List<Id> created = new List<Id>();
        for (Order_Intake__c intake : intakes) {
            String oldStatus = oldMap == null ? null : oldMap.get(intake.Id).Status__c;
            if (intake.Status__c == OrderIntakeReviewCases.STATUS_ORDER_CREATED && oldStatus != intake.Status__c && intake.Order__c != null) {
                created.add(intake.Id);
            }
        }
        if (created.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // The order exists; the rep can still send it with the agent ("Send it to the ERP")
            System.debug(LoggingLevel.WARN, 'No queueable job left to send intakes ' + created + ' to the ERP');
            return;
        }
        System.enqueueJob(new OrderIntakeErpAutoSubmit(created));
    }

    public void execute(QueueableContext context) {
        Order_Intake__c intake = [SELECT Name FROM Order_Intake__c WHERE Id = :intakeIds[0] WITH USER_MODE];
        SubmitOrderToErp.Request req = new SubmitOrderToErp.Request();
        req.intakeReference = intake.Name;
        SubmitOrderToErp.submit(new List<SubmitOrderToErp.Request>{ req });

        if (intakeIds.size() > 1) {
            List<Id> rest = intakeIds.clone();
            rest.remove(0);
            System.enqueueJob(new OrderIntakeErpAutoSubmit(rest));
        }
    }
}

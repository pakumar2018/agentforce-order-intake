trigger OrderIntakeTrigger on Order_Intake__c (after insert, after update) {
    OrderIntakeReviewCases.sync(Trigger.new, Trigger.oldMap);
    // Orders created after a review (or by any other path) go to the ERP on their own
    OrderIntakeErpAutoSubmit.enqueue(Trigger.new, Trigger.oldMap);
}

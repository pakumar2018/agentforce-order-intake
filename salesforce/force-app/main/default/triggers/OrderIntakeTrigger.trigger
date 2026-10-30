trigger OrderIntakeTrigger on Order_Intake__c (after insert, after update) {
    OrderIntakeReviewCases.sync(Trigger.new, Trigger.oldMap);
}

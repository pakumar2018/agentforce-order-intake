// Removes the demo intakes and everything created from them (orders, review cases, tasks, logged emails,
// attached PDFs), so the demo can be run again from a clean state. Touches only intakes whose
// Gmail_Message_Id__c starts with "seed-" (seeded) or "gm-" (created from Gmail by MuleSoft).
// Afterwards run seed-demo-intakes.apex. Orders already sent to Odoo must be removed in Odoo separately.
// Run: sf apex run --file scripts/apex/reset-demo-intakes.apex --target-org orderintake

List<Order_Intake__c> intakes = [
    SELECT Id, Order__c FROM Order_Intake__c
    WHERE Gmail_Message_Id__c LIKE 'seed-%' OR Gmail_Message_Id__c LIKE 'gm-%'
];
Set<Id> intakeIds = new Map<Id, Order_Intake__c>(intakes).keySet();
Set<Id> orderIds = new Set<Id>();
for (Order_Intake__c i : intakes) {
    if (i.Order__c != null) orderIds.add(i.Order__c);
}

List<Task> tasks = [SELECT Id FROM Task WHERE WhatId IN :intakeIds];
List<Case> cases = [SELECT Id FROM Case WHERE Order_Intake__c IN :intakeIds];
List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE RelatedToId IN :intakeIds];
List<Order> orders = [SELECT Id FROM Order WHERE Id IN :orderIds AND Status = 'Draft'];
Set<Id> documentIds = new Set<Id>();
if (!intakeIds.isEmpty()) {
    for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :intakeIds]) {
        documentIds.add(link.ContentDocumentId);
    }
}
List<ContentDocument> pdfs = [SELECT Id FROM ContentDocument WHERE Id IN :documentIds];

delete tasks;
delete cases;
delete emails;
delete pdfs;
delete intakes;   // lines are deleted with their intake (master-detail)
delete orders;

System.debug('RESET RESULT: intakes-' + intakes.size() + ' orders-' + orders.size()
    + ' cases-' + cases.size() + ' tasks-' + tasks.size() + ' emails-' + emails.size() + ' pdfs-' + pdfs.size());

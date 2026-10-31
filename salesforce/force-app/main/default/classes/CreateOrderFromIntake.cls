/**
 * Agent action: create the Salesforce order from a fully matched intake.
 * This is the single swap point for Revenue Cloud Advanced order creation.
 */
public with sharing class CreateOrderFromIntake {
    private static final Set<String> READY_STATUSES = new Set<String>{ 'Classified', 'Extracted', 'Needs Review' };

    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the order was created')
        public Boolean success;
        @InvocableVariable(label='Order Number' description='Salesforce order number, empty when not created')
        public String orderNumber;
        @InvocableVariable(label='Message' description='Confirmation with order number and total, or the reason the order could not be created')
        public String message;
    }

    @InvocableMethod(
        label='Create Order From Intake'
        description='Creates the Salesforce order for an order intake whose customer is known and whose lines are all matched. Fails with the reason when the intake still has exceptions or already has an order.'
    )
    public static List<Result> create(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createOne(req));
        }
        return results;
    }

    private static Result createOne(Request req) {
        Result res = new Result();
        res.success = false;
        res.orderNumber = '';
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        List<String> blockers = new List<String>();
        if (intake.Order__c != null) {
            blockers.add('order ' + intake.Order__r.OrderNumber + ' already exists for this intake');
        }
        if (!READY_STATUSES.contains(intake.Status__c)) {
            blockers.add('status is ' + intake.Status__c);
        }
        if (intake.Account__c == null) {
            blockers.add('the customer account is not matched');
        }
        if (intake.Lines__r.isEmpty()) {
            blockers.add('there are no extracted lines');
        }
        Set<Id> productIds = new Set<Id>();
        for (Order_Intake_Line__c line : intake.Lines__r) {
            if (line.Match_Status__c != OrderIntakeService.MATCH_MATCHED || line.Product__c == null) {
                blockers.add('line ' + line.Line_No__c.intValue() + ' is ' + line.Match_Status__c);
            } else if (line.Quantity__c == null || line.Quantity__c <= 0) {
                blockers.add('line ' + line.Line_No__c.intValue() + ' has no quantity');
            } else {
                productIds.add(line.Product__c);
            }
        }
        if (!blockers.isEmpty()) {
            res.message = 'Cannot create the order for ' + intake.Name + ': ' + String.join(blockers, '; ') + '.';
            return res;
        }

        Map<Id, PricebookEntry> entries = OrderIntakeService.listPrices(productIds);
        Order newOrder = new Order(
            AccountId = intake.Account__c,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = OrderIntakeService.standardPricebookId(),
            PoNumber = intake.Customer_PO_Number__c,
            Description = 'Created by the Order Intake agent from ' + intake.Name
        );
        Savepoint sp = Database.setSavepoint();
        try {
            insert as user newOrder;
            List<OrderItem> items = new List<OrderItem>();
            for (Order_Intake_Line__c line : intake.Lines__r) {
                PricebookEntry entry = entries.get(line.Product__c);
                items.add(new OrderItem(
                    OrderId = newOrder.Id,
                    PricebookEntryId = entry.Id,
                    Quantity = line.Quantity__c,
                    UnitPrice = line.Unit_Price_On_PO__c != null ? line.Unit_Price_On_PO__c : entry.UnitPrice
                ));
            }
            insert as user items;
            update as user new Order_Intake__c(Id = intake.Id, Order__c = newOrder.Id, Status__c = 'Order Created', Exception_Reason__c = null);
        } catch (Exception e) {
            Database.rollback(sp);
            res.message = 'Order creation failed for ' + intake.Name + ': ' + e.getMessage();
            return res;
        }

        Order created = [SELECT OrderNumber, TotalAmount FROM Order WHERE Id = :newOrder.Id WITH USER_MODE];
        res.success = true;
        res.orderNumber = created.OrderNumber;
        res.message = 'Created order ' + created.OrderNumber + ' for ' + intake.Account__r.Name
            + ' (PO ' + intake.Customer_PO_Number__c + ') with ' + intake.Lines__r.size() + ' lines, total '
            + OrderIntakeService.money(created.TotalAmount) + '. Intake ' + intake.Name + ' is now Order Created and is being sent to the ERP automatically; check its ERP status in a moment.';
        return res;
    }
}
/**
 * Agent action: correct one PO line (matched product, quantity, price) and recheck it.
 */
public with sharing class UpdateOrderIntakeLine {
    public class Request {
        @InvocableVariable(label='Intake Reference' description='Intake number such as OI-00012, or the customer PO number' required=true)
        public String intakeReference;
        @InvocableVariable(label='Line Number' description='Line number on the PO, as shown in the intake details' required=true)
        public Integer lineNumber;
        @InvocableVariable(label='Product Code' description='Catalog product code to match this line to, for example BRG-2001. Leave empty to keep the current product.')
        public String productCode;
        @InvocableVariable(label='Quantity' description='Corrected quantity. Leave empty to keep the current quantity.')
        public Decimal quantity;
        @InvocableVariable(label='Use List Price' description='True to replace the PO unit price with the catalog list price')
        public Boolean useListPrice;
        @InvocableVariable(label='Accept PO Price' description='True when the user approves the customer PO price even though it differs from list price')
        public Boolean acceptPoPrice;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the line was updated')
        public Boolean success;
        @InvocableVariable(label='Message' description='What changed, the line after the update, and the remaining exceptions on the intake')
        public String message;
    }

    @InvocableMethod(
        label='Update Order Intake Line'
        description='Corrects one extracted PO line: sets the matched catalog product, quantity, or price (use list price or accept the PO price), then rechecks the line and the intake exceptions.'
    )
    public static List<Result> updateLine(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(apply(req));
        }
        return results;
    }

    private static Result apply(Request req) {
        Result res = new Result();
        res.success = false;
        Order_Intake__c intake = OrderIntakeService.findIntake(req.intakeReference);
        if (intake == null) {
            res.message = OrderIntakeService.notFoundMessage(req.intakeReference);
            return res;
        }
        if (intake.Order__c != null) {
            res.message = intake.Name + ' already has order ' + intake.Order__r.OrderNumber + '; its lines can no longer be changed.';
            return res;
        }
        Order_Intake_Line__c line;
        for (Order_Intake_Line__c candidate : intake.Lines__r) {
            if (candidate.Line_No__c != null && candidate.Line_No__c.intValue() == req.lineNumber) {
                line = candidate;
            }
        }
        if (line == null) {
            res.message = intake.Name + ' has no line ' + req.lineNumber + '.';
            return res;
        }

        if (String.isNotBlank(req.productCode)) {
            List<Product2> products = [
                SELECT Id, ProductCode, Name FROM Product2
                WHERE ProductCode = :req.productCode.trim() AND IsActive = true
                WITH USER_MODE LIMIT 1
            ];
            if (products.isEmpty()) {
                res.message = 'No active product with code ' + req.productCode + '. Use Suggest Product Matches to find the right code.';
                return res;
            }
            line.Product__c = products[0].Id;
            line.Product__r = products[0];
        }
        if (line.Product__c != null) {
            PricebookEntry price = OrderIntakeService.listPrices(new Set<Id>{ line.Product__c }).get(line.Product__c);
            line.List_Price__c = price == null ? null : price.UnitPrice;
        }
        if (req.quantity != null) {
            if (req.quantity <= 0) {
                res.message = 'Quantity must be greater than zero.';
                return res;
            }
            line.Quantity__c = req.quantity;
        }
        if (req.useListPrice == true && line.List_Price__c != null) {
            line.Unit_Price_On_PO__c = line.List_Price__c;
        }
        OrderIntakeService.applyMatchStatus(line);
        if (req.acceptPoPrice == true && line.Match_Status__c == OrderIntakeService.MATCH_PRICE) {
            line.Match_Status__c = OrderIntakeService.MATCH_MATCHED;
        }

        Order_Intake_Line__c toSave = new Order_Intake_Line__c(
            Id = line.Id,
            Product__c = line.Product__c,
            List_Price__c = line.List_Price__c,
            Quantity__c = line.Quantity__c,
            Unit_Price_On_PO__c = line.Unit_Price_On_PO__c,
            Match_Status__c = line.Match_Status__c
        );
        update as user toSave;

        OrderIntakeService.refreshExceptions(intake, intake.Lines__r);
        update as user new Order_Intake__c(Id = intake.Id, Exception_Reason__c = intake.Exception_Reason__c, Status__c = intake.Status__c);

        res.success = true;
        res.message = 'Updated. ' + OrderIntakeService.describeLine(line)
            + '\nIntake ' + intake.Name + ' is now ' + intake.Status__c
            + (String.isBlank(intake.Exception_Reason__c) ? ' with no open exceptions.' : ' with open exceptions: ' + intake.Exception_Reason__c.replace(';', ', ') + '.');
        return res;
    }
}
/**
 * Agent action: search order intakes by free text and/or status.
 */
public with sharing class FindOrderIntakes {
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Needs Review', 'ERP Failed', 'Error' };

    public class Request {
        @InvocableVariable(
            label='Search Text'
            description='Optional text to match against intake number, customer PO number, customer name, email sender or subject'
        )
        public String searchText;
        @InvocableVariable(
            label='Status Filter'
            description='Optional exact status (Received, Classified, Extracted, Needs Review, Order Created, Sent to ERP, ERP Confirmed, ERP Failed, Not Order, Error) or "open" for everything needing attention'
        )
        public String statusFilter;
    }

    public class Result {
        @InvocableVariable(label='Summary' description='One line per matching intake, newest first')
        public String summary;
        @InvocableVariable(label='Match Count' description='Number of intakes returned')
        public Integer matchCount;
    }

    @InvocableMethod(
        label='Find Order Intakes'
        description='Searches order intake emails by intake number, PO number, customer, sender or subject, optionally filtered by status. Returns up to 10 newest matches.'
    )
    public static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(search(req));
        }
        return results;
    }

    private static Result search(Request req) {
        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        if (String.isNotBlank(req.searchText)) {
            binds.put('exact', req.searchText.trim());
            binds.put('likeText', '%' + req.searchText.trim() + '%');
            conditions.add('(Name = :exact OR Customer_PO_Number__c = :exact OR Account__r.Name LIKE :likeText'
                + ' OR Source_Email_From__c LIKE :likeText OR Subject__c LIKE :likeText)');
        }
        if (String.isNotBlank(req.statusFilter)) {
            if (req.statusFilter.trim().equalsIgnoreCase('open')) {
                binds.put('statuses', OPEN_STATUSES);
            } else {
                binds.put('statuses', new Set<String>{ req.statusFilter.trim() });
            }
            conditions.add('Status__c IN :statuses');
        }
        String soql = 'SELECT Id, Name, Status__c, Customer_PO_Number__c, Received_At__c, Exception_Reason__c,'
            + ' Account__c, Account__r.Name FROM Order_Intake__c'
            + (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND '))
            + ' ORDER BY Received_At__c DESC NULLS LAST, CreatedDate DESC LIMIT 10';
        List<Order_Intake__c> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

        Result res = new Result();
        res.matchCount = rows.size();
        if (rows.isEmpty()) {
            res.summary = 'No order intakes match that search.';
        } else {
            List<String> lines = new List<String>();
            for (Order_Intake__c row : rows) {
                lines.add(OrderIntakeService.headline(row));
            }
            res.summary = String.join(lines, '\n');
        }
        return res;
    }
}
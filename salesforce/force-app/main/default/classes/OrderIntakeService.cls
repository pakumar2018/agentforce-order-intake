/**
 * Shared logic for the Order Intake agent actions: finding intakes, describing them
 * as agent-readable text, list-price lookup and line/exception status recalculation.
 */
public with sharing class OrderIntakeService {
    /** A PO price more than 5% away from list price is flagged as a price mismatch. */
    public static final Decimal PRICE_TOLERANCE = 0.05;

    public static final String STATUS_NEEDS_REVIEW = 'Needs Review';
    public static final String STATUS_EXTRACTED = 'Extracted';
    public static final String MATCH_MATCHED = 'Matched';
    public static final String MATCH_UNMATCHED = 'Unmatched';
    public static final String MATCH_SUGGESTED = 'Suggested';
    public static final String MATCH_PRICE = 'Price Mismatch';
    public static final String REASON_UNKNOWN_SKU = 'Unknown SKU';
    public static final String REASON_PRICE = 'Price Mismatch';

    public static Id standardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }

    /** Accepts an intake number (OI-00012, or just 12) or a customer PO number. */
    public static Order_Intake__c findIntake(String reference) {
        if (String.isBlank(reference)) {
            return null;
        }
        String ref = reference.trim();
        String intakeName = ref.isNumeric() ? 'OI-' + ref.leftPad(5, '0') : ref.toUpperCase();
        List<Order_Intake__c> rows = [
            SELECT Id FROM Order_Intake__c
            WHERE Name = :intakeName OR Customer_PO_Number__c = :ref
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : intakesWithLines(new Set<Id>{ rows[0].Id })[0];
    }

    /** Intakes with everything describe() shows: lines, order, ERP result and review cases. */
    public static List<Order_Intake__c> intakesWithLines(Set<Id> intakeIds) {
        return [
            SELECT Id, Name, Status__c, Classification__c, Classification_Confidence__c,
                Exception_Reason__c, Customer_PO_Number__c, Source_Email_From__c, Subject__c, Email_Body__c,
                Received_At__c, Account__c, Account__r.Name, Account__r.AccountNumber,
                Order__c, Order__r.OrderNumber, Order__r.TotalAmount, Extraction_Source__c,
                ERP_Order_Number__c, ERP_Error__c, Extraction_Confidence__c, Processing_Error__c,
                (SELECT Id, Name, Line_No__c, Raw_SKU__c, Raw_Description__c, Quantity__c,
                    Unit_Price_On_PO__c, Product__c, Product__r.ProductCode, Product__r.Name,
                    List_Price__c, Match_Status__c
                 FROM Lines__r ORDER BY Line_No__c),
                (SELECT CaseNumber, Status FROM Review_Cases__r ORDER BY CreatedDate DESC)
            FROM Order_Intake__c
            WHERE Id IN :intakeIds
            WITH USER_MODE
        ];
    }

    public static String notFoundMessage(String reference) {
        return 'No order intake found for "' + reference + '". Ask for the intake number (for example OI-00012) or the customer PO number.';
    }

    /** One-line summary used in search results. */
    public static String headline(Order_Intake__c intake) {
        List<String> parts = new List<String>{
            intake.Name,
            'Status: ' + intake.Status__c,
            'Customer: ' + (intake.Account__c == null ? 'not matched' : intake.Account__r.Name),
            'PO: ' + valueOr(intake.Customer_PO_Number__c, 'none'),
            'Received: ' + (intake.Received_At__c == null ? 'unknown' : intake.Received_At__c.format('yyyy-MM-dd HH:mm'))
        };
        if (String.isNotBlank(intake.Exception_Reason__c)) {
            parts.add('Exceptions: ' + intake.Exception_Reason__c.replace(';', ', '));
        }
        return String.join(parts, ' | ');
    }

    /** Full multi-line description including every extracted line. */
    public static String describe(Order_Intake__c intake) {
        List<String> out = new List<String>{ headline(intake) };
        out.add('Email: from ' + valueOr(intake.Source_Email_From__c, 'unknown') + ', subject "' + valueOr(intake.Subject__c, '') + '"');
        if (intake.Classification__c != null) {
            out.add('Classification: ' + intake.Classification__c + confidence(intake.Classification_Confidence__c));
        }
        if (intake.Extraction_Confidence__c != null) {
            out.add('Extraction confidence:' + confidence(intake.Extraction_Confidence__c).replace('(', '').replace(')', '')
                + (String.isBlank(intake.Extraction_Source__c) ? '' : ', read from the ' + intake.Extraction_Source__c));
        }
        List<Case> cases = intake.Review_Cases__r;
        if (cases != null && !cases.isEmpty()) {
            out.add('Review case: ' + cases[0].CaseNumber + ' (' + cases[0].Status + ')');
        }
        out.add('Order: ' + (intake.Order__c == null ? 'not created yet' : intake.Order__r.OrderNumber
            + ' (total ' + money(intake.Order__r.TotalAmount) + ')'));
        if (String.isNotBlank(intake.ERP_Order_Number__c) || String.isNotBlank(intake.ERP_Error__c)) {
            out.add('ERP: ' + valueOr(intake.ERP_Order_Number__c, 'no ERP number')
                + (String.isNotBlank(intake.ERP_Error__c) ? ' | ERP error: ' + intake.ERP_Error__c : ''));
        }
        if (String.isNotBlank(intake.Processing_Error__c)) {
            out.add('Processing error: ' + intake.Processing_Error__c);
        }
        List<Order_Intake_Line__c> lines = intake.Lines__r;
        if (lines == null || lines.isEmpty()) {
            out.add('Lines: none extracted');
        } else {
            out.add('Lines:');
            for (Order_Intake_Line__c line : lines) {
                out.add(describeLine(line));
            }
        }
        return String.join(out, '\n');
    }

    public static String describeLine(Order_Intake_Line__c line) {
        String text = 'Line ' + (line.Line_No__c == null ? '?' : String.valueOf(line.Line_No__c.intValue()))
            + ': PO SKU "' + valueOr(line.Raw_SKU__c, '') + '" "' + valueOr(line.Raw_Description__c, '') + '"'
            + ', qty ' + (line.Quantity__c == null ? '?' : line.Quantity__c.stripTrailingZeros().toPlainString())
            + ' @ ' + money(line.Unit_Price_On_PO__c)
            + ' -> ' + valueOr(line.Match_Status__c, MATCH_UNMATCHED);
        if (line.Product__c != null) {
            text += ' to ' + line.Product__r.ProductCode + ' ' + line.Product__r.Name + ' (list ' + money(line.List_Price__c) + ')';
            Decimal variance = variance(line.Unit_Price_On_PO__c, line.List_Price__c);
            if (variance != null && variance != 0) {
                text += ', PO price ' + (variance > 0 ? '+' : '') + (variance * 100).setScale(1) + '% vs list';
            }
        }
        return text;
    }

    public static Map<Id, PricebookEntry> listPrices(Set<Id> productIds) {
        Map<Id, PricebookEntry> byProduct = new Map<Id, PricebookEntry>();
        Id pricebookId = standardPricebookId();
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds AND IsActive = true
            WITH USER_MODE
        ]) {
            byProduct.put(entry.Product2Id, entry);
        }
        return byProduct;
    }

    public static Decimal variance(Decimal poPrice, Decimal listPrice) {
        if (poPrice == null || listPrice == null || listPrice == 0) {
            return null;
        }
        return (poPrice - listPrice) / listPrice;
    }

    /** Sets Match_Status__c from the matched product and price variance. */
    public static void applyMatchStatus(Order_Intake_Line__c line) {
        if (line.Product__c == null) {
            line.Match_Status__c = MATCH_UNMATCHED;
            return;
        }
        Decimal v = variance(line.Unit_Price_On_PO__c, line.List_Price__c);
        line.Match_Status__c = (v != null && Math.abs(v) > PRICE_TOLERANCE) ? MATCH_PRICE : MATCH_MATCHED;
    }

    /**
     * Rebuilds the SKU and price exception reasons from the lines, keeping other reasons
     * (Low Confidence, Unknown Customer, Missing Field), and moves the intake between
     * Needs Review and Extracted accordingly.
     */
    public static void refreshExceptions(Order_Intake__c intake, List<Order_Intake_Line__c> lines) {
        Set<String> reasons = new Set<String>();
        if (String.isNotBlank(intake.Exception_Reason__c)) {
            reasons.addAll(intake.Exception_Reason__c.split(';'));
        }
        reasons.remove(REASON_UNKNOWN_SKU);
        reasons.remove(REASON_PRICE);
        for (Order_Intake_Line__c line : lines) {
            if (line.Match_Status__c == MATCH_UNMATCHED || line.Match_Status__c == MATCH_SUGGESTED) {
                reasons.add(REASON_UNKNOWN_SKU);
            } else if (line.Match_Status__c == MATCH_PRICE) {
                reasons.add(REASON_PRICE);
            }
        }
        if (intake.Account__c != null) {
            reasons.remove('Unknown Customer');
        }
        intake.Exception_Reason__c = reasons.isEmpty() ? null : String.join(new List<String>(reasons), ';');
        if (reasons.isEmpty() && intake.Status__c == STATUS_NEEDS_REVIEW) {
            intake.Status__c = STATUS_EXTRACTED;
        } else if (!reasons.isEmpty() && intake.Status__c == STATUS_EXTRACTED) {
            intake.Status__c = STATUS_NEEDS_REVIEW;
        }
    }

    public static String money(Decimal amount) {
        return amount == null ? '?' : amount.setScale(2).format();
    }

    private static String confidence(Decimal pct) {
        return pct == null ? '' : ' (' + pct.setScale(0) + '% confidence)';
    }

    private static String valueOr(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }
}

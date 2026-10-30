/**
 * Agent action: suggest catalog products for an unrecognised SKU or description on a PO line.
 */
public with sharing class SuggestProductMatches {
    public class Request {
        @InvocableVariable(label='SKU Text' description='The SKU or part number as written on the PO')
        public String skuText;
        @InvocableVariable(label='Description Text' description='The item description as written on the PO')
        public String descriptionText;
    }

    public class Result {
        @InvocableVariable(label='Suggestions' description='Up to 3 candidate products with product code, name and list price, best first')
        public String suggestions;
        @InvocableVariable(label='Suggestion Count' description='Number of candidates found')
        public Integer suggestionCount;
    }

    private class Candidate implements Comparable {
        Product2 product;
        Integer score;
        Candidate(Product2 product, Integer score) {
            this.product = product;
            this.score = score;
        }
        public Integer compareTo(Object other) {
            return ((Candidate) other).score - score;
        }
    }

    @InvocableMethod(
        label='Suggest Product Matches'
        description='Finds the closest catalog products for a PO line whose SKU was not recognised, using the SKU and description text. Returns up to 3 candidates with product code, name and list price.'
    )
    public static List<Result> suggest(List<Request> requests) {
        List<Product2> catalog = [
            SELECT Id, ProductCode, Name FROM Product2 WHERE IsActive = true WITH USER_MODE LIMIT 2000
        ];
        Map<Id, PricebookEntry> prices = OrderIntakeService.listPrices(new Map<Id, Product2>(catalog).keySet());

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(rank(req, catalog, prices));
        }
        return results;
    }

    private static Result rank(Request req, List<Product2> catalog, Map<Id, PricebookEntry> prices) {
        String sku = normalize(req.skuText);
        Set<String> wanted = tokens((req.descriptionText == null ? '' : req.descriptionText) + ' ' + (req.skuText == null ? '' : req.skuText));
        List<Candidate> candidates = new List<Candidate>();
        for (Product2 p : catalog) {
            String code = normalize(p.ProductCode);
            Integer score = 0;
            if (String.isNotBlank(sku) && code == sku) {
                score += 100;
            } else if (String.isNotBlank(sku) && String.isNotBlank(code) && (code.contains(sku) || sku.contains(code))) {
                score += 60;
            }
            for (String t : tokens(p.Name + ' ' + p.ProductCode)) {
                if (wanted.contains(t)) {
                    score += 10;
                }
            }
            if (score > 0) {
                candidates.add(new Candidate(p, score));
            }
        }
        candidates.sort();

        Result res = new Result();
        List<String> lines = new List<String>();
        for (Integer i = 0; i < Math.min(3, candidates.size()); i++) {
            Product2 p = candidates[i].product;
            PricebookEntry price = prices.get(p.Id);
            lines.add((i + 1) + '. ' + p.ProductCode + ' - ' + p.Name + ' (list ' + OrderIntakeService.money(price == null ? null : price.UnitPrice) + ')');
        }
        res.suggestionCount = lines.size();
        res.suggestions = lines.isEmpty() ? 'No similar catalog products found.' : String.join(lines, '\n');
        return res;
    }

    private static String normalize(String value) {
        return value == null ? '' : value.toUpperCase().replaceAll('[^A-Z0-9]', '');
    }

    private static Set<String> tokens(String value) {
        Set<String> result = new Set<String>();
        for (String t : value.toLowerCase().split('[^a-z0-9]+')) {
            if (t.length() >= 3) {
                result.add(t);
            }
        }
        return result;
    }
}
%dw 2.0

// Merges the two readings of a purchase-order email into the one extraction Salesforce receives
// (POST /services/apexrest/orderintake/v1/extraction):
//   body:       the Extract_Order_From_Email prompt template on the email body (every purchase order)
//   attachment: the PO attachment read with Azure Document Intelligence (PDF and images: invoice model;
//               Word and Excel: layout model, then the Extract_Order_From_Document prompt template),
//               or null when the email has no readable attachment
// Lines come from the attachment when it has any, otherwise from the body. PO number, customer number and
// customer name come from the attachment and the body fills gaps. When both name a PO number and they differ,
// the attachment's is kept and error is set, so Salesforce flags the intake for review.
// Confidence is the lower of the two when the body contributed, otherwise the attachment's.

var headerFields = ["poNumber", "customerNumber", "customerName"]

fun present(v) = v != null and not isBlank(v as String)

// "PO-7803", "po 7803" and "7803" are the same purchase order
fun poKey(po) = (upper(po as String) replace /[^A-Z0-9]/ with "") replace /^PO/ with ""

fun readJson(text) = if (present(text)) read(text as String, "application/json") else null

fun mergeExtractions(body, attachment, attachmentName) = do {
    var b = body default {}
    var a = attachment
    var attachmentLines = if (a == null) [] else (a.lines default [])
    var bodyLines = b.lines default []
    var linesFromBody = isEmpty(attachmentLines)
    var filledFromBody = if (a == null) headerFields
        else headerFields filter ((field) -> (not present(a[field])) and present(b[field]))
    var bodyUsed = a == null or (linesFromBody and not isEmpty(bodyLines)) or not isEmpty(filledFromBody)
    var poMismatch = a != null and present(a.poNumber) and present(b.poNumber) and poKey(a.poNumber) != poKey(b.poNumber)
    var header = headerFields reduce ((field, acc = {}) ->
        acc ++ { (field): if (a != null and present(a[field])) a[field] else if (present(b[field])) b[field] else null })
    var confidences = (if (a == null) [] else [a.extractionConfidence]) ++ (if (bodyUsed) [b.extractionConfidence] else [])
    var known = confidences filter ((c) -> c != null)
    ---
    header ++ {
        extractionConfidence: if (isEmpty(known)) null else min(known),
        lines: if (linesFromBody) bodyLines else attachmentLines,
        source: if (a == null) "email body"
            else "attachment " ++ (attachmentName default "") ++ (if (bodyUsed) " + email body" else ""),
        error: if (poMismatch)
                "PO number " ++ (a.poNumber as String) ++ " in the attachment differs from " ++ (b.poNumber as String)
                    ++ " in the email body; the attachment's was used. Check with the customer."
            else null,
        rawPayload: write({
            lineSource: if (a == null) "email body" else if (linesFromBody) "email body" else "attachment",
            filledFromBody: if (a == null) [] else filledFromBody,
            attachment: if (a == null) null else readJson(a.rawPayload),
            emailBody: readJson(b.rawPayload)
        }, "application/json")
    }
}

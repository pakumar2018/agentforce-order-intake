%dw 2.0
output application/json
// Maps the Extract_Order_From_Email prompt template generation to the Salesforce extraction contract
// (POST /services/apexrest/orderintake/v1/extraction), the same shape azure-to-extraction.dwl produces.
// The template answers with one line of JSON; strip code fences in case the model adds them.
var answer = read(((payload.generations[0].text default "{}") replace /```(json)?/ with ""), "application/json")

fun text(v) = do {
    var t = if (v == null) "" else trim(v as String)
    ---
    if (isEmpty(t) or lower(t) == "null") null else t
}
fun number(v) = if (v is Number) v
    else do {
        var c = if (v == null) "" else ((v as String) replace /[^0-9.\-]/ with "")
        ---
        if (isEmpty(c)) null else c as Number
    }
---
{
    extractionConfidence: if (answer.confidence is Number) round(answer.confidence * 1000) / 10 else null,
    poNumber: text(answer.poNumber),
    customerName: text(answer.customerName),
    customerNumber: text(answer.customerNumber),
    lines: ((answer.lines default []) filter ((l) -> l != null)) map ((l, index) -> {
        lineNo: index + 1,
        sku: text(l.sku),
        description: text(l.description),
        quantity: number(l.quantity),
        unitPrice: number(l.unitPrice)
    }),
    rawPayload: write(answer, "application/json")
}

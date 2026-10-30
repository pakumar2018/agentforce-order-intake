%dw 2.0
output application/json
// Maps an Azure Document Intelligence prebuilt-invoice result to the Salesforce extraction contract
// (POST /services/apexrest/orderintake/v1/extraction).
// Header: PurchaseOrder and CustomerId from the invoice fields. On a PO the invoice model labels the buyer
// "Vendor", so customer matching relies on the sender email and CustomerId, with CustomerName as a fallback.
// Lines: read from the detected line-item table (header cells such as "Item Code", "Qty", "Unit Price").
// The invoice Items field can merge several PO rows into one item, so it is only a fallback.
var result = payload.analyzeResult default {}
var fields = result.documents[0].fields default {}
var items = fields.Items.valueArray default []

fun str(f) = do {
    var s = if (f == null) "" else trim(((f.valueString default f.content) default "") as String)
    ---
    if (isEmpty(s)) null else s
}
fun num(f) = if (f == null) null else (f.valueNumber default f.valueCurrency.amount)
fun text(s) = do {
    var t = if (s == null) "" else trim((s as String) replace /\s+/ with " ")
    ---
    if (isEmpty(t)) null else t
}
fun toNum(s) = do {
    var c = if (s == null) "" else ((s as String) replace /[^0-9.\-]/ with "")
    ---
    if (isEmpty(c)) null else c as Number
}

// ---- Lines from the detected table
fun headerColumn(headers, pattern) = do {
    var hits = headers filter ((h) -> lower(text(h.content) default "") matches pattern)
    ---
    if (isEmpty(hits)) null else hits[0].columnIndex
}
var lineTables = (result.tables default []) map ((t) -> do {
        var headers = (t.cells default []) filter ((c) -> c.kind == "columnHeader")
        ---
        {
            cells: t.cells default [],
            headerRows: headers map ((h) -> h.rowIndex) distinctBy $,
            sku: headerColumn(headers, /.*(item code|item no|sku|product code|part).*/),
            desc: headerColumn(headers, /.*desc.*/),
            qty: headerColumn(headers, /.*(qty|quantity).*/),
            price: headerColumn(headers, /.*unit price.*|price/)
        }
    }) filter ((t) -> t.sku != null and t.qty != null)

fun cellText(rowCells, column) =
    if (column == null) null
    else do {
        var hits = rowCells filter ((c) -> c.columnIndex == column)
        ---
        if (isEmpty(hits)) null else text(hits[0].content)
    }

var tableLines = if (isEmpty(lineTables)) [] else do {
        var lt = lineTables[0]
        var bodyCells = lt.cells filter ((c) -> c.kind != "columnHeader" and not (lt.headerRows contains c.rowIndex))
        var rowNumbers = (bodyCells map ((c) -> c.rowIndex)) distinctBy $ orderBy $
        ---
        (rowNumbers map ((r) -> do {
            var rowCells = bodyCells filter ((c) -> c.rowIndex == r)
            ---
            {
                sku: cellText(rowCells, lt.sku),
                description: cellText(rowCells, lt.desc),
                quantity: toNum(cellText(rowCells, lt.qty)),
                unitPrice: toNum(cellText(rowCells, lt.price))
            }
        })) filter ((l) -> l.sku != null and l.quantity != null)
    }

// ---- Fallback: the invoice Items field
var itemLines = items map ((item) -> do {
        var row = item.valueObject default {}
        ---
        { sku: str(row.ProductCode), description: str(row.Description), quantity: num(row.Quantity), unitPrice: num(row.UnitPrice) }
    })

var lines = if (isEmpty(tableLines)) itemLines else tableLines

// Confidence of the header fields the order depends on, plus the Items confidence when lines come from Items
var scored = ([fields.PurchaseOrder, fields.CustomerId]
    ++ (if (isEmpty(tableLines)) (items flatMap ((item) -> [item.valueObject.ProductCode, item.valueObject.Quantity, item.valueObject.UnitPrice])) else []))
    filter ((f) -> f != null and (f.confidence is Number))
---
{
    extractionConfidence: if (isEmpty(scored)) null else round(avg(scored map ((f) -> f.confidence)) * 1000) / 10,
    poNumber: str(fields.PurchaseOrder),
    customerName: str(fields.CustomerName) default str(fields.VendorName),
    customerNumber: str(fields.CustomerId),
    lines: lines map ((l, index) -> l ++ { lineNo: index + 1 }),
    // Extracted fields and the line source, not the per-word OCR data
    rawPayload: write({ lineSource: if (isEmpty(tableLines)) "invoice Items" else "detected table", fields: fields }, "application/json")
}

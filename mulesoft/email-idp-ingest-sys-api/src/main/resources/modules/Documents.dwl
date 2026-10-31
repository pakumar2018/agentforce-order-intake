%dw 2.0

// Which attachment holds the purchase order, and how Azure Document Intelligence reads it.
//   invoice: PDF and images, read by the prebuilt invoice model (PO fields + line table)
//   office:  Word, Excel, PowerPoint and HTML, which the invoice model does not accept; the layout model
//            returns their text and tables as markdown, and the email-body prompt template reads that
var contentTypes = {
    pdf: "application/pdf",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    bmp: "image/bmp",
    tif: "image/tiff",
    tiff: "image/tiff",
    heif: "image/heif",
    docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    html: "text/html",
    htm: "text/html"
}
var officeExtensions = ["docx", "xlsx", "pptx", "html", "htm"]

fun extension(name) = lower(((((name default "") as String) match /.*\.([A-Za-z0-9]+)$/)[1]) default "")

fun contentType(name) = contentTypes[extension(name)] default "application/octet-stream"

fun readMode(name) = do {
    var ext = extension(name)
    ---
    if (officeExtensions contains ext) "office"
    else if (contentTypes[ext] != null) "invoice"
    else null
}

// PDF first, then images, then Office files; null when no attachment can be read
fun poDocument(attachments) = do {
    var readable = (attachments default []) filter ((a) -> readMode(a.name) != null)
    var rank = (a) -> if (extension(a.name) == "pdf") 0 else if (readMode(a.name) == "invoice") 1 else 2
    var sorted = readable orderBy rank($)
    ---
    if (isEmpty(sorted)) null else sorted[0] ++ { readMode: readMode(sorted[0].name), contentType: contentType(sorted[0].name) }
}

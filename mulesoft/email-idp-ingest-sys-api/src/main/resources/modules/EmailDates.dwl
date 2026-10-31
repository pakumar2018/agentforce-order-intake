%dw 2.0
import try from dw::Runtime

// When the email was sent, in UTC, for Salesforce (Received_At__c).
// Uses the RFC 5322 Date header ("Fri, 30 Oct 2026 23:14:34 -0400 (EDT)"), which carries its own offset.
// The connector's receivedDate has no time zone, so it is not reliable across runtimes.
fun receivedIso(dateHeader) = do {
    var cleaned = trim(((dateHeader default "") as String)
        replace /\([^)]*\)/ with ""
        replace /^[A-Za-z]{3},\s*/ with "")
    var parsed = try(() -> cleaned as DateTime {format: "d MMM yyyy HH:mm:ss Z", locale: "en"})
    var sent = if (parsed.success) parsed.result else now()
    ---
    (sent >> "UTC") as String {format: "yyyy-MM-dd'T'HH:mm:ss'Z'"}
}

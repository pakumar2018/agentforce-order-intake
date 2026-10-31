# email-idp-ingest-sys-api (Agentforce Order Intake)

Reads purchase-order emails from Gmail, classifies them with Agentforce, reads the PO PDF with
**Azure AI Document Intelligence**, and creates Order Intake records in Salesforce for the
**Order Intake Assistant** agent.

```
Gmail label "Orders"
  -> Salesforce Order_Intake__c (upsert on a hash of the Gmail Message-ID, every attachment stored as the original file)
  -> Agentforce prompt template Classify_Order_Email (Purchase Order / Change Order / Inquiry / Other);
     it sees the subject, the plain-text body and the attachment file names
  -> Purchase Order: prompt template Extract_Order_From_Email reads the email body, and the PO attachment is read too
     (PDF/image: Azure prebuilt invoice model; Word/Excel: Azure layout model + prompt template
     Extract_Order_From_Document); modules/Extractions.dwl merges the two readings
       -> Salesforce Apex REST /orderintake/v1/extraction builds the lines, matches the customer
          (sender email, then CustomerId on the PO) and products, and sets status
          Extracted (clean) or Needs Review (with exceptions); a clean PO becomes an order
       -> order.autoSubmitErp: Apex REST /orderintake/v1/erp-submit sends it to the ERP;
          ERP Confirmed -> reply with the ERP order number; ERP Failed -> no reply, review Case
  -> email moved to Processed / Needs-Review / Not-Order
```

| File | Purpose |
|---|---|
| `src/main/mule/emailToIDP.xml` | Gmail listener and routing |
| `src/main/mule/salesforce-api.xml` | Salesforce REST calls (client credentials) |
| `src/main/mule/azure-docintel.xml` | Azure Document Intelligence analysis and polling |
| `src/main/resources/dw/azure-to-extraction.dwl` | Maps the Azure result (PurchaseOrder, CustomerId, Items) to Salesforce |
| `src/main/resources/modules/Extractions.dwl` | Merges the email-body and attachment extractions |
| `src/main/resources/modules/Documents.dwl` | Picks the PO attachment and Azure model; keeps attachments as their original bytes |
| `src/main/resources/mule-app-dev.properties` | Non-secret settings |
| `src/test/resources/azure-invoice-po-45188.json` | Real Azure result for the PO 45188 demo PDF, used by MUnit |

## Changes from the original project
- Fixed: `${secure::email.password}` without the Secure Properties module (app would not start).
- Fixed: `mule.env` was never defined (now defaults to `dev`).
- Fixed: variables written as `"# [payload]"` (a space after `#` makes them plain text, not expressions).
- Fixed: attachment content was dropped; IMAP attribute names (`messageId`, `from`) did not exist.
- Fixed: MUnit 3.4.0 cannot start the Mule 4.11 runtime; upgraded to MUnit 3.7.0.
- Fixed: the IMAPS connection requires a TLS context; it validates Gmail's certificate against the JVM's default CAs.
- Fixed: DataWeave expressions mixing JSON responses and Java values now declare `output application/java`.
- Fixed: Gmail Message-IDs ("...@mail.gmail.com") broke the Salesforce upsert URL; the key is now a SHA-1 hash.
- Fixed: Gmail senders arrive as "Name <address>"; only the address is stored.
- Removed: unused log4j/POI/PDFBox/sockets dependencies, `insecure="true"` TLS, and the placeholder conversion service.
- Added: Salesforce, Agentforce classification, Azure extraction, Gmail re-labelling, duplicate protection, MUnit tests.

## Secrets
Never stored in files. In Studio: **Run Configurations → Arguments → VM arguments**:
```
-M-Demail.password=GMAIL_APP_PASSWORD -M-Dsf.clientId=... -M-Dsf.clientSecret=... -M-Docr.apiKey=AZURE_KEY1
```
On CloudHub, add them under **Properties**; they are hidden because `mule-artifact.json` lists them as secure properties.

| Property | Where it comes from |
|---|---|
| `email.password` | Gmail → Google Account → Security → App passwords (needs 2-Step Verification) |
| `sf.clientId` / `sf.clientSecret` | Salesforce External Client App with **client credentials flow**, run-as user with the **Order Intake Integration** permission set |
| `ocr.apiKey` | Azure Portal → Document Intelligence resource → **Keys and Endpoint** → KEY 1 |

## Build and test
`mvn clean package` builds the app and runs the MUnit tests (Mule 4.11, Java 17). In Studio: right-click
`src/test/munit/emailToIDP-test-suite.xml` → **Run MUnit suite**.

## Run
1. Import: **File → Import → Anypoint Studio project from File System** → this folder.
2. Add the VM arguments above → **Run**.
3. From `demo.dealer.po@gmail.com` (with a customer alias in **From**), email a PO PDF to `demo.orders.po@gmail.com` (Gmail filter applies the **Orders** label).
4. Within a minute: a new Order Intake in Salesforce (Order Desk app), and the email moves to **Processed** or **Needs-Review**.

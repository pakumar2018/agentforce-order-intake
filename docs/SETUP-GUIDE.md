# Setup guide: Order Intake Assistant

How to recreate the full solution in a new environment. All data is fictional; no credentials are stored in
any repository.

## Components and repositories
| Component | Where | Purpose |
|---|---|---|
| `order-intake-sf` | Salesforce DX project | Objects, agent (Agent Script), Apex actions, prompt template, credentials, permission sets, seed scripts, Testing Center suite |
| `order-intake-erp-api` | MuleSoft project ([GitHub](https://github.com/pakumar2018/order-intake-erp-api)) | ERP API on CloudHub: Salesforce order → Odoo sales order |
| `email-idp-ingest-sys-api` | MuleSoft project | Email ingest on CloudHub: Gmail → Salesforce → Agentforce classification → Azure Document Intelligence → Salesforce |
| `odoo-setup` | CSV files | Odoo products and customers matching the Salesforce demo data |
| `demo-purchase-orders` | PDFs and generator | Four fictional purchase orders, one per demo scenario |

## Prerequisites
- Salesforce **Developer Edition with Agentforce and Data Cloud**; Salesforce CLI 2.x
- Anypoint Platform account with CloudHub 2.0; Anypoint Studio 7.24+ (Mule 4.11, Java 17)
- Odoo Online (Sales and Invoicing apps)
- Azure subscription with an **AI Document Intelligence** resource (free F0 tier is enough)
- Two Gmail accounts: an orders mailbox and a dealer (customer) mailbox

## 1. Salesforce
```bash
sf org login web --alias orderintake --set-default
sf project deploy start --source-dir force-app --target-org orderintake
sf org assign permset --name Order_Intake_User --target-org orderintake
sf org assign permset --name Order_Intake_Integration --target-org orderintake
sf apex run --file scripts/apex/seed-demo-data.apex --target-org orderintake
sf apex run --file scripts/apex/seed-demo-intakes.apex --target-org orderintake
sf agent publish authoring-bundle --api-name Order_Intake_Assistant --target-org orderintake
sf agent activate --api-name Order_Intake_Assistant --target-org orderintake
```
- Assign yourself **Prompt Template Manager** and **Prompt Template User**.
- Edit `seed-demo-data.apex` if your dealer mailbox is not `demo.dealer.po@gmail.com`: each customer's buyer
  contact uses a `+alias` of that mailbox so the sender identifies the customer.
- **External Client App** for MuleSoft (Setup → External Client App Manager): OAuth enabled, scope `api`,
  **client credentials flow** enabled in both Settings and Policies, Run As = a user with
  `Order_Intake_Integration`. Copy the consumer key and secret.

## 2. Odoo
1. Invoicing → Settings → enable **Sales Credit Limit**.
2. Import `odoo-setup/odoo-products.csv` (Sales → Products) and `odoo-setup/odoo-customers.csv` (customers;
   Reference = CUST-100x, credit limit 25,000).
3. Profile → Account Security → **New API Key** (scope RPC).

## 3. MuleSoft ERP API (`order-intake-erp-api`)
1. Generate a shared secret (`api.key`), for example 40 random characters.
2. Deploy to CloudHub with properties `odoo.apiKey` (Odoo key) and `api.key` (shared secret); adjust
   `odoo.host` and `odoo.database` in `config.yaml`.
3. Note the public URL. In Salesforce, set it as the `Url` parameter value in
   `namedCredentials/Order_Intake_Mule.namedCredential-meta.xml` (the public URL followed by `/api`), deploy, then Setup → Named Credentials → External Credentials → **Order Intake Mule Credential**
   → principal **ErpApiKey** → add parameter **`ApiKey`** = the shared secret.

## 4. Azure AI Document Intelligence
Create the resource (Azure Portal → Document Intelligence → Create, pricing tier Free F0). Copy the endpoint
host into `ocr.host` in `email-idp-ingest-sys-api/src/main/resources/mule-app-dev.properties`, and KEY 1 as the
secret `ocr.apiKey`.

## 5. Gmail
- Orders mailbox: labels **Orders**, **Processed**, **Needs-Review**, **Not-Order**; a filter that labels
  incoming order emails **Orders** (PDF or not); an **App Password** (requires 2-Step Verification). The same
  App Password is used for IMAP (reading) and SMTP (the "order created" reply).
- Dealer mailbox: "Send mail as" aliases `+brightline`, `+cobalt`, `+harborpine`, `+summit`.

## 6. MuleSoft email ingest (`email-idp-ingest-sys-api`)
Set `email.username`, `sf.host` and `ocr.host` in `mule-app-dev.properties`. Deploy to CloudHub (Mule 4.11,
Java 17) with the secure properties `email.password`, `sf.clientId`, `sf.clientSecret` and `ocr.apiKey`.
Run only one copy at a time (Studio or CloudHub), since both would poll the same mailbox.

## Permissions summary
| Permission set | Who | Grants |
|---|---|---|
| `Order_Intake_User` | Order desk reps | Order Intake objects and fields, Order Desk app, agent access, Apex action classes, ERP credential principal |
| `Order_Intake_Integration` | MuleSoft run-as user | API access, Order Intake objects, extraction REST endpoint |
| Prompt Template User | Reps and the MuleSoft user | Running `Classify_Order_Email` and `Extract_Order_From_Email` |

## Testing
| Test | How | Expected |
|---|---|---|
| Apex (17 tests) | `sf project deploy start --source-dir force-app --test-level RunLocalTests` | All pass |
| Testing Center (10 cases) | `sf agent test run --api-name Order_Intake_Assistant_Tests --wait 15` | 10/10 output validation pass (off-topic cases have no topic by design) |
| Classification | `scripts/test-classification.ps1` | 4 sample emails classified correctly |
| Email ingest MUnit (7 tests) | `mvn clean package` in `email-idp-ingest-sys-api` | All pass |
| End to end | Email `PO-7795-Cobalt-clean.pdf` from the Cobalt alias | Intake *Order Created*, 3 matched lines, "order created" reply in the thread, email in **Processed** |
| Order in the email body | No PDF; body "PO 7801: 40 x BLT-3001 at 22.00, 40 x NUT-3101 at 9.80" from the Cobalt alias | Intake *Order Created* (Extraction Source: email body), reply sent |
| Exceptions | Email `PO-45188-Brightline-exceptions.pdf` from the Brightline alias | Intake *Needs Review*: Unknown SKU, Price Mismatch; a review Case is opened |
| ERP | Agent: "Create the order for PO 7781", then "Send it to the ERP" | Odoo sales order number returned and visible in Odoo |
| Credit limit | Agent: "Create the order for PO HP-2210", then "Send it to the ERP" | Rejected on the Odoo credit limit; agent offers Credit escalation |

## Resetting the demo
```bash
sf apex run --file scripts/apex/reset-demo-intakes.apex --target-org orderintake
sf apex run --file scripts/apex/seed-demo-intakes.apex --target-org orderintake
```
Then cancel and delete test orders in Odoo, and leave no unread emails under the Gmail **Orders** label.

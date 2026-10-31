# Test cases: Order Intake Assistant

Run the reset and reseed scripts before testing (see SETUP-GUIDE.md). Send emails from the dealer mailbox
(demo.dealer.po) using the customer's `+alias` to demo.orders.po@gmail.com, then wait about a minute.

## A. Email intake (Gmail → MuleSoft → Agentforce classification → Azure → Salesforce)

| # | Test | Input | Expected in Salesforce | Expected in Gmail |
|---|---|---|---|---|
| A1 | Clean PO | From `+cobalt`, attach `PO-7795-Cobalt-clean.pdf` | Salesforce order created and sent to Odoo automatically: intake **ERP Confirmed** with the Odoo order number (S000xx), Extraction Source `attachment PO-7795-Cobalt-clean.pdf` (plus ` + email body` when the body added something), PO 7795, Cobalt Fabrication Ltd, 3 Matched lines (BLT-3001 ×30 @ 22.00, NUT-3101 ×30 @ 9.80, GSK-4001 ×200 @ 1.35), no Case | **Processed**; "order created" reply in the dealer's thread with the Odoo order number, the lines and total |
| A2 | PO with exceptions | From `+brightline`, attach `PO-45188-Brightline-exceptions.pdf` | **Needs Review**, PO 45188, Brightline Manufacturing; line 1 WID-1001 Matched, line 2 BRG6204 Unmatched (**Unknown SKU**), line 3 VLV-5001 **Price Mismatch**; review **Case** opened (subject with PO and exceptions, description with all lines and the email body) | **Needs-Review**; no reply |
| A3 | Credit limit PO | From `+harborpine`, attach `PO-HP-2240-HarborPine-credit-limit.pdf` | Order created, then sent to Odoo automatically and rejected on the credit limit: intake **ERP Failed** with the Odoo error in ERP Error, PO HP-2240, Harbor and Pine, 1 line PMP-6001 ×80 @ 449.00 (total 35,920); High priority review **Case** "ERP rejected the order" | **Needs-Review**; no reply |
| A4 | Faded scan | From `+summit`, attach `PO-SMW-5541-Summit-scanned.pdf` | **Needs Review**, PO SMW-5541; FLT-7001 Matched, HYD-FLTR-CRTG **Unknown SKU**; also **Low Confidence** if Azure scores below 80%; review **Case** opened | **Needs-Review** |
| A5 | Empty body, PDF only | Any alias, no body text, subject "PO 7795", PDF attached | Still classified **Purchase Order** (classifier sees the attachment name) | As A1 |
| A6 | Not an order | Any alias, no attachment, "Do you have pumps in stock?" | **Not Order**, classification Inquiry/Other, no lines | **Not-Order** |
| A7 | Duplicate | The same email processed again (marked unread) | No second intake (same Gmail Message-ID key); log says duplicate skipped | Moved as before |
| A9 | Order in the email body | From `+cobalt`, no attachment, subject "PO 7801", body "Please supply 40 x BLT-3001 Hex Bolt at 22.00 and 40 x NUT-3101 Hex Nut at 9.80. Customer CUST-1002." | Azure skipped; **ERP Confirmed** (order created and sent to Odoo), Extraction Source **email body**, PO 7801, 2 Matched lines | **Processed**; "order created" reply with the Odoo order number |
| A10 | Incomplete body order | From `+cobalt`, no attachment, body "Please send 50 more of the usual bolts" | **Needs Review** (Missing Field and/or Unknown SKU, low confidence); review **Case** opened with the email body | **Needs-Review**; no reply |
| A11 | Rep resolves a review | After A2, fix the lines with the agent and create the order (B3–B6) | Intake **Order Created**; the review **Case closes** automatically | — |
| A12 | Excel PO | From `+cobalt`, subject "Purchase order 7803", short body, attach `PO-7803-Cobalt.xlsx` (in `mulesoft/email-idp-ingest-sys-api/src/test/resources`) | The .xlsx is on the intake under Files (original file, opens in Excel); Document Text holds its text; Extraction Source `attachment PO-7803-Cobalt.xlsx` (` + email body` if the body filled a gap); lines from the spreadsheet | **Processed** with a reply when clean and ERP confirmed |
| A13 | Word PO | As A12 with a .docx PO | Same as A12, read with the Azure layout model and `Extract_Order_From_Document` | As A12 |
| A14 | PO number mismatch | From `+cobalt`, body "Please process PO 7804", attach `PO-7795-Cobalt-clean.pdf` | **Needs Review** (Missing Field); Processing Error "PO number 7795 in the attachment differs from 7804 in the email body ..."; Customer PO Number 7795 (the attachment's); review **Case** | **Needs-Review**; no reply |
| A15 | Rep resends after an ERP failure | After A3, raise the credit limit in Odoo (or lower the quantity), then ask the agent "Resend PO HP-2240 to the ERP" | Intake **ERP Confirmed**; the ERP review **Case closes** automatically | — |
| A16 | Reviewed order goes to the ERP on its own | After A2, fix the lines with the agent and say "Create the order" only | Within seconds the intake is **ERP Confirmed** with the Odoo number, with no "Send it to the ERP" needed; the review **Case** is closed |
| A8 | Unknown sender | Send from an address with no contact, PDF with customer no. CUST-1002 | Customer matched by customer number from the PDF | As A1 |

## B. Agent (Order Desk app → Agentforce panel)

| # | Ask the agent | Expected behaviour |
|---|---|---|
| B1 | What needs my attention today? | Lists Needs Review intakes (PO 45120, PO SMW-5530, plus email ones) with exceptions; asks which to work on |
| B2 | Show me PO 45120 | 3 lines: WID-1001 ×200 matched, BRG6204 ×500 unknown SKU, VLV-5001 ×40 price mismatch (17% below list) |
| B3 | What products could line 2 be? | Suggests BRG-2001 Ball Bearing 6204-2RS first; asks the rep to choose, does not choose itself |
| B4 | Use BRG-2001 for line 2 | Line 2 becomes Matched |
| B5 | Accept the customer's PO price for line 3 | Line 3 becomes Matched at the PO price; intake ready for order |
| B6 | Create the order | Asks for confirmation once; creates a Salesforce Order; intake **Order Created** |
| B7 | Create an order for an intake with unresolved lines | Refuses and lists what must be fixed first |
| B8 | (after B6) What is the ERP status of this order? | No need to send it: creating the order sent it to Odoo automatically. Returns the Odoo order number (S000xx); intake **ERP Confirmed**; order visible in Odoo with customer reference = PO number |
| B9 | Send it to the ERP (after B8) | Says it is already in the ERP and returns the same Odoo order number; nothing is sent again |
| B10 | Create the order for PO HP-2210 | The order goes to Odoo automatically, which rejects it on the credit limit; intake **ERP Failed**; agent explains and offers Credit escalation |
| B11 | Escalate it to the Credit team | Creates a Task for Credit; confirms |
| B16 | Show me PO 45188 (after A2) | Details include "Review case: 0000xxxx (New)" |
| B12 | What is the ERP status of PO 7781? (before ordering) | Says no Salesforce order exists yet, so nothing was sent |
| B13 | Draft a confirmation email for PO 45188 (after B8) | Draft built from the order: exact quantities and prices; not sent until approved |
| B14 | Ask Summit to resend a clearer copy of PO SMW-5530 | Drafts a short email, shows it for approval, sends only after confirmation |
| B15 | What's the weather in Paris? / Write a poem | Politely declines and says what it can help with |

## C. Automated tests

| Suite | How to run | Count | Expected |
|---|---|---|---|
| Apex | `sf project deploy start --source-dir force-app --test-level RunLocalTests` | 25 (actions, extraction endpoint, auto order creation with confirmation, ERP submit endpoint with confirmed, failed and resent orders, automatic ERP submit when a reviewed order is created, review Case open and close) | All pass |
| Agentforce Testing Center | `sf agent test run --api-name Order_Intake_Assistant_Tests --wait 15` | 10 | 10/10 output validation pass |
| Classification | `scripts/test-classification.ps1` | 4 sample emails | PO, change order, inquiry and other classified correctly |
| MUnit (email ingest) | `mvn clean package` | 20 | All pass: moving the email to its label is retried and a failed move never marks the intake Error, an .xlsx attachment through the listener's own transform keeps its original bytes, body + attachment merge (body only, attachment only, both agreeing, body lines when the attachment has none, PO mismatch), ERP submit after order creation (confirmed: reply with the ERP number; failed: no reply, Needs-Review; review intake: not sent), choice of PO document and Azure model, Received At from the Date header, Azure mapping for PO 45188, merged-rows PO 7795 read from the table, Items fallback, order from the email body, message key, sender address, attachment names |

## D. Integration and security checks

| # | Test | Expected |
|---|---|---|
| D1 | Call the ERP API without `X-Api-Key` | 401, no Odoo order |
| D2 | Wrong ApiKey in the Salesforce External Credential | Agent reports "Missing or invalid X-Api-Key"; intake ERP Failed |
| D6 | ERP API down when a clean order arrives | Order created; intake **ERP Failed** with the HTTP error in ERP Error; review **Case**; no reply; email to **Needs-Review**; the rep resends it with the agent later |
| D3 | Azure key wrong or quota exceeded | Intake **Error** with the Azure message in Processing Error; a High priority review **Case**; email stays in Orders |
| D5 | Gmail SMTP fails (for example a wrong App Password) | Order still created; the log shows "reply ... failed"; email moved as usual |
| D4 | Both Studio and CloudHub running | Not allowed: run only one copy. Symptoms when both run: emails handled by the older copy (Word or Excel attachment ignored, no "[Attachments: ...]" line in Email Body) and "Error while moving email" |
| D7 | Gmail drops the idle IMAP connection before the email is moved | The move is retried (email.moveRetries); if it still fails, the log says "is complete, but email N could not be moved" and the intake keeps its real status (no Error, no Case); the email stays under Orders, marked read |

## E. Deployment from GitHub (docs/CI-CD.md)

| # | Test | Expected |
|---|---|---|
| E1 | Actions → **MuleSoft: ERP API** → Run workflow | Green run; new Exchange version; app Running in Runtime Manager at the same URL; D1 still returns 401 |
| E2 | Actions → **MuleSoft: email ingest** → Run workflow | Green run (20 MUnit tests pass first); app Running; A9 still works |
| E3 | Push a change under `mulesoft/<app>/` to `main` | Only that app's workflow runs and deploys |
| E4 | Actions → **Salesforce: deploy** → Run workflow | Green run; metadata deployed; all Apex tests pass |

# Order Intake Assistant: email purchase orders to ERP with Agentforce and MuleSoft

**Hackathon theme:** 1, Agentforce Build: From Use Case to Customer Demo
**Products:** Agentforce (Agent Script, Prompt Builder, Testing Center, Einstein Trust Layer), Sales Cloud Orders
(Revenue Cloud Advanced swap point), MuleSoft Anypoint (Email and HTTP connectors, CloudHub, MUnit),
Azure AI Document Intelligence, Odoo ERP, Gmail

## 1. The business problem
B2B distributors and manufacturers still receive most purchase orders as **PDF attachments in email**.
An order-desk rep opens each email, reads the PDF, finds the customer, re-keys every line into the CRM or
ERP, checks SKUs and prices, and chases the customer when something is unclear.

- Manual entry takes **10–15 minutes per PO**, and errors (wrong SKU, quantity or price) flow straight into
  fulfilment and invoicing.
- Exceptions (unknown part numbers, price differences, credit holds, unclear scans) are handled by email
  ping-pong between sales, pricing, credit and the customer.
- Order status is invisible until the ERP has the order.

**Target users:** order-desk reps and customer service agents (primary); pricing, credit and order-desk
supervisors as escalation teams.

## 2. The solution
A fully automated **intake pipeline** plus an **Agentforce employee agent** for everything that needs a human.

```
Customer emails a purchase order: a PDF, image, Word or Excel file, or the order typed in the email body
  -> MuleSoft (CloudHub) reads the Gmail "Orders" label
  -> Order Intake record in Salesforce, every attachment stored as the original file
  -> Agentforce prompt template classifies the email: Purchase Order / Change Order / Inquiry / Other
     (it reads the subject, the plain-text body and the attachment file names)
  -> The Agentforce prompt template Extract_Order_From_Email always reads the email body. A PO attachment is read too:
       PDF or image: Azure AI Document Intelligence, invoice model (PO number, customer number, every line)
       Word or Excel: Azure layout model turns it into text and tables, which the prompt template
                      Extract_Order_From_Document reads
     MuleSoft merges the two: lines from the attachment (from the body when the attachment has none), header
     fields from the attachment with the body filling gaps, the lower confidence when both were used; a PO number
     that differs between body and attachment sends the intake to review
  -> Salesforce matches the customer (sender email, then customer number) and products, checks list prices,
     and sets exceptions:
       clean PO      -> the Salesforce order is created straight away and sent to the ERP:
                          ERP Confirmed -> the customer gets an "order created" reply with the ERP order
                                           number in the same email thread
                          ERP Failed    -> no reply; a review Case (for example the Odoo credit limit)
       anything off  -> Needs Review (Unknown SKU, Price Mismatch, Low Confidence, Unknown Customer, Missing Field)
                        and a review Case with the full details (also for processing errors);
                        the Case closes automatically once the order is created or the ERP confirms it
  -> The email moves to the Processed / Needs-Review / Not-Order label
  -> The Order Intake Assistant (Agentforce) helps the rep resolve exceptions, create the order,
     send or resend it to the ERP and confirm to the customer
  -> MuleSoft ERP API (CloudHub) creates and confirms the sales order in Odoo; the customer credit limit is enforced
```

## 3. The Order Intake Assistant (Agentforce employee agent)
Built in **Agent Script** (`aiAuthoringBundles/Order_Intake_Assistant`, active version 2) with a router and
three subagents, and 10 invocable Apex actions.

| Subagent | What the rep can ask | Actions |
|---|---|---|
| **Intake Review** | "What needs my attention?", "Show me PO 45188", "What could line 2 be?", "Use BRG-2001", "Accept the PO price", "Create the order", "Escalate to Pricing" | Find intakes, intake details, suggest product matches, update line, create order, escalate |
| **ERP Sync** | "Send it to the ERP", "Why did HP-2210 fail?", "Show every ERP failure" | Find intakes, check ERP status, submit/resubmit to ERP, escalate |
| **Customer Reply** | "Draft a confirmation for PO 45188", "Ask Summit for a clearer copy" | Draft confirmation (built from the order), intake details, send email |

**Design choices that make it trustworthy**
- Every fact comes from an action; the agent is told never to invent intake numbers, products, prices or ERP results.
- **Rules live in code, not in the prompt:** an order can only be created when the customer is known and every
  line is matched; the ERP API enforces the credit limit; one Salesforce order can never create two ERP orders.
- **Human confirmation** on every consequential action (create order, send to ERP, send email), using the
  platform's built-in confirmation.
- The rep chooses products for unknown SKUs; the agent only suggests.
- **Confirmation emails are generated from the order record**, so quantities and prices sent to customers are exact.

## 4. How AI is used
| Where | AI | Why |
|---|---|---|
| Email triage | Prompt Builder template `Classify_Order_Email` (Einstein Trust Layer with toxicity and safety scoring) | Separates POs from change orders, inquiries and noise before anything is extracted |
| Order from the email body | Prompt Builder template `Extract_Order_From_Email` | Every PO email's body is read; orders typed in the email need no OCR, and a body that only says "see attached" adds nothing; missing details lower the confidence and send the email to review |
| Document understanding | Azure AI Document Intelligence, prebuilt invoice model (reads PO number, customer number and line items, with per-field confidence) | Turns PDFs and images, including scans, into structured lines; low confidence flags the intake for review |
| Word and Excel POs | Azure layout model (text and tables as markdown) + Prompt Builder template `Extract_Order_From_Document` | The invoice model does not accept Office files; the layout text is stored on the intake (Document Text) and read separately from the email body |
| Exception handling | Agentforce employee agent (Agent Script) | Conversational resolution with tools, routing and guardrails |
| Product matching | Deterministic scoring in Apex (SKU and description tokens) | Explainable suggestions the rep can trust |

**Why Azure Document Intelligence:** MuleSoft IDP and Salesforce Document AI (Data 360) were evaluated first.
Neither is licensed in the Developer Edition and trial accounts used for this build, so the extraction step uses
Azure's free tier behind the same contract. Because the extraction result is mapped in one DataWeave file and
posted to one Salesforce endpoint, MuleSoft IDP or Document AI can replace Azure in a customer project without
changing Salesforce or the agent.

## 5. Technical components
| Layer | Component |
|---|---|
| Salesforce data | `Order_Intake__c`, `Order_Intake_Line__c`, Order Desk app, list views, permission sets |
| Agent | `Order_Intake_Assistant` Agent Script bundle (active version 2) with 10 invocable Apex actions sharing `OrderIntakeService` |
| Prompts | `Classify_Order_Email`, `Extract_Order_From_Email` and `Extract_Order_From_Document` (Flex prompt templates) |
| Review cases | `OrderIntakeTrigger` / `OrderIntakeReviewCases`: one Case per email that needs review, failed or was rejected by the ERP, closed when the order is created or the ERP confirms it |
| Integration endpoints | Apex REST `/orderintake/v1/extraction`: builds lines, matches customer and products, sets exceptions, creates the order for a clean PO. Apex REST `/orderintake/v1/erp-submit`: sends that order to the ERP in its own transaction (the callout cannot follow the order DML) with the agent's Submit Order To ERP logic, and returns the ERP result and the confirmation |
| MuleSoft: email ingest | `email-idp-ingest-sys-api` on CloudHub: Gmail IMAP → Salesforce REST (client credentials) → Agentforce classification → email body (prompt template) + attachment (Azure Document Intelligence), merged in DataWeave → Salesforce → ERP submit → reply |
| MuleSoft: ERP API | `order-intake-erp-api` on CloudHub: `POST /api/orders/{id}/erp-submit`, `GET /api/orders/{id}/erp-status`; OpenAPI spec included |
| Salesforce → MuleSoft | Named Credential `Order_Intake_Mule` + External Credential sending an `X-Api-Key` header |
| ERP | Odoo Online: customers with credit limits, products by SKU, confirmed sales orders |
| Document AI | Azure AI Document Intelligence (free tier), prebuilt invoice model |

## 6. Quality, testing and security
- **Apex:** 21 tests (all actions, the extraction endpoint, auto order creation, the ERP submit endpoint with
  confirmed, rejected and resent orders, review cases, MuleSoft callouts with mocks), all passing.
- **Testing Center:** 10-case functional suite (routing, action selection, response quality, off-topic refusal),
  10/10 passing on active version 2.
- **MuleSoft:** the email ingest app builds with `mvn package` and has 18 MUnit tests, including the mapping of a real
  Azure result for the PO 45188 demo PDF, a PO whose rows Azure merged into one item (lines are read from the
  detected table), an order written in the email body, an Excel attachment run through the listener's own transform
  (the original file bytes are kept), the body + attachment merge (body only, attachment only, both agreeing, PO
  mismatch), and the ERP submit with and without ERP confirmation. Both MuleSoft apps run on CloudHub.
- **Live end-to-end tests:** a PO emailed from Gmail became a Salesforce intake with 3 lines read by Azure
  (91% confidence); the agent created the order and Odoo confirmed it (S00003); a 35,920 order was rejected on the
  Odoo customer credit limit and escalated to the Credit team.
- **Defects found by testing and fixed:** quantities rendered as `2E+2` and misread by the model; a double
  confirmation; DataWeave media-type errors; Gmail Message-IDs breaking the Salesforce URL; sender display names
  rejected by the Email field; an empty-body PO email classified as Other (the classifier now sees attachment names).
- **Security:** no credentials in source code (CloudHub secure properties, Salesforce Named and External
  Credentials); OAuth 2.0 client credentials for MuleSoft → Salesforce; API key on the ERP API; least-privilege
  permission sets; TLS validation on Gmail; Einstein Trust Layer on all generative calls; fictional data only.

## 7. Business value (illustrative assumptions)
Assumptions: 2,000 PO emails a month, 12 minutes of manual entry each, 70% straight-through after automation,
4 minutes per exception with the agent, loaded cost of 35 USD per hour.

| | Before | After |
|---|---|---|
| Order-desk time | 400 hours a month | about 40 hours a month |
| Time saved | | **about 360 hours a month (4,300 hours a year), roughly 150,000 USD a year** |
| Order cycle time | hours to days | minutes for clean POs |
| Keying errors | frequent | product and price checks before the order exists |

Further value: faster cash (orders reach the ERP sooner), credit risk caught before fulfilment, and instant,
accurate confirmations for customers.

## 8. Reuse for other customers
- Industry-neutral pattern for any B2B business with email orders (manufacturing, distribution, consumer goods,
  medical supplies, automotive aftermarket).
- Swap points are isolated:
  - **Order creation** (`CreateOrderFromIntake`) → Revenue Cloud Advanced
  - **ERP** behind the MuleSoft ERP API contract → SAP, NetSuite or Dynamics 365 through their MuleSoft connectors
  - **Document AI** (one MuleSoft flow and one DataWeave mapping) → MuleSoft IDP or Salesforce Document AI
  - **Mailbox** → Gmail or Microsoft 365
- Seed and reset scripts recreate the demo in a new Developer Edition org in minutes.

## 9. Known limitations and next steps
- Standard Orders stand in for Revenue Cloud Advanced, which is not available in a Developer Edition org.
- The Azure invoice model labels the buyer on a PO as "Vendor"; customer matching therefore uses the sender
  email and the customer number on the PO, with the name only as a fallback. A custom-trained Azure or IDP
  purchase-order model would remove this.
- The ERP API has no automated tests in its repository; it was verified with live calls and agent tests against Odoo.
- Demo accounts (Odoo trial, Azure free tier, Gmail) are fictional and short-lived.
- Next: change-order handling, Slack alerts for Needs Review intakes, an Agentforce Service Agent so customers
  can ask "where is my order?", and a Claude-based document-analysis agent over MCP for complex POs (Theme 4).

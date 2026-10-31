# Order Intake Assistant: email purchase orders to ERP with Agentforce and MuleSoft

**Hackathon theme:** 1, Agentforce Build: From Use Case to Customer Demo
**Products:** Agentforce (Agent Script, Prompt Builder, Testing Center, Einstein Trust Layer), Sales Cloud Orders
and Cases (Revenue Cloud Advanced swap point), MuleSoft Anypoint (Email and HTTP connectors, CloudHub 2.0, MUnit),
Azure AI Document Intelligence, Odoo ERP, Gmail, GitHub Actions
**Code:** https://github.com/pakumar2018/agentforce-order-intake (public; no credentials, fictional data only)

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
  -> The Order Intake Assistant (Agentforce) helps the rep resolve exceptions and create the order (which then
     goes to the ERP on its own), resend failed ones and confirm to the customer
  -> MuleSoft ERP API (CloudHub) creates and confirms the sales order in Odoo; the customer credit limit is enforced
```

### Demo story
Two fictional customers email PDF purchase orders. **Cobalt Fabrication, PO 7820** (4 lines, all matching) goes
from email to a confirmed Odoo order with nobody touching it, and Cobalt gets a reply with the ERP order number.
**Brightline Manufacturing, PO 45220** has an unknown part number and a valve price about 15% under list, so it
goes to review with a Case. **Sam**, an order desk rep, asks the agent what needs attention, picks the suggested
bearing, accepts the quoted price and creates the order; it goes to Odoo on its own and the Case closes.

## 3. The Order Intake Assistant (Agentforce employee agent)
Built in **Agent Script** (`aiAuthoringBundles/Order_Intake_Assistant`, active version 2) with a router and
three subagents, and 10 invocable Apex actions.

| Subagent | What the rep can ask | Actions |
|---|---|---|
| **Intake Review** | "What needs my attention?", "Show me PO 45188", "What could line 2 be?", "Use BRG-2001", "Accept the PO price", "Create the order", "Escalate to Pricing" | Find intakes, intake details, suggest product matches, update line, create order, escalate |
| **ERP Sync** | "What is the ERP status?", "Why did HP-2210 fail?", "Resend it to the ERP", "Show every ERP failure" | Find intakes, check ERP status, submit/resubmit to ERP, escalate |
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
| Reviewed orders to ERP | `OrderIntakeErpAutoSubmit`: when an intake becomes Order Created (for example after the rep fixes it with the agent), `OrderIntakeTrigger` queues a job that runs `SubmitOrderToErp`, so the order reaches Odoo without a second request. MuleSoft's straight-through orders opt out, because MuleSoft sends them itself and waits for the ERP number for the reply |
| MuleSoft: email ingest | `email-idp-ingest-sys-api` on CloudHub: Gmail IMAP → Salesforce REST (client credentials) → Agentforce classification → email body (prompt template) + attachment (Azure Document Intelligence), merged in DataWeave → Salesforce → ERP submit → reply |
| MuleSoft: ERP API | `order-intake-erp-api` on CloudHub: `POST /api/orders/{id}/erp-submit`, `GET /api/orders/{id}/erp-status`; OpenAPI spec included |
| Salesforce → MuleSoft | Named Credential `Order_Intake_Mule` + External Credential sending an `X-Api-Key` header |
| ERP | Odoo Online: customers with credit limits, products by SKU, confirmed sales orders |
| Document AI | Azure AI Document Intelligence (free tier): prebuilt invoice model for PDFs and images, layout model for Word and Excel |
| Delivery | GitHub Actions: every push to `main` runs the MUnit and Apex tests and deploys both MuleSoft apps to CloudHub 2.0 and the Salesforce metadata |

## 6. Quality, testing and security
- **Apex:** 25 tests (all actions, the extraction endpoint, auto order creation, the automatic ERP submit of reviewed orders, the ERP submit endpoint with
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
  Odoo customer credit limit and escalated to the Credit team; an order typed in the email body (PO 7801) and a
  Word PO (PO 7804) each became a Salesforce order automatically with all lines matched. The latest additions
  (body + attachment merge, original Excel files, automatic ERP submit) are covered by the automated tests above
  and are what the demo recording (PO 7820 and PO 45220) exercises.
- **Defects found by testing and fixed:** quantities rendered as `2E+2` and misread by the model; a double
  confirmation; DataWeave media-type errors; Gmail Message-IDs breaking the Salesforce URL; sender display names
  rejected by the Email field; an empty-body PO email classified as Other (the classifier now sees attachment names);
  Azure merging several PO rows into one item (lines are now read from the detected table); Excel attachments
  re-written by DataWeave (the original bytes are now kept); Received At off by the time-zone offset (now read
  from the email's Date header).
- **Security:** no credentials in source code (CloudHub secure properties, Salesforce Named and External
  Credentials); OAuth 2.0 client credentials for MuleSoft → Salesforce; API key on the ERP API; least-privilege
  permission sets; TLS validation on Gmail; Einstein Trust Layer on all generative calls; fictional data only.

## 7. Business value (illustrative assumptions)
Assumptions: 2,000 PO emails a month, 12 minutes of manual entry each, 70% straight-through after automation,
4 minutes per exception with the agent, loaded cost of 40 USD per hour.

| | Before | After |
|---|---|---|
| Orders with zero touches | none | **about 70%** |
| Order-desk time | 400 hours a month | about 40 hours a month |
| Time saved | | **about 360 hours a month, about 90% of order-entry time (roughly 2 FTE), about 172,800 USD a year** |
| Email to ERP for a clean order | hours to days | **under a minute** |
| Keying errors | frequent | product and price checks before the order exists |

The pipeline saves about 280 hours (clean orders need no one); the agent saves about 80 hours more (each review
drops from 12 to about 4 minutes).

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
- Change orders and inquiries are classified and filed as Not Order; they are not processed further yet.
- Every email to the orders mailbox is picked up, including system notifications; they are classified as Not Order.
- One attachment per email is read as the PO (PDF first, then images, then Word or Excel); other files are stored only.
- Demo accounts (Odoo trial, Azure free tier, Gmail) are fictional and short-lived; the business-value figures are
  planning assumptions, not measured results.
- Next: change-order handling, order creation in Revenue Cloud Advanced, a custom-trained PO model, Slack alerts
  for Needs Review intakes, and an Agentforce Service Agent so customers can ask "where is my order?".

## 10. Submission contents and access
| Requirement | Where |
|---|---|
| Demo video (2–3 minutes) | Shared through OneDrive / Microsoft Stream |
| Presentation | `Email-to-Order Agent.pptx` (target user and problem, agent capabilities and storyboard, scenario, AI usage, impact and reuse) |
| Agentforce agent and Salesforce environment | Agentforce Developer Edition org with the active Order Intake Assistant; walkthrough or demo login on request, no credentials in any document. Agent spec: `docs/Order_Intake_Assistant-AgentSpec.md` |
| Agent Script, subagents, actions, prompts, automation | `salesforce/force-app/main/default/`: `aiAuthoringBundles` (Agent Script), `classes` (Apex actions and REST endpoints), `genAiPromptTemplates` (3 prompt templates), `triggers` (review Cases, automatic ERP submit) |
| Demo data, setup instructions, code | `salesforce/scripts/apex` (seed and reset), `demo-purchase-orders/`, `odoo-setup/`, `docs/SETUP-GUIDE.md`, `docs/DEMO-SCRIPT.md`, the GitHub repository |
| Architecture, dependencies, permissions, testing | This write-up (sections 2, 5, 6), `docs/SETUP-GUIDE.md` (prerequisites and permission sets), `docs/TEST-CASES.md`, `docs/CI-CD.md`, `salesforce/tests/` (Testing Center suite) |
| Known limitations and future improvements | Section 9 |

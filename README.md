# Order Intake Assistant: email purchase orders to ERP with Agentforce and MuleSoft

OSF Agentforce Hackathon, Theme 1.

B2B customers still send most orders as emails, with a PDF attached or the order typed in the message.
This solution reads those emails, turns them into Salesforce orders, sends them to the ERP and replies to the
customer, and gives order desk reps an Agentforce agent for every order that needs a person.

```
Customer email (Gmail)
  -> MuleSoft email ingest (CloudHub)
       -> Order Intake in Salesforce, every attachment stored as the original file
       -> Agentforce prompt template classifies the email (Purchase Order / Change Order / Inquiry / Other)
       -> prompt template always reads the email body; a PO attachment is read too
            (PDF/image: Azure invoice model; Word/Excel: Azure layout model + prompt template)
          and the two readings are merged (attachment first, the body fills gaps, PO mismatch -> review)
       -> Salesforce matches customer, products and prices
            clean     -> Salesforce order created and sent to the ERP
                           ERP Confirmed -> "order created" reply with the ERP order number in the customer's thread
                           ERP Failed    -> no reply, review Case (for example the Odoo credit limit)
            not clean -> Needs Review + review Case with all details
  -> Order Intake Assistant (Agentforce employee agent) resolves exceptions, creates the order,
     creates the order, which then goes to the ERP on its own, and drafts the customer confirmation
  -> MuleSoft ERP API (CloudHub) -> Odoo sales order, with the customer credit limit enforced
```

## Repository contents
| Folder | What it is |
|---|---|
| [`salesforce/`](salesforce) | Salesforce DX project: objects, Agentforce agent (Agent Script), invocable Apex actions, prompt templates, review-case trigger, named/external credentials, permission sets, seed and reset scripts, Testing Center suite |
| [`mulesoft/email-idp-ingest-sys-api/`](mulesoft/email-idp-ingest-sys-api) | Mule 4 app: Gmail IMAP → Salesforce → classification → email-body extraction plus Azure Document Intelligence for the attachment, merged → Salesforce → ERP submit → reply by SMTP |
| [`mulesoft/order-intake-erp-api/`](mulesoft/order-intake-erp-api) | Mule 4 app: ERP API (`POST /api/orders/{id}/erp-submit`, `GET /api/orders/{id}/erp-status`) that creates and confirms Odoo sales orders |
| [`odoo-setup/`](odoo-setup) | Odoo products and customers matching the Salesforce demo data |
| [`demo-purchase-orders/`](demo-purchase-orders) | Four fictional PO PDFs (one per demo scenario) and their generator |
| [`docs/`](docs) | [Project write-up](docs/PROJECT-WRITEUP.md), [setup guide](docs/SETUP-GUIDE.md), [CI/CD](docs/CI-CD.md), [agent spec](docs/Order_Intake_Assistant-AgentSpec.md), [test cases](docs/TEST-CASES.md), [demo script](docs/DEMO-SCRIPT.md) |

## Highlights
- **Agentforce employee agent** in Agent Script with three subagents (intake review, ERP sync, customer reply),
  10 Apex actions, and confirmation before every consequential action.
- **Three prompt templates** (Einstein Trust Layer): email classification, order extraction from the email body,
  and order extraction from an attached Word or Excel PO.
- **Body and attachment both read:** PDF, image, Word and Excel POs are read alongside the email body; the attachment
  wins, the body fills gaps, and a PO number that differs between them sends the intake to review.
- **Straight-through processing:** a clean PO becomes an order, goes to the ERP, and the customer gets a
  confirmation with the ERP order number without anyone touching it.
- **Exceptions become Cases** with the full email, lines and exceptions (also when the ERP rejects an order); the
  Case closes when the order is created or the ERP confirms it.
- **Reviewed orders go to the ERP on their own:** when Sam creates an order after a review, Salesforce sends it to
  the ERP straight away (same logic as the agent's Submit Order To ERP) and records ERP Confirmed or ERP Failed.
- **MuleSoft on CloudHub** for both integrations; Odoo as the ERP, with idempotent submission and credit limit checks.
- **Tests:** 25 Apex tests, 10 Agentforce Testing Center cases, 18 MUnit tests.

## Setup
See [docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md). No credentials are stored in this repository: secrets are
supplied as Anypoint secure properties and Salesforce External Credential parameters. All customer data is fictional.

## Continuous deployment
GitHub Actions deploy both MuleSoft apps to CloudHub 2.0 and the Salesforce metadata on every push to `main`
(see [docs/CI-CD.md](docs/CI-CD.md) and [.github/workflows](.github/workflows)).

# Order Intake Assistant: email purchase orders to ERP with Agentforce and MuleSoft

OSF Agentforce Hackathon, Theme 1.

B2B customers still send most orders as emails, with a PDF attached or the order typed in the message.
This solution reads those emails, turns them into Salesforce orders, sends them to the ERP and replies to the
customer, and gives order desk reps an Agentforce agent for every order that needs a person.

```
Customer email (Gmail)
  -> MuleSoft email ingest (CloudHub)
       -> Order Intake in Salesforce, PDF attached
       -> Agentforce prompt template classifies the email (Purchase Order / Change Order / Inquiry / Other)
       -> PDF: Azure AI Document Intelligence reads it  |  no PDF: prompt template reads the email body
       -> Salesforce matches customer, products and prices
            clean     -> Salesforce order created, "order created" reply in the customer's thread
            not clean -> Needs Review + review Case with all details
  -> Order Intake Assistant (Agentforce employee agent) resolves exceptions, creates the order,
     sends it to the ERP and drafts the customer confirmation
  -> MuleSoft ERP API (CloudHub) -> Odoo sales order, with the customer credit limit enforced
```

## Repository contents
| Folder | What it is |
|---|---|
| [`salesforce/`](salesforce) | Salesforce DX project: objects, Agentforce agent (Agent Script), invocable Apex actions, prompt templates, review-case trigger, named/external credentials, permission sets, seed and reset scripts, Testing Center suite |
| [`mulesoft/email-idp-ingest-sys-api/`](mulesoft/email-idp-ingest-sys-api) | Mule 4 app: Gmail IMAP → Salesforce → classification → Azure Document Intelligence or email-body extraction → Salesforce → reply by SMTP |
| [`mulesoft/order-intake-erp-api/`](mulesoft/order-intake-erp-api) | Mule 4 app: ERP API (`POST /api/orders/{id}/erp-submit`, `GET /api/orders/{id}/erp-status`) that creates and confirms Odoo sales orders |
| [`odoo-setup/`](odoo-setup) | Odoo products and customers matching the Salesforce demo data |
| [`demo-purchase-orders/`](demo-purchase-orders) | Four fictional PO PDFs (one per demo scenario) and their generator |
| [`docs/`](docs) | [Project write-up](docs/PROJECT-WRITEUP.md), [setup guide](docs/SETUP-GUIDE.md), [CI/CD](docs/CI-CD.md), [agent spec](docs/Order_Intake_Assistant-AgentSpec.md), [test cases](docs/TEST-CASES.md), [demo script](docs/DEMO-SCRIPT.md) |

## Highlights
- **Agentforce employee agent** in Agent Script with three subagents (intake review, ERP sync, customer reply),
  10 Apex actions, and confirmation before every consequential action.
- **Two prompt templates** (Einstein Trust Layer): email classification and order extraction from the email body.
- **Straight-through processing:** a clean PO becomes an order and gets a confirmation reply without anyone touching it.
- **Exceptions become Cases** with the full email, lines and exceptions; the Case closes when the order is created.
- **MuleSoft on CloudHub** for both integrations; Odoo as the ERP, with idempotent submission and credit limit checks.
- **Tests:** 17 Apex tests, 10 Agentforce Testing Center cases, 7 MUnit tests.

## Setup
See [docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md). No credentials are stored in this repository: secrets are
supplied as Anypoint secure properties and Salesforce External Credential parameters. All customer data is fictional.

## Continuous deployment
GitHub Actions deploy both MuleSoft apps to CloudHub 2.0 and the Salesforce metadata on every push to `main`
(see [docs/CI-CD.md](docs/CI-CD.md) and [.github/workflows](.github/workflows)).

# Demo script: Order Intake Assistant (target 2:45)

## Before you record
1. **Reset Salesforce** (removes seeded and email-created intakes with their orders, then reseeds):
   `sf apex run --file scripts/apex/reset-demo-intakes.apex --target-org orderintake`
   `sf apex run --file scripts/apex/seed-demo-intakes.apex --target-org orderintake`
2. **Reset Odoo:** Sales → Orders → cancel and delete earlier test orders.
3. **Reset Gmail (orders mailbox):** no unread emails left under the **Orders** label.
4. Check both MuleSoft apps show **Running** in Runtime Manager (`email-idp-ingest-sys-api`, `order-intake-erp-api`),
   and that no local copy is running in Anypoint Studio.
5. Have these tabs open, logged in, zoomed to 110–125%: Gmail (dealer: demo.dealer.po), Gmail (orders:
   demo.orders.po), Salesforce Order Desk app, Odoo Sales, Runtime Manager logs (optional).
6. Prepare the email in the dealer Gmail (do not send yet): **From** `Maya Chen – Brightline Manufacturing`,
   **To** `demo.orders.po@gmail.com`, **Subject** `PO 45188 - widgets, bearings and valves`, attach
   `PO-45188-Brightline-exceptions.pdf`.
7. Close notifications, hide bookmarks, use a clean browser profile.
8. Record with **Microsoft Clipchamp**, **PowerPoint (Insert → Screen Recording)** or **OBS Studio** at 1920×1080.
   Record each scene as its own clip; you can re-take one scene without redoing the whole video.

## Scenes

| # | Time | On screen | Say (voice-over) |
|---|---|---|---|
| 1 | 0:00–0:15 | Title slide, then the Gmail inbox full of PO emails | "Order desks still get most B2B orders as PDF emails. Every one is opened, read and re-keyed by hand. It takes minutes per order, and every typo becomes a shipping or invoicing problem." |
| 2 | 0:15–0:35 | Dealer Gmail: send the prepared PO 45188 email. Orders Gmail: the email arrives under **Orders**, then moves to **Needs-Review** | "Here a customer, Brightline Manufacturing, emails a purchase order. MuleSoft picks it up from the order mailbox within a minute, creates an Order Intake in Salesforce and attaches the PDF." |
| 3 | 0:35–0:55 | Salesforce Order Desk → Order Intakes → the new intake: Classification *Purchase Order*, extraction confidence, the three lines, status *Needs Review* | "Agentforce classifies the email as a purchase order, Azure Document Intelligence reads every line from the PDF, and Salesforce checks each product and price. Clean orders go straight through. This one has two problems." |
| 4 | 0:55–1:20 | Agentforce panel: **What needs my attention today?** then **Show me PO 45188** | "The order desk rep simply asks the Order Intake Assistant. It lists what needs attention and explains PO 45188: line 2 has an unknown part number, and line 3 is 17 percent below list price." |
| 5 | 1:20–1:45 | **What products could line 2 be?** → **Use BRG-2001 for line 2** → **Accept the customer's PO price for line 3** | "For the unknown SKU it suggests the closest catalog products, and the rep picks one. For the price, the rep accepts the quoted price. The agent never guesses; the rep stays in control." |
| 6 | 1:45–2:05 | **Create the order** → confirm → **What's the ERP status?** Switch to Odoo → Sales → the new confirmed order with customer reference 45188 | "With the exceptions cleared, the agent creates the order, and Salesforce sends it to the ERP through MuleSoft on its own. Seconds later the confirmed sales order is in Odoo." |
| 7 | 2:05–2:25 | **Create the order for PO HP-2210** → confirm → **What's the ERP status?** → rejection → **Escalate it to the Credit team** | "When the ERP says no, for example this 36,000 dollar order over the customer's credit limit in Odoo, the agent explains why and hands it to the credit team in one sentence." |
| 8 | 2:25–2:45 | **Draft a confirmation email for PO 45188**, show the exact lines. End on a value slide | "Finally it drafts the customer confirmation straight from the order, so every quantity and price is exact. Email to ERP in minutes instead of hours: about 360 hours a month back for a typical order desk." |

## Tips
- Speak slower than feels natural; 140–150 words per minute fits the timing above.
- Pause one second after each agent answer so viewers can read it.
- If an agent answer is long, zoom in (Clipchamp: zoom effect) rather than scrolling.
- Add on-screen captions for the key moments: "Classified by Agentforce", "Read by Azure Document Intelligence",
  "Human confirms", "Order in Odoo".
- Keep the final cut between 2:30 and 3:00.

## If something goes wrong while recording
- Email not picked up after 2 minutes: check it is **unread** and has the **Orders** label.
- Intake shows *Error*: open it and read **Processing Error**; Runtime Manager logs show the detail.
- Agent says the ERP rejected an order with "Missing or invalid X-Api-Key": the secret in Salesforce
  (External Credential *Order Intake Mule Credential*, parameter `ApiKey`) no longer matches CloudHub `api.key`.

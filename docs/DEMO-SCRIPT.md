# Demo script: one clean order, one order Sam reviews (target 3:00)

Run from the `salesforce` folder of the repository. Demo files are in `demo-purchase-orders/`.

Story: two customers email purchase orders as PDFs. Cobalt's PO 7820 goes from email to ERP with no one
touching it. Brightline's PO 45220 has two problems; Sam, an order desk rep, fixes them with the Order Intake
Assistant, the order goes to the ERP and the review Case closes.

## Before you record
1. **Reset Salesforce:**
   `sf apex run --file scripts/apex/reset-demo-intakes.apex --target-org orderintake`
   `sf apex run --file scripts/apex/seed-demo-intakes.apex --target-org orderintake`
2. **Reset Odoo:** Sales → Orders → cancel and delete earlier test orders.
3. **Orders mailbox (demo.orders.po):** no unread emails under **Orders**.
4. **Runtime Manager:** `email-idp-ingest-sys-api` and `order-intake-erp-api` both **Running**; nothing running in Studio.
5. **Dealer mailbox (demo.dealer.po):** two drafts ready (do not send yet):
   - From `+cobalt`, subject `Purchase order 7820`, attachment `PO-7820-Cobalt-clean.pdf`
   - From `+brightline`, subject `PO 45220 - widgets, bearings and valves`, attachment `PO-45220-Brightline-review.pdf`
6. Tabs open and logged in, zoom 110–125%: dealer Gmail, orders Gmail, Salesforce **Order Desk** app (logged in as
   Sam), Odoo Sales. Close notifications, hide bookmarks.
7. Record each scene as its own clip (Clipchamp, PowerPoint screen recording or OBS, 1920×1080).

Tip: send both drafts at the start of scene 2 so MuleSoft has processed both by scene 4 (about a minute).

## Scenes

| # | Time | On screen | Say (voice-over) |
|---|---|---|---|
| 1 | 0:00–0:15 | Title slide, then the dealer Gmail with the two drafts | "B2B customers still send most orders as PDF emails. Someone opens each one, reads it and types it into the ERP. That takes minutes per order, and every typo becomes a shipping or invoicing problem." |
| 2 | 0:15–0:30 | Dealer Gmail: open and send the Cobalt draft, then the Brightline draft | "Two customers send purchase orders right now: Cobalt Fabrication, PO 7820, and Brightline Manufacturing, PO 45220. Both are PDFs." |
| 3 | 0:30–0:50 | Orders Gmail: both emails arrive under **Orders**, then move: 7820 to **Processed**, 45220 to **Needs-Review** | "MuleSoft on CloudHub watches the order mailbox. For each email it creates an Order Intake in Salesforce, stores the PDF, and asks an Agentforce prompt template whether this is a purchase order. It reads the email text with a second prompt template and sends the PDF to Azure Document Intelligence, then combines the two." |
| 4 | 0:50–1:15 | Salesforce → Order Intakes → PO 7820: Classification *Purchase Order*, Extraction Source *attachment PO-7820-Cobalt-clean.pdf*, 4 Matched lines, status **ERP Confirmed**, ERP Order Number S000xx. Then Odoo → Sales → order with customer reference 7820 | "Cobalt's order is clean. Customer and all four products match the catalog and price book, so Salesforce creates the order and sends it to Odoo through the MuleSoft ERP API. It's already confirmed in Odoo, and no one touched it." |
| 5 | 1:15–1:25 | Dealer Gmail: the reply "Order confirmation - PO 7820 (S000xx)" in the Cobalt thread | "Cobalt gets a confirmation in the same thread, with the ERP order number and the exact lines." |
| 6 | 1:25–1:40 | Salesforce → PO 45220: status **Needs Review**, exceptions *Unknown SKU; Price Mismatch*, the three lines; the related review **Case** with the PDF | "Brightline's order isn't clean. Salesforce flags it for review and opens a Case with the email, the PDF and every line. No reply goes out, because a person needs to look at it." |
| 7 | 1:40–2:00 | Sam opens the Agentforce panel: **What orders need my attention today?** then **Show me PO 45220** | "Sam from the order desk just asks the Order Intake Assistant. It lists what needs attention today and explains PO 45220: line 2 has a part number we don't recognise, and line 3 is about 15 percent below list price." |
| 8 | 2:00–2:20 | **What products could line 2 be?** → **Use BRG-2002 for line 2** → **Accept the customer's price for line 3, it was quoted** | "For the unknown part it suggests the closest catalog products, and Sam picks the 6205 bearing. The valve price was quoted to the customer, so Sam accepts it. The agent never guesses; Sam stays in control." |
| 9 | 2:20–2:40 | **Create the order** → confirm. Show the Case: **Closed**. Then **What's the ERP status of PO 45220?** → ERP Confirmed with the Odoo order number | "With the problems cleared, Sam creates the order. The review Case closes on its own, and the order goes straight to the ERP. Sam doesn't have to ask: it's already back with its Odoo number." |
| 10 | 2:40–3:00 | Odoo → Sales: confirmed orders 7820 and 45220. Optional: **Draft a confirmation email for PO 45220**. End on a value slide | "Two orders from email to ERP: one with nobody involved, one in under a minute of Sam's time. That's hours a day back for a typical order desk, and no re-typing." |

## Words to put on screen
- Scene 3: "MuleSoft reads the mailbox" · "Classified by Agentforce" · "Read by Azure Document Intelligence"
- Scene 4: "Matched in Salesforce" · "Sent to Odoo automatically"
- Scene 6: "Unknown SKU" · "Price Mismatch" · "Review Case opened"
- Scene 9: "Sam confirms" · "Case closed" · "Order in Odoo"

## If something goes wrong
- An email isn't picked up after 2 minutes: in the orders mailbox it must be **unread** and labelled **Orders**.
- An intake shows *Error*: open it and read **Processing Error**; Runtime Manager logs show the detail.
- PO 7820 shows **ERP Failed**: read **ERP Error** on the intake. "Missing or invalid X-Api-Key" means the
  External Credential `ApiKey` in Salesforce no longer matches `api.key` in CloudHub.
- The agent suggests a different product for line 2: say "Use BRG-2002 for line 2" anyway.

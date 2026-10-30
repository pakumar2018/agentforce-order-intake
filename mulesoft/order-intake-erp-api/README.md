# Order Intake ERP API (MuleSoft → Odoo)

System API that the Agentforce **Order Intake Assistant** calls to send approved orders to the ERP.
Salesforce posts the order with its lines; this app creates and confirms the sales order in **Odoo**
and returns the Odoo order number, or a reason the ERP rejected it.

| Endpoint | Purpose |
|---|---|
| `POST /api/orders/{orderId}/erp-submit` | Find customer by Reference → credit-limit check → find products by Internal Reference → create + confirm `sale.order` |
| `GET /api/orders/{orderId}/erp-status` | Return the Odoo order for that Salesforce order |

Response: `{"status": "Confirmed" | "Failed", "erpOrderNumber": "S00001", "error": null}`.
Business rejections (credit limit, unknown customer or SKU) return HTTP 200 with `status: Failed`, so the
agent can explain them. Resubmitting the same Salesforce order never creates a duplicate in Odoo.
API spec: `src/main/resources/api/order-intake-erp-api.yaml` (OpenAPI 3).

## Prerequisites
- Anypoint Studio 7.x with Mule runtime 4.9 and Java 17
- Odoo set up with the products and customers from `odoo-setup/` (customer **Reference** = CUST-100x, product **Internal Reference** = SKU)
- An Odoo API key with **RPC** scope

## Secrets (never put them in files)
| Property | Value |
|---|---|
| `odoo.apiKey` | Your Odoo API key |
| `api.key` | Any long random string you choose. Salesforce sends it in the `X-Api-Key` header |

## 1. Import into Anypoint Studio
1. **File → Import… → Anypoint Studio → Anypoint Studio project from File System** → Next.
2. **Project Root**: choose this `order-intake-erp-api` folder → **Finish**.
3. If Studio asks to update the runtime or connector versions, accept.

## 2. Run locally
1. **Run → Run Configurations… → Mule Applications → order-intake-erp-api → Arguments** tab.
2. In **VM arguments**, add (with your own values):
   `-M-Dodoo.apiKey=YOUR_ODOO_KEY -M-Dapi.key=YOUR_SHARED_SECRET`
3. **Run**. Wait for `DEPLOYED` in the console.
4. Test (in a terminal or Postman):
   ```
   curl -X POST http://localhost:8081/api/orders/TEST-001/erp-submit -H "Content-Type: application/json" -H "X-Api-Key: YOUR_SHARED_SECRET" -d "{\"orderNumber\":\"TEST\",\"poNumber\":\"TEST-PO\",\"accountNumber\":\"CUST-1002\",\"lines\":[{\"sku\":\"BLT-3001\",\"quantity\":2,\"unitPrice\":22}]}"
   ```
   Expect `{"status":"Confirmed","erpOrderNumber":"S0000x",...}` and a confirmed sales order in Odoo
   (Sales → Orders). Run the same command again: you get the same order number, no duplicate.
   Cancel and delete this test order in Odoo afterwards.

## 3. Deploy to CloudHub
1. Right-click the project → **Anypoint Platform → Deploy to CloudHub**. Sign in.
2. App name: `order-intake-erp-api` (add a suffix if taken). Runtime 4.9, smallest size.
3. **Properties** tab: add `odoo.apiKey` and `api.key`. They are hidden in Runtime Manager because
   `mule-artifact.json` lists them as secure properties.
4. **Deploy**. Note the public URL, for example `https://order-intake-erp-api-xxxx.cloudhub.io`.

## 4. Connect Salesforce
Create the named credential `Order_Intake_Mule` with URL `<public URL>/api` and a custom header
`X-Api-Key`. Once it exists, the agent stops simulating the ERP and calls this API.

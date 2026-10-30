# Automatic deployment from GitHub

Every push to `main` deploys what changed:

| Workflow | Runs when | What it does |
|---|---|---|
| `MuleSoft: email ingest` | `mulesoft/email-idp-ingest-sys-api/**` changes | MUnit tests → publish to Exchange → deploy to CloudHub 2.0 |
| `MuleSoft: ERP API` | `mulesoft/order-intake-erp-api/**` changes | Publish to Exchange → deploy to CloudHub 2.0 |
| `Salesforce: deploy` | `salesforce/force-app/**` changes | Deploy metadata and run all Apex tests |

Every workflow can also be started by hand: **Actions** tab → pick the workflow → **Run workflow**.
Until the settings below are configured, the jobs show as *skipped*.

Secrets are stored only as GitHub **encrypted secrets**; they never appear in the code or the logs.

## 1. Anypoint connected app (once)
Anypoint Platform → **Access Management → Connected Apps → Create app**:
- Name `github-actions`, type **App acts on its own behalf (client credentials)**
- Scopes, for the business group and the **Sandbox** environment:
  - Exchange: **Exchange Contributor**
  - Runtime Manager: **Create Applications**, **Delete Applications**, **Read Applications**, **Read Servers**
  - General: **View Environment**, **View Organization**
- Save, then copy the **ID** and **Secret**.

The **organization ID** is under Access Management → **Business Groups** → your organization.

## 2. GitHub settings
Repository → **Settings → Secrets and variables → Actions**.

**Variables** tab:

| Name | Value |
|---|---|
| `ANYPOINT_ORG_ID` | Anypoint organization (business group) ID |
| `ANYPOINT_ENVIRONMENT` | `Sandbox` (default) |
| `ANYPOINT_TARGET` | CloudHub 2.0 space, default `Cloudhub-US-East-2` |
| `MULE_VERSION` / `MULE_RELEASE_CHANNEL` | As shown in Runtime Manager → app → Settings → Runtime version (defaults `4.13.1` / `EDGE`) |
| `SALESFORCE_DEPLOY` | `true` to turn on the Salesforce workflow |

**Secrets** tab:

| Name | Used by | Value |
|---|---|---|
| `ANYPOINT_CLIENT_ID`, `ANYPOINT_CLIENT_SECRET` | Both Mule apps | Connected app from step 1 |
| `EMAIL_PASSWORD` | Email ingest | Gmail App Password of the orders mailbox |
| `SF_CLIENT_ID`, `SF_CLIENT_SECRET` | Email ingest | Salesforce External Client App consumer key and secret |
| `OCR_API_KEY` | Email ingest | Azure Document Intelligence key |
| `ODOO_API_KEY` | ERP API | Odoo API key |
| `ERP_API_KEY` | ERP API | Shared secret Salesforce sends as `X-Api-Key` |
| `SF_AUTH_URL` | Salesforce | Org login URL from `sf org display --target-org orderintake --verbose` (the "Sfdx Auth Url" line) |

With the GitHub CLI you can set a secret without it being shown on screen: `gh secret set EMAIL_PASSWORD`
asks for the value.

## Notes
- Each run publishes a new Exchange version `1.<run number>.<attempt>` with the organization ID as group ID; the
  pom in the repository keeps `com.osf.demo` so the projects still open in Anypoint Studio unchanged.
- A deployment sets all secure properties from the GitHub secrets, so keep them current there rather than in
  Runtime Manager.
- Run only one copy of the email ingest app: stop any Studio run while CloudHub is deployed.

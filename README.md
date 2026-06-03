# Logic App CI/CD POC

A proof of concept for deploying Azure Logic Apps Standard via GitHub Actions using OpenID Connect (OIDC) federated identity — no static credentials stored in GitHub.

## What This Repo Contains

```
.
├── .github/workflows/deploy.yml   # CI/CD pipeline (validate → staging → production)
├── logic-apps/
│   ├── host.json                  # Logic Apps extension bundle config
│   ├── connections.json           # Managed API connections (empty for this POC)
│   ├── healthcheck/
│   │   ├── workflow.json          # Healthcheck endpoint v1
│   │   └── workflow.v2.json      # Healthcheck endpoint v2 (adds deployedVia + note fields)
│   └── heartbeat/
│       └── workflow.json          # Heartbeat endpoint
├── fed_main.json                  # OIDC federated credential definition for main branch
├── fed_prod.json                  # OIDC federated credential definition for production env
├── fed_staging.json               # OIDC federated credential definition for staging env
└── setup.ps1                      # One-time Azure provisioning script
```

---

## Architecture

Two separate Logic App Standard instances are used — one for staging, one for production. This avoids the complexity of slot swaps while giving a clear environment boundary.

```
GitHub Push to main
        │
        ▼
  [1] Validate          JSON lint check on all logic-apps/ files
        │
        ▼
  [2] Deploy Staging    Zip deploy → la-poc-staging
        │               Wait 20s → retrieve healthcheck callback URL
        ▼
  [3] Deploy Production Manual approval gate (GitHub "production" environment)
                        Zip deploy → la-poc-main
                        Smoke test: HTTP 200 on /healthcheck
```

---

## CI/CD Pipeline

**File:** [.github/workflows/deploy.yml](.github/workflows/deploy.yml)

### Triggers
- Push to `main` with changes under `logic-apps/**`
- Manual trigger via `workflow_dispatch`

### Jobs

| Job | Environment | What it does |
|-----|-------------|--------------|
| `validate` | — | Validates all JSON files in `logic-apps/` are well-formed |
| `deploy-staging` | `staging` | Zips and deploys to the staging Logic App; fetches healthcheck URL |
| `deploy-production` | `production` | Waits for manual approval, then deploys to prod and smoke-tests the healthcheck |

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `RESOURCE_GROUP` | Resource group containing both Logic Apps |
| `LOGIC_APP_NAME` | Production Logic App name |
| `STAGING_LOGIC_APP_NAME` | Staging Logic App name |

### GitHub Environments Required

- **`staging`** — no approval gate; secrets scoped here if needed
- **`production`** — requires manual approval before the production deploy job runs

---

## Logic App Workflows

### `healthcheck`
HTTP GET endpoint that returns a JSON health status. Used by the pipeline smoke test to confirm a successful deployment.

**v1 response:**
```json
{
  "status": "healthy",
  "version": "v1",
  "workflow": "healthcheck",
  "timestamp": "<utcNow>"
}
```

**v2 response** (`workflow.v2.json` — rename to `workflow.json` to deploy):
```json
{
  "status": "healthy",
  "version": "v2",
  "workflow": "healthcheck",
  "timestamp": "<utcNow>",
  "deployedVia": "GitHub Actions CI/CD",
  "note": "This is the v2 deployment — zero downtime slot swap confirmed"
}
```

### `heartbeat`
Simple HTTP GET endpoint that returns a healthy status. Structurally identical to healthcheck v1; exists as a second workflow to demonstrate multi-workflow deployments.

---

## OIDC / Federated Identity Setup

Authentication to Azure uses OIDC instead of a service principal secret. GitHub Actions exchanges a short-lived token for an Azure access token at runtime.

Three federated credential definitions are stored as JSON files for reference:

| File | Subject claim | When used |
|------|--------------|-----------|
| `fed_main.json` | `repo:…:ref:refs/heads/main` | Any push-triggered run on main |
| `fed_staging.json` | `repo:…:environment:staging` | Staging environment jobs |
| `fed_prod.json` | `repo:…:environment:production` | Production environment jobs |

These were registered on the app registration using:
```powershell
az ad app federated-credential create --id <app-id> --parameters fed_staging.json
az ad app federated-credential create --id <app-id> --parameters fed_prod.json
```

---

## One-Time Azure Setup

**File:** [setup.ps1](setup.ps1)

Run this once to provision all Azure infrastructure. It creates:

1. Resource group (`rg-logicapp-poc`, `australiaeast`)
2. Storage account (Standard LRS) — required by Logic Apps Standard
3. App Service Plan (SKU: WS1 Workflow Standard)
4. Production Logic App (`la-poc-main`)
5. Staging Logic App (a separate instance, not a slot)
6. Entra ID app registration (`sp-logicapp-poc-github`) with Contributor role on the resource group
7. Federated credentials for main branch, staging environment, and production environment

After running the script, add the five GitHub secrets listed above and create the two GitHub environments.

```powershell
# Login first
az login
# Then run
.\setup.ps1
```

---

## Key Design Decisions

- **Separate Logic Apps for staging/prod** rather than deployment slots. Slots on Logic Apps Standard require the same App Service Plan, add complexity, and the POC goal is demonstrating the pipeline pattern, not slot mechanics.
- **OIDC over service principal secrets** — tokens are ephemeral, no rotation needed, and the trust is scoped to specific branches/environments.
- **JSON validation step** — catches malformed workflow files before any Azure API calls are made, giving fast feedback on authoring errors.
- **Manual approval gate on production** — enforced by the GitHub `production` environment protection rule, not by pipeline logic, so it cannot be bypassed by editing the YAML.

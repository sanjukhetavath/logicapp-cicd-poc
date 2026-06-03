# ─────────────────────────────────────────────────────────────
# POC Setup Script — Logic App CI/CD with Deployment Slots
# Windows PowerShell | Azure_Test_Sanju
# Fixed: appservice plan, logicapp create, slot command
# ─────────────────────────────────────────────────────────────

# ── CONFIG ───────────────────────────────────────────────────
$SUBSCRIPTION_ID  = "8f44896c-5241-456d-a885-e2aea45ae980"
$TENANT_ID        = "c33ca1f9-d381-41ee-a929-5c73dd92902f"
$RESOURCE_GROUP   = "rg-logicapp-poc"
$LOCATION         = "australiaeast"
$APP_PLAN         = "asp-logicapp-poc"
$LOGIC_APP        = "la-poc-main"
$STORAGE_ACCOUNT  = "stla$(Get-Random -Maximum 99999)"
$GITHUB_USERNAME  = "sanjukhetavath"
$REPO_NAME        = "logicapp-cicd-poc"
# ─────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==> Setting active subscription..." -ForegroundColor Cyan
az account set --subscription $SUBSCRIPTION_ID
Write-Host "    OK" -ForegroundColor Green

# ── 1. Resource group ────────────────────────────────────────
Write-Host ""
Write-Host "==> Creating resource group..." -ForegroundColor Cyan
az group create `
  --name $RESOURCE_GROUP `
  --location $LOCATION `
  --output none
Write-Host "    OK: $RESOURCE_GROUP" -ForegroundColor Green

# ── 2. Storage account ───────────────────────────────────────
Write-Host ""
Write-Host "==> Creating storage account..." -ForegroundColor Cyan
az storage account create `
  --name $STORAGE_ACCOUNT `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --sku Standard_LRS `
  --output none
Write-Host "    OK: $STORAGE_ACCOUNT" -ForegroundColor Green

# ── 3. App Service Plan (WS1) ────────────────────────────────
# FIX: removed --is-linux flag (not valid for WS1 WorkflowStandard)
Write-Host ""
Write-Host "==> Creating App Service Plan WS1..." -ForegroundColor Cyan
az appservice plan create `
  --name $APP_PLAN `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --sku WS1 `
  --output none
Write-Host "    OK: $APP_PLAN" -ForegroundColor Green

# ── 4. Logic App Standard ────────────────────────────────────
# FIX: removed --location flag (not valid for az logicapp create)
Write-Host ""
Write-Host "==> Creating Logic App Standard..." -ForegroundColor Cyan
az logicapp create `
  --name $LOGIC_APP `
  --resource-group $RESOURCE_GROUP `
  --plan $APP_PLAN `
  --storage-account $STORAGE_ACCOUNT `
  --output none
Write-Host "    OK: $LOGIC_APP" -ForegroundColor Green

# ── 5. Staging deployment slot ───────────────────────────────
# FIX: Logic App Standard uses az functionapp slot commands
Write-Host ""
Write-Host "==> Creating staging deployment slot..." -ForegroundColor Cyan
az functionapp deployment slot create `
  --name $LOGIC_APP `
  --resource-group $RESOURCE_GROUP `
  --slot staging `
  --output none
Write-Host "    OK: staging slot created" -ForegroundColor Green

# ── 5b. Set APP_KIND on staging slot ─────────────────────────
# Required for Logic App Standard slots to be recognised as workflow apps
Write-Host ""
Write-Host "==> Setting APP_KIND on staging slot..." -ForegroundColor Cyan
az logicapp config appsettings set `
  --name $LOGIC_APP `
  --resource-group $RESOURCE_GROUP `
  --slot staging `
  --settings APP_KIND=workflowapp `
  --output none
Write-Host "    OK: APP_KIND=workflowapp set on staging slot" -ForegroundColor Green

# ── 6. Entra ID app registration ─────────────────────────────
Write-Host ""
Write-Host "==> Creating Entra ID app registration..." -ForegroundColor Cyan
$APP_ID = az ad app create `
  --display-name "sp-logicapp-poc-github" `
  --query appId -o tsv
Write-Host "    OK: App ID = $APP_ID" -ForegroundColor Green

az ad sp create --id $APP_ID --output none

# ── 7. Contributor role on resource group ────────────────────
Write-Host ""
Write-Host "==> Assigning Contributor role..." -ForegroundColor Cyan
az role assignment create `
  --assignee $APP_ID `
  --role Contributor `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" `
  --output none
Write-Host "    OK: Contributor assigned" -ForegroundColor Green

# ── 8. Federated credentials (OIDC) ─────────────────────────
Write-Host ""
Write-Host "==> Adding federated credential for main branch..." -ForegroundColor Cyan
$FED_MAIN = @{
  name      = "github-actions-main"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_USERNAME}/${REPO_NAME}:ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json -Compress

az ad app federated-credential create `
  --id $APP_ID `
  --parameters $FED_MAIN `
  --output none
Write-Host "    OK: main branch credential added" -ForegroundColor Green

Write-Host ""
Write-Host "==> Adding federated credential for production environment..." -ForegroundColor Cyan
$FED_PROD = @{
  name      = "github-actions-production-env"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_USERNAME}/${REPO_NAME}:environment:production"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json -Compress

az ad app federated-credential create `
  --id $APP_ID `
  --parameters $FED_PROD `
  --output none
Write-Host "    OK: production environment credential added" -ForegroundColor Green

# ── DONE ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host " SETUP COMPLETE" -ForegroundColor Yellow
Write-Host " Add these 5 secrets to GitHub Actions:" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host " AZURE_CLIENT_ID        = $APP_ID" -ForegroundColor White
Write-Host " AZURE_TENANT_ID        = $TENANT_ID" -ForegroundColor White
Write-Host " AZURE_SUBSCRIPTION_ID  = $SUBSCRIPTION_ID" -ForegroundColor White
Write-Host " LOGIC_APP_NAME         = $LOGIC_APP" -ForegroundColor White
Write-Host " RESOURCE_GROUP         = $RESOURCE_GROUP" -ForegroundColor White
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""
Write-Host " Open this URL to add secrets:" -ForegroundColor Cyan
Write-Host " https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/secrets/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host " Open this URL to create environments:" -ForegroundColor Cyan
Write-Host " https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/environments" -ForegroundColor Cyan
Write-Host ""
Write-Host " Storage account name: $STORAGE_ACCOUNT" -ForegroundColor Gray
Write-Host ""
Write-Host " Teardown when done (saves cost):" -ForegroundColor Gray
Write-Host "   az group delete --name $RESOURCE_GROUP --yes --no-wait" -ForegroundColor Gray
Write-Host "   az ad app delete --id $APP_ID" -ForegroundColor Gray
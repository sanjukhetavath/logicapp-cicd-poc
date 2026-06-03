#!/bin/bash
# ─────────────────────────────────────────────────────────────
# POC Setup Script — Logic App CI/CD with Deployment Slots
# Run this once with your personal Azure account
# ─────────────────────────────────────────────────────────────
set -e

# ── CONFIG — edit these ──────────────────────────────────────
RESOURCE_GROUP="rg-logicapp-poc"
LOCATION="australiaeast"
APP_PLAN="asp-logicapp-poc"
LOGIC_APP="la-poc-main"
STORAGE_ACCOUNT="stlogicapppoc$RANDOM"   # must be globally unique
# ─────────────────────────────────────────────────────────────

echo "==> Logging in..."
az login

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription: $SUBSCRIPTION_ID"
echo "Tenant:       $TENANT_ID"

echo ""
echo "==> Creating resource group..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

echo ""
echo "==> Creating storage account (required by Logic App)..."
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

echo ""
echo "==> Creating App Service Plan (WS1 — required for deployment slots)..."
az appservice plan create \
  --name $APP_PLAN \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku WS1 \
  --is-linux false

echo ""
echo "==> Creating Logic App Standard..."
az logicapp create \
  --name $LOGIC_APP \
  --resource-group $RESOURCE_GROUP \
  --plan $APP_PLAN \
  --storage-account $STORAGE_ACCOUNT \
  --location $LOCATION

echo ""
echo "==> Creating staging deployment slot..."
az logicapp deployment slot create \
  --name $LOGIC_APP \
  --resource-group $RESOURCE_GROUP \
  --slot staging

echo ""
echo "==> Enabling system-assigned managed identity on main slot..."
az logicapp identity assign \
  --name $LOGIC_APP \
  --resource-group $RESOURCE_GROUP

echo ""
echo "==> Setting up OIDC federated credential for GitHub Actions..."
echo "    Creating Entra ID app registration..."

APP_ID=$(az ad app create \
  --display-name "sp-logicapp-poc-github" \
  --query appId -o tsv)

echo "    App ID: $APP_ID"

SP_ID=$(az ad sp create \
  --id $APP_ID \
  --query id -o tsv)

echo "    Assigning Contributor role on resource group..."
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP

echo "    Adding federated credential for GitHub Actions..."
# Replace YOUR_GITHUB_USERNAME and YOUR_REPO_NAME below
GITHUB_USERNAME="sanjukhetavath"  
REPO_NAME="logicapp-cicd-poc" 

az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-actions-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_USERNAME}/${REPO_NAME}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

# Also add federated credential for environment (production gate)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-actions-production-env\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_USERNAME}/${REPO_NAME}:environment:production\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

echo ""
echo "────────────────────────────────────────────────────────"
echo " SETUP COMPLETE — add these to GitHub repo secrets:"
echo "────────────────────────────────────────────────────────"
echo " AZURE_CLIENT_ID      = $APP_ID"
echo " AZURE_TENANT_ID      = $TENANT_ID"
echo " AZURE_SUBSCRIPTION_ID= $SUBSCRIPTION_ID"
echo " LOGIC_APP_NAME       = $LOGIC_APP"
echo " RESOURCE_GROUP       = $RESOURCE_GROUP"
echo "────────────────────────────────────────────────────────"
echo ""
echo "Next steps:"
echo "  1. Add the above 5 secrets to GitHub: Settings → Secrets → Actions"
echo "  2. Create GitHub Environments: 'staging' (no approval) and 'production' (add yourself as reviewer)"
echo "  3. Push your code to main — the pipeline will trigger automatically"
echo ""
echo "To tear down everything after the POC:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo "  az ad app delete --id $APP_ID"

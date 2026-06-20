#!/usr/bin/env bash
# One-time setup: lets GitHub Actions authenticate to Azure with NO stored secret.
# Run this once, locally, with an account that has rights to create AD apps + role assignments.
set -euo pipefail

GITHUB_ORG="YOUR_ORG"
GITHUB_REPO="azure-cicd-demo"
APP_NAME="gh-oidc-${GITHUB_REPO}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Using subscription: $SUBSCRIPTION_ID"

# 1. Create the Azure AD application + service principal GitHub will impersonate.
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID" >/dev/null
echo "Created app registration: $APP_ID"

# 2. Federated credentials — one per trigger path. GitHub presents a signed
#    OIDC token at runtime; Azure checks it matches one of these subjects.
#    No client secret is ever generated or stored.
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "release-tags",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/tags/v*",
  "audiences": ["api://AzureADTokenExchange"]
}'

az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "pull-requests",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'

# 3. Least-privilege role assignments (adjust scopes from "subscription" to a
#    specific resource group once you know it, for tighter blast radius).
ACR_NAME="$1"          # e.g. ./setup-oidc.sh acrmyappabc123
AKS_RG="$2"             # resource group containing the AKS cluster

ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "AcrPush" --scope "$ACR_ID"

AKS_ID=$(az aks show --resource-group "$AKS_RG" --name "aks-myapp" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "Azure Kubernetes Service Cluster User Role" --scope "$AKS_ID"
# This RBAC role just lets CI fetch kubeconfig. Actual in-cluster permissions
# (what helm/kubectl can do once connected) are controlled separately by
# Kubernetes RBAC — bind the SP's object ID to a Role/RoleBinding scoped to
# the "staging" namespace only, so it can never touch "production".

echo ""
echo "Done. Add these as GitHub Actions *variables* (Settings > Secrets and variables > Actions > Variables):"
echo "  AZURE_CLIENT_ID       = $APP_ID"
echo "  AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "  AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo "  ACR_NAME              = $ACR_NAME"
echo "  AKS_RESOURCE_GROUP    = $AKS_RG"
echo "  AKS_CLUSTER_NAME      = aks-myapp"
echo ""
echo "None of these are secrets — that's the point of OIDC. There is no"
echo "AZURE_CLIENT_SECRET to rotate or leak."

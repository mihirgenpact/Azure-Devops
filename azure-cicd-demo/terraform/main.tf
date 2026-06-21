resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
}


data "azurerm_resource_group" "main" {
  name = var.existing_resource_group_name
}

# ---------------------------------------------------------------------------
# Container registry — where CI pushes images after build + scan
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "main" {
  name                = "acr${var.project_name}${local.suffix}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = false # we authenticate via Azure AD / OIDC, not static admin creds
}

# ---------------------------------------------------------------------------
# AKS cluster
#   - oidc_issuer_enabled + workload_identity_enabled: lets Kubernetes
#     ServiceAccounts assume Azure AD identities (no secrets stored in-cluster).
# ---------------------------------------------------------------------------

# Lets AKS nodes pull images from ACR without static credentials.

# ---------------------------------------------------------------------------
# Key Vault — app secrets, fetched via the Secrets Store CSI driver +
# workload identity (see helm/myapp/templates/secretproviderclass.yaml)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${local.suffix}"
  resource_group_name       = data.azurerm_resource_group.main.name
  location                  = data.azurerm_resource_group.main.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  soft_delete_retention_days = 7
}

data "azurerm_client_config" "current" {}

# Workload identity used by pods to read secrets from Key Vault.
resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${var.project_name}-workload"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
}



# Federates the AKS ServiceAccount "myapp-sa" in namespace "production"/"staging"
# to this Azure identity — this is the trust link, no secret involved.

resource "azurerm_federated_identity_credential" "workload_production" {
  name                = "fic-${var.project_name}-production"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:production:myapp-sa"
}

variable "existing_resource_group_name" {
  description = "Name of the existing resource group to deploy into"
  type        = string
}

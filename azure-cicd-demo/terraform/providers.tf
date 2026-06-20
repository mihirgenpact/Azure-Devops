terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  # Remote state — uncomment and fill in once you've created the storage account
  # (see scripts/setup-oidc.sh comments for a one-time bootstrap command).
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstateunique123"
  #   container_name       = "tfstate"
  #   key                  = "azure-cicd-demo.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
  backend "azurerm" {
    resource_group_name  = "gch-rg-eus-poc-corp-apexops-01"
    storage_account_name = "sttfstate3a6cab"
    container_name       = "tfstate"
    key                  = "azure-cicd-demo.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
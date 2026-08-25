terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "= 2.10.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.80.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azapi" {}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

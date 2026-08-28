terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

variable "name" {
  type = string
}

variable "identity_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

locals {
  key_vault_crypto_user_role_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/12338af0-0e69-4776-bea7-57ae8d297424"
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "foundry_cmk" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_key_vault" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

resource "azapi_resource" "foundry_key" {
  type      = "Microsoft.KeyVault/vaults/keys@2024-11-01"
  name      = "cmk-foundry"
  parent_id = azurerm_key_vault.this.id
  body = {
    properties = {
      kty     = "RSA"
      keySize = 3072
      attributes = {
        enabled = true
      }
      rotationPolicy = {
        attributes = {
          expiryTime = "P2Y"
        }
        lifetimeActions = [
          {
            trigger = {
              timeAfterCreate = "P18M"
            }
            action = {
              type = "Rotate"
            }
          },
          {
            trigger = {
              timeBeforeExpiry = "P30D"
            }
            action = {
              type = "Notify"
            }
          }
        ]
      }
    }
  }

  response_export_values    = ["properties.keyUriWithVersion"]
  schema_validation_enabled = false
}

resource "azapi_resource" "search_key" {
  type      = "Microsoft.KeyVault/vaults/keys@2024-11-01"
  name      = "cmk-search"
  parent_id = azurerm_key_vault.this.id
  body = {
    properties = {
      kty     = "RSA"
      keySize = 3072
      attributes = {
        enabled = true
      }
      rotationPolicy = {
        attributes = {
          expiryTime = "P2Y"
        }
        lifetimeActions = [
          {
            trigger = {
              timeAfterCreate = "P18M"
            }
            action = {
              type = "Rotate"
            }
          },
          {
            trigger = {
              timeBeforeExpiry = "P30D"
            }
            action = {
              type = "Notify"
            }
          }
        ]
      }
    }
  }

  response_export_values    = ["properties.keyUriWithVersion"]
  schema_validation_enabled = false
}

resource "azurerm_role_assignment" "foundry_key_crypto_user" {
  name                             = uuidv5("url", "${azapi_resource.foundry_key.id}|${azurerm_user_assigned_identity.foundry_cmk.principal_id}|12338af0-0e69-4776-bea7-57ae8d297424")
  scope                            = azapi_resource.foundry_key.id
  role_definition_id               = local.key_vault_crypto_user_role_id
  principal_id                     = azurerm_user_assigned_identity.foundry_cmk.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

module "private_endpoint" {
  source = "../private-endpoint"

  name                 = "pe-${var.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  tags                 = var.tags
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azurerm_key_vault.this.id
  group_ids            = ["vault"]
  private_dns_zone_ids = [var.private_dns_zone_id]
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "foundry_key_name" {
  value = azapi_resource.foundry_key.name
}

output "foundry_key_version" {
  value = element(reverse(split("/", azapi_resource.foundry_key.output.properties.keyUriWithVersion)), 0)
}

output "foundry_key_id" {
  value = azapi_resource.foundry_key.id
}

output "search_key_name" {
  value = azapi_resource.search_key.name
}

output "search_key_version" {
  value = element(reverse(split("/", azapi_resource.search_key.output.properties.keyUriWithVersion)), 0)
}

output "search_key_id" {
  value = azapi_resource.search_key.id
}

output "foundry_cmk_identity_id" {
  value = azurerm_user_assigned_identity.foundry_cmk.id
}

output "foundry_cmk_identity_client_id" {
  value = azurerm_user_assigned_identity.foundry_cmk.client_id
}

output "foundry_cmk_identity_principal_id" {
  value = azurerm_user_assigned_identity.foundry_cmk.principal_id
}

output "foundry_key_role_id" {
  value = azurerm_role_assignment.foundry_key_crypto_user.id
}

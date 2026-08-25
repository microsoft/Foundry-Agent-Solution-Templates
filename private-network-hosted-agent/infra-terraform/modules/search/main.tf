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

variable "location" {
  type = string
}

variable "private_endpoint_location" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
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

variable "search_key_id" {
  type = string
}

variable "deployment_principal_object_id" {
  type = string
}

locals {
  subscription_id                           = data.azurerm_client_config.current.subscription_id
  search_service_contributor_role_id        = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7ca78c08-252a-4471-8644-bb5ff32d4ba0"
  search_index_data_contributor_role_id     = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/8ebe5a00-799e-43f5-93ac-243d3dce84a7"
  key_vault_service_encryption_user_role_id = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/e147488a-f6f5-4113-8e2d-b22465e65bf6"
}

data "azurerm_client_config" "current" {}

resource "azapi_resource" "this" {
  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "basic"
    }
    properties = {
      replicaCount        = 1
      partitionCount      = 1
      hostingMode         = "Default"
      publicNetworkAccess = "Disabled"
      disableLocalAuth    = true
      networkRuleSet = {
        ipRules = []
      }
      encryptionWithCmk = {
        enforcement = "Enabled"
      }
    }
  }

  response_export_values    = ["identity.principalId"]
  schema_validation_enabled = false
}

resource "azurerm_role_assignment" "search_key" {
  name                             = uuidv5("url", "${var.search_key_id}|${azapi_resource.this.output.identity.principalId}|e147488a-f6f5-4113-8e2d-b22465e65bf6")
  scope                            = var.search_key_id
  role_definition_id               = local.key_vault_service_encryption_user_role_id
  principal_id                     = azapi_resource.this.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "bootstrap_service" {
  name               = uuidv5("url", "${azapi_resource.this.id}|${var.deployment_principal_object_id}|7ca78c08-252a-4471-8644-bb5ff32d4ba0")
  scope              = azapi_resource.this.id
  role_definition_id = local.search_service_contributor_role_id
  principal_id       = var.deployment_principal_object_id
}

resource "azurerm_role_assignment" "bootstrap_data" {
  name               = uuidv5("url", "${azapi_resource.this.id}|${var.deployment_principal_object_id}|8ebe5a00-799e-43f5-93ac-243d3dce84a7")
  scope              = azapi_resource.this.id
  role_definition_id = local.search_index_data_contributor_role_id
  principal_id       = var.deployment_principal_object_id
}

module "private_endpoint" {
  source = "../private-endpoint"

  name                 = "pe-${var.name}"
  location             = var.private_endpoint_location
  resource_group_name  = var.resource_group_name
  tags                 = var.tags
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azapi_resource.this.id
  group_ids            = ["searchService"]
  private_dns_zone_ids = [var.private_dns_zone_id]
}

output "search_service_name" {
  value = azapi_resource.this.name
}

output "search_service_id" {
  value = azapi_resource.this.id
}

output "search_endpoint" {
  value = "https://${azapi_resource.this.name}.search.windows.net"
}

output "search_principal_id" {
  value = azapi_resource.this.output.identity.principalId
}

output "search_key_role_id" {
  value = azurerm_role_assignment.search_key.id
}

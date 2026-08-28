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

variable "project_name" {
  type = string
}

variable "location" {
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

variable "agent_subnet_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  type = list(string)
}

variable "foundry_cmk_identity_id" {
  type = string
}

variable "foundry_cmk_identity_client_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "key_vault_uri" {
  type = string
}

variable "foundry_key_name" {
  type = string
}

variable "foundry_key_version" {
  type = string
}

variable "foundry_cmk_role_id" {
  type = string
}

variable "deployment_principal_object_id" {
  type = string
}

variable "invocation_test_principal_object_id" {
  type = string
}

variable "model_name" {
  type = string
}

variable "model_version" {
  type = string
}

variable "model_capacity" {
  type = number
}

locals {
  subscription_id                = data.azurerm_client_config.current.subscription_id
  key_vault_crypto_user_role_id  = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/12338af0-0e69-4776-bea7-57ae8d297424"
  foundry_user_role_id           = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  foundry_agent_consumer_role_id = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eed3b665-ab3a-47b6-8f48-c9382fb1dad6"
}

data "azurerm_client_config" "current" {}

resource "terraform_data" "cmk_authorization" {
  input = var.foundry_cmk_role_id
}

resource "azapi_resource" "account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.foundry_cmk_identity_id]
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = var.name
      disableLocalAuth       = true
      publicNetworkAccess    = "Disabled"
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = var.agent_subnet_id
          useMicrosoftManagedNetwork = false
        }
      ]
      encryption = {
        keySource = "Microsoft.KeyVault"
        keyVaultProperties = {
          keyVaultUri      = var.key_vault_uri
          keyName          = var.foundry_key_name
          keyVersion       = var.foundry_key_version
          identityClientId = var.foundry_cmk_identity_client_id
        }
      }
    }
  }

  response_export_values    = ["identity.principalId"]
  schema_validation_enabled = false

  depends_on = [terraform_data.cmk_authorization]
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = var.project_name
  parent_id = azapi_resource.account.id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = "Private Hosted Agent"
      description = "Private Python Hosted Agent with direct Azure AI Search SDK tool."
    }
  }

  response_export_values    = ["identity.principalId"]
  schema_validation_enabled = false
}

resource "azurerm_role_assignment" "account_key_vault" {
  name                             = uuidv5("url", "${var.key_vault_id}|${azapi_resource.account.output.identity.principalId}|12338af0-0e69-4776-bea7-57ae8d297424")
  scope                            = var.key_vault_id
  role_definition_id               = local.key_vault_crypto_user_role_id
  principal_id                     = azapi_resource.account.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "project_key_vault" {
  name                             = uuidv5("url", "${var.key_vault_id}|${azapi_resource.project.output.identity.principalId}|12338af0-0e69-4776-bea7-57ae8d297424")
  scope                            = var.key_vault_id
  role_definition_id               = local.key_vault_crypto_user_role_id
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name      = var.model_name
  parent_id = azapi_resource.account.id
  body = {
    sku = {
      name     = "Standard"
      capacity = var.model_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.model_name
        version = var.model_version
      }
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }

  schema_validation_enabled = false
}

resource "azurerm_role_assignment" "project_foundry" {
  name                             = uuidv5("url", "${azapi_resource.account.id}|${azapi_resource.project.output.identity.principalId}|53ca6127-db72-4b80-b1b0-d745d6d5456d")
  scope                            = azapi_resource.account.id
  role_definition_id               = local.foundry_user_role_id
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deployment_foundry" {
  name               = uuidv5("url", "${azapi_resource.project.id}|${var.deployment_principal_object_id}|53ca6127-db72-4b80-b1b0-d745d6d5456d")
  scope              = azapi_resource.project.id
  role_definition_id = local.foundry_user_role_id
  principal_id       = var.deployment_principal_object_id
}

resource "azurerm_role_assignment" "invocation_consumer" {
  count = var.invocation_test_principal_object_id == "" ? 0 : 1

  name               = uuidv5("url", "${azapi_resource.project.id}|${var.invocation_test_principal_object_id}|eed3b665-ab3a-47b6-8f48-c9382fb1dad6")
  scope              = azapi_resource.project.id
  role_definition_id = local.foundry_agent_consumer_role_id
  principal_id       = var.invocation_test_principal_object_id
}

module "private_endpoint" {
  source = "../private-endpoint"

  name                 = "pe-${var.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  tags                 = var.tags
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azapi_resource.account.id
  group_ids            = ["account"]
  private_dns_zone_ids = var.private_dns_zone_ids
}

output "account_name" {
  value = azapi_resource.account.name
}

output "account_id" {
  value = azapi_resource.account.id
}

output "account_principal_id" {
  value = azapi_resource.account.output.identity.principalId
}

output "project_name" {
  value = azapi_resource.project.name
}

output "project_id" {
  value = azapi_resource.project.id
}

output "project_principal_id" {
  value = azapi_resource.project.output.identity.principalId
}

output "project_endpoint" {
  value = "https://${azapi_resource.account.name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "account_key_vault_role_id" {
  value = azurerm_role_assignment.account_key_vault.id
}

output "project_key_vault_role_id" {
  value = azurerm_role_assignment.project_key_vault.id
}

output "project_foundry_role_id" {
  value = azurerm_role_assignment.project_foundry.id
}

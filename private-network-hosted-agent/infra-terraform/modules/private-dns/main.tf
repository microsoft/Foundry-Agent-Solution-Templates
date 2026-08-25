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

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "vnet_id" {
  type = string
}

variable "dns_inbound_subnet_id" {
  type = string
}

variable "dns_inbound_ip_address" {
  type = string
}

locals {
  zone_names = toset([
    "privatelink.cognitiveservices.azure.com",
    "privatelink.services.ai.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.search.windows.net",
    "privatelink.vaultcore.azure.net",
  ])
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.zone_names

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.zone_names

  name                  = "link-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azapi_resource" "resolver" {
  type      = "Microsoft.Network/dnsResolvers@2022-07-01"
  name      = "dnspr-${var.name}"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body = {
    properties = {
      virtualNetwork = {
        id = var.vnet_id
      }
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "inbound" {
  type      = "Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01"
  name      = "inbound"
  parent_id = azapi_resource.resolver.id
  location  = var.location
  tags      = var.tags
  body = {
    properties = {
      ipConfigurations = [
        {
          privateIpAllocationMethod = "Static"
          privateIpAddress          = var.dns_inbound_ip_address
          subnet = {
            id = var.dns_inbound_subnet_id
          }
        }
      ]
    }
  }

  schema_validation_enabled = false
}

output "foundry_zone_ids" {
  value = [
    azurerm_private_dns_zone.this["privatelink.cognitiveservices.azure.com"].id,
    azurerm_private_dns_zone.this["privatelink.services.ai.azure.com"].id,
    azurerm_private_dns_zone.this["privatelink.openai.azure.com"].id,
  ]
}

output "search_zone_id" {
  value = azurerm_private_dns_zone.this["privatelink.search.windows.net"].id
}

output "key_vault_zone_id" {
  value = azurerm_private_dns_zone.this["privatelink.vaultcore.azure.net"].id
}

output "inbound_ip_address" {
  value = var.dns_inbound_ip_address
}

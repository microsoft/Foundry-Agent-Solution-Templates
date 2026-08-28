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

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "connectivity_mode" {
  type = string
}

variable "vnet_id" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "gateway_subnet_id" {
  type = string
}

variable "p2s_address_pool" {
  type = string
}

variable "p2s_tenant_id" {
  type = string
}

variable "s2s_gateway_ip_address" {
  type = string
}

variable "s2s_remote_address_prefixes" {
  type = list(string)
}

variable "s2s_enable_bgp" {
  type = bool
}

variable "s2s_remote_asn" {
  type = number
}

variable "s2s_bgp_peering_address" {
  type = string
}

variable "s2s_shared_key" {
  type      = string
  sensitive = true
}

variable "remote_vnet_resource_id" {
  type = string
}

locals {
  uses_gateway     = contains(["pointToSite", "siteToSite"], var.connectivity_mode)
  is_point_to_site = var.connectivity_mode == "pointToSite"
  is_site_to_site  = var.connectivity_mode == "siteToSite"
  is_peering       = var.connectivity_mode == "vnetPeering"
  gateway_name     = "vpng-${var.name}"
  remote_vnet_name = local.is_peering ? element(split("/", var.remote_vnet_resource_id), 8) : "unused"
}

resource "azurerm_public_ip" "gateway" {
  count = local.uses_gateway ? 1 : 0

  name                = "pip-${var.name}-gateway"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  zones               = ["1", "2", "3"]
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_virtual_network_gateway" "this" {
  count = local.uses_gateway ? 1 : 0

  name                = local.gateway_name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  bgp_enabled         = local.is_site_to_site && var.s2s_enable_bgp
  generation          = "Generation2"
  sku                 = "VpnGw2AZ"
  tags                = var.tags

  ip_configuration {
    name                          = "default"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.gateway_subnet_id
    public_ip_address_id          = azurerm_public_ip.gateway[0].id
  }

  dynamic "vpn_client_configuration" {
    for_each = local.is_point_to_site ? [1] : []

    content {
      address_space        = [var.p2s_address_pool]
      vpn_client_protocols = ["OpenVPN"]
      vpn_auth_types       = ["AAD"]
      aad_tenant           = "https://login.microsoftonline.com/${var.p2s_tenant_id}/"
      aad_audience         = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
      aad_issuer           = "https://sts.windows.net/${var.p2s_tenant_id}/"
    }
  }
}

resource "azurerm_local_network_gateway" "this" {
  count = local.is_site_to_site ? 1 : 0

  name                = "lng-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  gateway_address     = var.s2s_gateway_ip_address
  address_space       = var.s2s_remote_address_prefixes
  tags                = var.tags

  dynamic "bgp_settings" {
    for_each = var.s2s_enable_bgp ? [1] : []

    content {
      asn                 = var.s2s_remote_asn
      bgp_peering_address = var.s2s_bgp_peering_address
      peer_weight         = 0
    }
  }
}

resource "azurerm_virtual_network_gateway_connection" "site_to_site" {
  count = local.is_site_to_site ? 1 : 0

  name                       = "conn-${var.name}-s2s"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  type                       = "IPsec"
  connection_protocol        = "IKEv2"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.this[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.this[0].id
  shared_key                 = var.s2s_shared_key
  enable_bgp                 = var.s2s_enable_bgp
  routing_weight             = 0
  tags                       = var.tags
}

resource "azurerm_virtual_network_peering" "local_to_remote" {
  count = local.is_peering ? 1 : 0

  name                         = "to-${local.remote_vnet_name}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = var.vnet_name
  remote_virtual_network_id    = var.remote_vnet_resource_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azapi_resource" "remote_to_local" {
  count = local.is_peering ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01"
  name      = "to-${var.vnet_name}"
  parent_id = var.remote_vnet_resource_id
  body = {
    properties = {
      allowVirtualNetworkAccess = true
      allowForwardedTraffic     = false
      allowGatewayTransit       = false
      useRemoteGateways         = false
      remoteVirtualNetwork = {
        id = var.vnet_id
      }
    }
  }

  schema_validation_enabled = false
}

output "vpn_gateway_name" {
  value = local.uses_gateway ? azurerm_virtual_network_gateway.this[0].name : ""
}

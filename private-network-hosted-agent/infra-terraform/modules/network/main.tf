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

variable "p2s_address_pool" {
  type = string
}

variable "vnet_address_prefix" {
  type = string
}

variable "agent_subnet_prefix" {
  type = string
}

variable "private_endpoint_subnet_prefix" {
  type = string
}

variable "firewall_subnet_prefix" {
  type = string
}

variable "firewall_creation_required" {
  type = bool
}

variable "gateway_subnet_prefix" {
  type = string
}

variable "dns_inbound_subnet_prefix" {
  type = string
}

locals {
  uses_gateway               = contains(["pointToSite", "siteToSite"], var.connectivity_mode)
  vnet_name                  = "vnet-${var.name}"
  firewall_name              = "afw-${var.name}"
  firewall_policy_name       = "afwp-${var.name}"
  firewall_public_ip         = "pip-${var.name}-firewall"
  agent_subnet_id            = "${azurerm_virtual_network.this.id}/subnets/snet-agent"
  private_endpoint_subnet_id = "${azurerm_virtual_network.this.id}/subnets/snet-private-endpoints"
  firewall_subnet_id         = "${azurerm_virtual_network.this.id}/subnets/AzureFirewallSubnet"
  dns_inbound_subnet_id      = "${azurerm_virtual_network.this.id}/subnets/snet-dns-inbound"
  gateway_subnet_id          = "${azurerm_virtual_network.this.id}/subnets/GatewaySubnet"
  subnet_retry = {
    error_message_regex = [
      "(?i)AnotherOperationInProgress",
      "(?i)ResourceNotFound",
      "(?i)RetryableError",
      "(?i)unexpected status 404",
    ]
    interval_seconds     = 10
    max_interval_seconds = 60
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${var.name}-private-endpoints"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "private_endpoint_p2s" {
  count = var.connectivity_mode == "pointToSite" ? 1 : 0

  name                        = "AllowPointToSitePrivateHttps"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.p2s_address_pool
  destination_address_prefix  = var.private_endpoint_subnet_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "private_endpoint_vnet" {
  name                        = "AllowApprovedPrivateHttps"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = var.private_endpoint_subnet_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "private_endpoint_deny" {
  name                        = "DenyOtherPrivateEndpointInbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = var.private_endpoint_subnet_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name

  depends_on = [azurerm_network_security_rule.private_endpoint_vnet]
}

resource "azurerm_route_table" "agent" {
  name                          = "rt-${var.name}-agent"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_prefix]
  tags                = var.tags
}

resource "azapi_update_resource" "vnet_private_endpoint_policy" {
  type        = "Microsoft.Network/virtualNetworks@2024-07-01"
  resource_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      privateEndpointVNetPolicies = "Disabled"
    }
  }
}

resource "azapi_resource" "firewall_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "AzureFirewallSubnet"
  parent_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      addressPrefix                     = var.firewall_subnet_prefix
      defaultOutboundAccess             = true
      privateEndpointNetworkPolicies    = "Disabled"
      privateLinkServiceNetworkPolicies = "Enabled"
    }
  }

  locks                     = [azurerm_virtual_network.this.id]
  retry                     = local.subnet_retry
  schema_validation_enabled = true

  depends_on = [azapi_update_resource.vnet_private_endpoint_policy]
}

resource "azapi_resource" "agent_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "snet-agent"
  parent_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      addressPrefix                     = var.agent_subnet_prefix
      defaultOutboundAccess             = true
      privateEndpointNetworkPolicies    = "Disabled"
      privateLinkServiceNetworkPolicies = "Enabled"
      delegations = [
        {
          name = "Microsoft.App.environments"
          properties = {
            serviceName = "Microsoft.App/environments"
          }
        }
      ]
    }
  }

  locks                     = [azurerm_virtual_network.this.id]
  retry                     = local.subnet_retry
  schema_validation_enabled = true

  depends_on = [azapi_update_resource.firewall_policy_attachment]
}

resource "azapi_resource" "private_endpoint_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "snet-private-endpoints"
  parent_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      addressPrefix         = var.private_endpoint_subnet_prefix
      defaultOutboundAccess = true
      networkSecurityGroup = {
        id = azurerm_network_security_group.private_endpoints.id
      }
      privateEndpointNetworkPolicies    = "Enabled"
      privateLinkServiceNetworkPolicies = "Enabled"
    }
  }

  locks                     = [azurerm_virtual_network.this.id]
  retry                     = local.subnet_retry
  schema_validation_enabled = true

  depends_on = [azapi_resource.agent_subnet]
}

resource "azapi_resource" "dns_inbound_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "snet-dns-inbound"
  parent_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      addressPrefix                     = var.dns_inbound_subnet_prefix
      defaultOutboundAccess             = true
      privateEndpointNetworkPolicies    = "Disabled"
      privateLinkServiceNetworkPolicies = "Enabled"
      delegations = [
        {
          name = "Microsoft.Network.dnsResolvers"
          properties = {
            serviceName = "Microsoft.Network/dnsResolvers"
          }
        }
      ]
    }
  }

  locks                     = [azurerm_virtual_network.this.id]
  retry                     = local.subnet_retry
  schema_validation_enabled = true

  depends_on = [azapi_resource.private_endpoint_subnet]
}

resource "azapi_resource" "gateway_subnet" {
  count = local.uses_gateway ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "GatewaySubnet"
  parent_id = azurerm_virtual_network.this.id
  body = {
    properties = {
      addressPrefix                     = var.gateway_subnet_prefix
      defaultOutboundAccess             = true
      privateEndpointNetworkPolicies    = "Disabled"
      privateLinkServiceNetworkPolicies = "Enabled"
    }
  }

  locks                     = [azurerm_virtual_network.this.id]
  retry                     = local.subnet_retry
  schema_validation_enabled = true

  depends_on = [azapi_resource.dns_inbound_subnet]
}

resource "azurerm_public_ip" "firewall" {
  name                = local.firewall_public_ip
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

resource "azurerm_firewall_policy" "this" {
  name                     = local.firewall_policy_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = var.tags

  dns {
    proxy_enabled = false
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "agent_egress" {
  name               = "agent-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  network_rule_collection {
    name     = "allow-entra"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-entra-https"
      protocols             = ["TCP"]
      source_addresses      = [var.agent_subnet_prefix]
      destination_addresses = ["AzureActiveDirectory"]
      destination_ports     = ["443"]
    }
  }

  application_rule_collection {
    name     = "allow-hosted-agent-source-runtime"
    priority = 200
    action   = "Allow"

    rule {
      name             = "documented-source-runtime-dependencies"
      source_addresses = [var.agent_subnet_prefix]
      destination_fqdns = [
        "mcr.microsoft.com",
        "*.login.microsoft.com",
        "*.login.microsoftonline.com",
      ]
      terminate_tls = false

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  count = var.firewall_creation_required ? 1 : 0

  name                = local.firewall_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  threat_intel_mode   = "Alert"
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = local.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  lifecycle {
    ignore_changes = [firewall_policy_id]
  }

  depends_on = [azapi_resource.firewall_subnet]
}

data "azurerm_firewall" "existing" {
  count = var.firewall_creation_required ? 0 : 1

  name                = local.firewall_name
  resource_group_name = var.resource_group_name
}

locals {
  firewall_id = var.firewall_creation_required ? azurerm_firewall.this[0].id : data.azurerm_firewall.existing[0].id
  firewall_private_ip = var.firewall_creation_required ? (
    azurerm_firewall.this[0].ip_configuration[0].private_ip_address
    ) : (
    data.azurerm_firewall.existing[0].ip_configuration[0].private_ip_address
  )
}

resource "azapi_update_resource" "firewall_policy_attachment" {
  type        = "Microsoft.Network/azureFirewalls@2024-05-01"
  resource_id = local.firewall_id
  body = {
    properties = {
      firewallPolicy = {
        id = azurerm_firewall_policy.this.id
      }
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.agent_egress]
}

resource "azurerm_route" "default_via_firewall" {
  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.agent.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.firewall_private_ip

  depends_on = [azapi_update_resource.firewall_policy_attachment]
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  value = azurerm_virtual_network.this.name
}

output "agent_subnet_id" {
  value = local.agent_subnet_id

  depends_on = [azapi_resource.agent_subnet]
}

output "private_endpoint_subnet_id" {
  value = local.private_endpoint_subnet_id

  depends_on = [azapi_resource.private_endpoint_subnet]
}

output "private_endpoint_nsg_id" {
  value = azurerm_network_security_group.private_endpoints.id
}

output "dns_inbound_subnet_id" {
  value = local.dns_inbound_subnet_id

  depends_on = [azapi_resource.dns_inbound_subnet]
}

output "gateway_subnet_id" {
  value = local.uses_gateway ? local.gateway_subnet_id : ""

  depends_on = [azapi_resource.gateway_subnet]
}

output "firewall_id" {
  value = local.firewall_id
}

output "firewall_private_ip" {
  value = local.firewall_private_ip
}

output "agent_route_table_id" {
  value = azurerm_route_table.agent.id
}

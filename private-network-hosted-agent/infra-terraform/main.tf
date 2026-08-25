resource "terraform_data" "contract" {
  lifecycle {
    precondition {
      condition     = local.has_container_registry_id == local.has_container_registry_target
      error_message = "containerRegistryResourceId and containerRegistryEndpoint must be supplied together."
    }

    precondition {
      condition     = var.connectivityMode != "vnetPeering" || var.remoteVnetResourceId != ""
      error_message = "remoteVnetResourceId is required when connectivityMode is vnetPeering."
    }

    precondition {
      condition     = var.containerRegistryResourceId == trimspace(var.containerRegistryResourceId)
      error_message = "containerRegistryResourceId must not contain leading or trailing whitespace."
    }

    precondition {
      condition     = var.containerRegistryEndpoint == trimspace(var.containerRegistryEndpoint)
      error_message = "containerRegistryEndpoint must not contain leading or trailing whitespace."
    }
  }
}

moved {
  from = module.network.azurerm_subnet_route_table_association.agent
  to   = azurerm_subnet_route_table_association.agent_post_injection
}

removed {
  from = module.network.azurerm_subnet_network_security_group_association.agent

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_subnet_network_security_group_association.private_endpoints_post_injection

  lifecycle {
    destroy = false
  }
}

moved {
  from = module.network.azurerm_subnet.agent
  to   = module.network.azapi_resource.agent_subnet
}

moved {
  from = module.network.azurerm_subnet.private_endpoints
  to   = module.network.azapi_resource.private_endpoint_subnet
}

moved {
  from = module.network.azurerm_subnet.firewall
  to   = module.network.azapi_resource.firewall_subnet
}

moved {
  from = module.network.azurerm_subnet.dns_inbound
  to   = module.network.azapi_resource.dns_inbound_subnet
}

moved {
  from = module.network.azurerm_subnet.gateway
  to   = module.network.azapi_resource.gateway_subnet
}

removed {
  from = module.network.azurerm_network_security_rule.agent_vnet

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.network.azurerm_network_security_group.agent

  lifecycle {
    destroy = false
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.resource_group_tags

  depends_on = [terraform_data.contract]
}

module "network" {
  source = "./modules/network"

  name                           = local.resource_prefix
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  tags                           = local.tags
  connectivity_mode              = var.connectivityMode
  p2s_address_pool               = var.p2sAddressPool
  vnet_address_prefix            = var.vnetAddressPrefix
  agent_subnet_prefix            = var.agentSubnetPrefix
  private_endpoint_subnet_prefix = var.privateEndpointSubnetPrefix
  firewall_subnet_prefix         = var.firewallSubnetPrefix
  firewall_creation_required     = var.firewallCreationRequired
  gateway_subnet_prefix          = var.gatewaySubnetPrefix
  dns_inbound_subnet_prefix      = var.dnsInboundSubnetPrefix
}

module "private_dns" {
  source = "./modules/private-dns"

  name                   = local.resource_prefix
  location               = var.location
  resource_group_id      = azurerm_resource_group.this.id
  resource_group_name    = azurerm_resource_group.this.name
  tags                   = local.tags
  vnet_id                = module.network.vnet_id
  dns_inbound_subnet_id  = module.network.dns_inbound_subnet_id
  dns_inbound_ip_address = var.dnsInboundIpAddress
}

module "connectivity" {
  source = "./modules/connectivity"

  name                        = local.resource_prefix
  location                    = var.location
  resource_group_name         = azurerm_resource_group.this.name
  tags                        = local.tags
  connectivity_mode           = var.connectivityMode
  vnet_id                     = module.network.vnet_id
  vnet_name                   = module.network.vnet_name
  gateway_subnet_id           = module.network.gateway_subnet_id
  p2s_address_pool            = var.p2sAddressPool
  p2s_tenant_id               = local.p2s_tenant_id
  s2s_gateway_ip_address      = var.s2sGatewayIpAddress
  s2s_remote_address_prefixes = var.s2sRemoteAddressPrefixes
  s2s_enable_bgp              = var.s2sEnableBgp
  s2s_remote_asn              = var.s2sRemoteAsn
  s2s_bgp_peering_address     = var.s2sBgpPeeringAddress
  s2s_shared_key              = var.s2sSharedKey
  remote_vnet_resource_id     = var.remoteVnetResourceId
}

module "key_vault" {
  source = "./modules/key-vault"

  name                       = substr("kv-${local.sanitized_environment}-${local.unique_suffix}", 0, 24)
  identity_name              = "${local.resource_prefix}-foundry-cmk"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  tags                       = local.tags
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  private_dns_zone_id        = module.private_dns.key_vault_zone_id
}

module "search" {
  source = "./modules/search"

  name                           = substr("srch-${local.sanitized_environment}-${local.unique_suffix}", 0, 60)
  location                       = var.searchLocation
  private_endpoint_location      = var.location
  resource_group_id              = azurerm_resource_group.this.id
  resource_group_name            = azurerm_resource_group.this.name
  tags                           = local.tags
  private_endpoint_subnet_id     = module.network.private_endpoint_subnet_id
  private_dns_zone_id            = module.private_dns.search_zone_id
  search_key_id                  = module.key_vault.search_key_id
  deployment_principal_object_id = var.deploymentPrincipalObjectId
}

module "foundry" {
  source = "./modules/foundry"

  name                                = substr("aif${local.compact_prefix}", 0, 64)
  project_name                        = substr("proj-${local.sanitized_environment}-${local.unique_suffix}", 0, 64)
  location                            = var.location
  resource_group_id                   = azurerm_resource_group.this.id
  resource_group_name                 = azurerm_resource_group.this.name
  tags                                = merge(local.tags, { "azd-service-name" = "private-search-agent" })
  agent_subnet_id                     = module.network.agent_subnet_id
  private_endpoint_subnet_id          = module.network.private_endpoint_subnet_id
  private_dns_zone_ids                = module.private_dns.foundry_zone_ids
  foundry_cmk_identity_id             = module.key_vault.foundry_cmk_identity_id
  foundry_cmk_identity_client_id      = module.key_vault.foundry_cmk_identity_client_id
  key_vault_id                        = module.key_vault.key_vault_id
  key_vault_uri                       = module.key_vault.key_vault_uri
  foundry_key_name                    = module.key_vault.foundry_key_name
  foundry_key_version                 = module.key_vault.foundry_key_version
  foundry_cmk_role_id                 = module.key_vault.foundry_key_role_id
  deployment_principal_object_id      = var.deploymentPrincipalObjectId
  invocation_test_principal_object_id = var.invocationTestPrincipalObjectId
  model_name                          = var.modelName
  model_version                       = var.modelVersion
  model_capacity                      = var.modelCapacity

}

# Foundry attaches a platform-managed NSG while creating the network injection.
# Apply the customer UDR afterward so Hosted Agent egress remains forced through
# the solution Firewall without fighting the platform-owned NSG.
resource "azurerm_subnet_route_table_association" "agent_post_injection" {
  subnet_id      = module.network.agent_subnet_id
  route_table_id = module.network.agent_route_table_id

  depends_on = [module.foundry]
}

resource "azapi_update_resource" "private_endpoint_subnet_nsg_post_injection" {
  type        = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  resource_id = module.network.private_endpoint_subnet_id
  body = {
    properties = {
      networkSecurityGroup = {
        id = module.network.private_endpoint_nsg_id
      }
    }
  }

  depends_on = [module.foundry]
}

module "container_registry_connection" {
  count  = local.has_existing_container_registry ? 1 : 0
  source = "./modules/container-registry-connection"

  project_id                     = module.foundry.project_id
  project_principal_id           = module.foundry.project_principal_id
  connection_name                = substr("acr-${local.sanitized_environment}-${local.unique_suffix}", 0, 64)
  container_registry_resource_id = var.containerRegistryResourceId
  container_registry_endpoint    = var.containerRegistryEndpoint
}

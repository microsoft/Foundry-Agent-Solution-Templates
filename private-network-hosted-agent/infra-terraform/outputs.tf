output "AZURE_RESOURCE_GROUP" {
  value = azurerm_resource_group.this.name
}

output "AZURE_LOCATION" {
  value = var.location
}

output "AZURE_SEARCH_LOCATION" {
  value = var.searchLocation
}

output "RESOURCE_PREFIX" {
  value = local.resource_prefix
}

output "CONNECTIVITY_MODE" {
  value = var.connectivityMode
}

output "AZURE_VNET_ID" {
  value = module.network.vnet_id
}

output "AZURE_FIREWALL_ID" {
  value = module.network.firewall_id
}

output "AZURE_DNS_RESOLVER_INBOUND_IP" {
  value = module.private_dns.inbound_ip_address
}

output "AZURE_VPN_GATEWAY_NAME" {
  value = module.connectivity.vpn_gateway_name
}

output "AZURE_AI_ACCOUNT_NAME" {
  value = module.foundry.account_name
}

output "AZURE_AI_ACCOUNT_ID" {
  value = module.foundry.account_id
}

output "AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID" {
  value = module.foundry.account_principal_id
}

output "AZURE_AI_PROJECT_NAME" {
  value = module.foundry.project_name
}

output "AZURE_AI_PROJECT_ID" {
  value = module.foundry.project_id
}

output "AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID" {
  value = module.foundry.project_principal_id
}

output "FOUNDRY_PROJECT_ENDPOINT" {
  value = module.foundry.project_endpoint
}

output "AZURE_AI_PROJECT_ENDPOINT" {
  value = module.foundry.project_endpoint
}

output "AZURE_AI_MODEL_DEPLOYMENT_NAME" {
  value = var.modelName
}

output "AZURE_SEARCH_SERVICE_NAME" {
  value = module.search.search_service_name
}

output "AZURE_SEARCH_SERVICE_ID" {
  value = module.search.search_service_id
}

output "AZURE_SEARCH_ENDPOINT" {
  value = module.search.search_endpoint
}

output "AZURE_SEARCH_INDEX_NAME" {
  value = "private-knowledge"
}

output "AZURE_SEARCH_IDENTITY_PRINCIPAL_ID" {
  value = module.search.search_principal_id
}

output "AZURE_KEY_VAULT_NAME" {
  value = module.key_vault.key_vault_name
}

output "AZURE_KEY_VAULT_ID" {
  value = module.key_vault.key_vault_id
}

output "AZURE_KEY_VAULT_URI" {
  value = module.key_vault.key_vault_uri
}

output "AZURE_FOUNDRY_CMK_KEY_NAME" {
  value = module.key_vault.foundry_key_name
}

output "AZURE_FOUNDRY_CMK_KEY_VERSION" {
  value = module.key_vault.foundry_key_version
}

output "AZURE_FOUNDRY_CMK_KEY_ID" {
  value = module.key_vault.foundry_key_id
}

output "AZURE_FOUNDRY_CMK_IDENTITY_PRINCIPAL_ID" {
  value = module.key_vault.foundry_cmk_identity_principal_id
}

output "AZURE_SEARCH_CMK_KEY_NAME" {
  value = module.key_vault.search_key_name
}

output "AZURE_SEARCH_CMK_KEY_VERSION" {
  value = module.key_vault.search_key_version
}

output "AZURE_SEARCH_CMK_KEY_ID" {
  value = module.key_vault.search_key_id
}

output "DEPLOYMENT_PRINCIPAL_OBJECT_ID" {
  value = var.deploymentPrincipalObjectId
}

output "RBAC_FOUNDRY_CMK_IDENTITY_ROLE_ID" {
  value = module.key_vault.foundry_key_role_id
}

output "RBAC_SEARCH_CMK_IDENTITY_ROLE_ID" {
  value = module.search.search_key_role_id
}

output "RBAC_FOUNDRY_ACCOUNT_VAULT_ROLE_ID" {
  value = module.foundry.account_key_vault_role_id
}

output "RBAC_FOUNDRY_PROJECT_VAULT_ROLE_ID" {
  value = module.foundry.project_key_vault_role_id
}

output "RBAC_FOUNDRY_PROJECT_ACCOUNT_ROLE_ID" {
  value = module.foundry.project_foundry_role_id
}

output "AZURE_CONTAINER_REGISTRY_RESOURCE_ID" {
  value = local.has_existing_container_registry ? var.containerRegistryResourceId : ""
}

output "AZURE_CONTAINER_REGISTRY_ENDPOINT" {
  value = local.has_existing_container_registry ? var.containerRegistryEndpoint : ""
}

output "AZURE_CONTAINER_REGISTRY_CONNECTION_NAME" {
  value = local.has_existing_container_registry ? module.container_registry_connection[0].connection_name : ""
}

output "AZURE_AI_PROJECT_ACR_CONNECTION_NAME" {
  value = local.has_existing_container_registry ? module.container_registry_connection[0].connection_name : ""
}

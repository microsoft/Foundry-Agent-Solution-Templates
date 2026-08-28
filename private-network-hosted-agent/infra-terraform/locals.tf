data "azurerm_client_config" "current" {}

locals {
  resource_group_name = "rg-${var.environmentName}"
  sanitized_environment = substr(
    replace(lower(var.environmentName), "-", ""),
    0,
    10
  )
  unique_suffix = substr(md5(join("|", [
    data.azurerm_client_config.current.subscription_id,
    local.resource_group_name,
    var.environmentName,
  ])), 0, 6)
  resource_prefix = "fpha-${local.sanitized_environment}-${local.unique_suffix}"
  compact_prefix  = substr("fpha${local.sanitized_environment}${local.unique_suffix}", 0, 20)

  tags = {
    "azd-env-name"      = var.environmentName
    "solution-template" = "foundry-private-hosted-agent"
    "connectivity-mode" = var.connectivityMode
  }

  resource_group_tags = {
    "azd-env-name"             = var.environmentName
    "solution-template"        = "foundry-private-hosted-agent"
    "resource-group-ownership" = "template-created"
  }

  p2s_tenant_id                 = var.p2sTenantId == "" ? data.azurerm_client_config.current.tenant_id : var.p2sTenantId
  has_container_registry_id     = trimspace(var.containerRegistryResourceId) != ""
  has_container_registry_target = trimspace(var.containerRegistryEndpoint) != ""
  has_existing_container_registry = (
    local.has_container_registry_id &&
    local.has_container_registry_target
  )
}

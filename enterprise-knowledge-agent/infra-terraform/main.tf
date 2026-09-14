locals {
  create_demo_search = var.searchMode == "demo"
  search_name = var.searchServiceName != "" ? var.searchServiceName : substr(
    "srch-${substr(md5("/subscriptions/${var.subscriptionId}/resourceGroups/${var.resourceGroupName}"), 0, 12)}",
    0,
    60
  )
}

resource "azurerm_search_service" "demo" {
  count = local.create_demo_search ? 1 : 0

  name                          = local.search_name
  resource_group_name           = var.resourceGroupName
  location                      = var.searchLocation
  sku                           = var.searchSku
  local_authentication_enabled  = false
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "deployer_service_contributor" {
  count = local.create_demo_search ? 1 : 0

  scope                = azurerm_search_service.demo[0].id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.principalId
}

resource "azurerm_role_assignment" "deployer_data_contributor" {
  count = local.create_demo_search ? 1 : 0

  scope                = azurerm_search_service.demo[0].id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.principalId
}

mock_provider "azurerm" {}

variables {
  subscriptionId    = "00000000-0000-0000-0000-000000000000"
  resourceGroupName = "rg-enterprise-knowledge-test"
  principalId       = "00000000-0000-0000-0000-000000000001"
}

run "demo_creates_owned_search_and_rbac" {
  command = plan

  variables {
    searchMode = "demo"
  }

  assert {
    condition     = length(azurerm_search_service.demo) == 1
    error_message = "Demo mode must create exactly one Search service."
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer_service_contributor) == 1 && length(azurerm_role_assignment.deployer_data_contributor) == 1
    error_message = "Demo mode must grant both provisioning roles at the Search scope."
  }

  assert {
    condition     = azurerm_search_service.demo[0].local_authentication_enabled == false
    error_message = "The demo Search service must remain keyless."
  }
}

run "byo_creates_no_owned_resources" {
  command = plan

  variables {
    searchMode              = "byo"
    existingSearchEndpoint  = "https://existing.search.windows.net"
    existingSearchServiceId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/customer/providers/Microsoft.Search/searchServices/existing"
  }

  assert {
    condition     = length(azurerm_search_service.demo) == 0 && length(azurerm_role_assignment.deployer_service_contributor) == 0 && length(azurerm_role_assignment.deployer_data_contributor) == 0
    error_message = "BYO mode must not create or own Search resources."
  }

  assert {
    condition     = output.AZURE_SEARCH_ENDPOINT == "https://existing.search.windows.net"
    error_message = "BYO mode must pass through the configured endpoint."
  }
}

run "byo_requires_existing_search_coordinates" {
  command = plan

  variables {
    searchMode = "byo"
  }

  expect_failures = [output.AZURE_SEARCH_ENDPOINT]
}

run "search_sku_is_restricted" {
  command = plan

  variables {
    searchSku = "free"
  }

  expect_failures = [var.searchSku]
}


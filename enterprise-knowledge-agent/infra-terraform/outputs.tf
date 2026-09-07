output "AZURE_SEARCH_ENDPOINT" {
  value = var.searchMode == "demo" ? "https://${azurerm_search_service.demo[0].name}.search.windows.net" : var.existingSearchEndpoint

  precondition {
    condition     = var.searchMode == "demo" || (var.existingSearchEndpoint != "" && var.existingSearchServiceId != "")
    error_message = "existingSearchEndpoint and existingSearchServiceId are required in byo mode."
  }
  precondition {
    condition     = var.searchMode == "demo" || startswith(var.existingSearchEndpoint, "https://")
    error_message = "existingSearchEndpoint must be an HTTPS URL."
  }
  precondition {
    condition     = var.searchMode == "demo" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Search/searchServices/[^/]+$", var.existingSearchServiceId))
    error_message = "existingSearchServiceId must be a canonical Search service resource ID."
  }
}

output "AZURE_SEARCH_SERVICE_NAME" {
  value = var.searchMode == "demo" ? azurerm_search_service.demo[0].name : element(reverse(split("/", var.existingSearchServiceId)), 0)
}

output "AZURE_SEARCH_SERVICE_ID" {
  value = var.searchMode == "demo" ? azurerm_search_service.demo[0].id : var.existingSearchServiceId
}

output "AZURE_SEARCH_PRINCIPAL_ID" {
  value = var.searchMode == "demo" ? azurerm_search_service.demo[0].identity[0].principal_id : ""
}

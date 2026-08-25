terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  route = "tool-${lower(var.foundry_project_name)}-github-mcp"
}

resource "azapi_resource" "backend" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "github-mcp"
  parent_id = var.apim_id

  body = {
    properties = {
      protocol = "http"
      url      = "https://api.githubcopilot.com/mcp"
    }
  }
}

resource "azapi_resource" "api" {
  type                      = "Microsoft.ApiManagement/service/apis@2024-10-01-preview"
  name                      = local.route
  parent_id                 = var.apim_id
  schema_validation_enabled = false

  body = {
    properties = {
      displayName          = "${var.foundry_project_name} - MCP Tool (GitHub)"
      apiRevision          = "1"
      subscriptionRequired = false
      serviceUrl           = "https://api.githubcopilot.com/mcp"
      backendId            = azapi_resource.backend.name
      path                 = local.route
      protocols            = ["https"]
      type                 = "mcp"
      mcpProperties = {
        endpoints = {
          mcp = {
            uriTemplate = "/mcp"
          }
        }
        isFederationRouter = false
      }
    }
  }
}

resource "azapi_resource" "policy" {
  type                      = "Microsoft.ApiManagement/service/apis/policies@2024-10-01-preview"
  name                      = "policy"
  parent_id                 = azapi_resource.api.id
  schema_validation_enabled = false

  body = {
    properties = {
      format = "rawxml"
      value  = var.policy
    }
  }
}

output "gateway_url" {
  value = "https://${var.apim_name}.azure-api.net/${local.route}"
}

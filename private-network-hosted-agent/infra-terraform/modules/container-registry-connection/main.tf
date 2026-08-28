terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

variable "project_id" {
  type = string
}

variable "project_principal_id" {
  type = string
}

variable "connection_name" {
  type = string
}

variable "container_registry_resource_id" {
  type = string
}

variable "container_registry_endpoint" {
  type = string
}

resource "azapi_resource" "this" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = var.connection_name
  parent_id = var.project_id
  body = {
    properties = {
      category      = "ContainerRegistry"
      target        = var.container_registry_endpoint
      authType      = "ManagedIdentity"
      isSharedToAll = true
      credentials = {
        clientId   = var.project_principal_id
        resourceId = var.container_registry_resource_id
      }
      metadata = {
        ResourceId = var.container_registry_resource_id
      }
    }
  }

  schema_validation_enabled = false
}

output "connection_name" {
  value = azapi_resource.this.name
}

output "connection_id" {
  value = azapi_resource.this.id
}

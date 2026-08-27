terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

locals {
  methods         = toset(["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "TRACE"])
  direct_api_id   = "${lower(var.foundry_account_name)}-model-gateway"
  direct_api_path = "ai-gateway"
  product_name = substr(
    "${lower(var.foundry_account_name)}-${lower(var.foundry_project_name)}-ai-${substr(md5("${var.foundry_project_id}${var.foundry_account_name}${var.foundry_project_name}"), 0, 13)}",
    0,
    80
  )
  portal_backend_policy = <<-XML
    <policies>
      <inbound>
        <base />
        <set-backend-service backend-id="${var.foundry_account_name}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
  direct_responses_policy = replace(
    replace(
      var.gateway_policy,
      "__TENANT_ID__",
      var.tenant_id
    ),
    "__BACKEND_ID__",
    var.foundry_account_name
  )
  rendered_user_level_policy = replace(
    var.user_level_policy,
    "__PROJECT_NAME__",
    var.foundry_project_name
  )
}

resource "azapi_resource" "backend" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = var.foundry_account_name
  parent_id                 = var.apim_id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol   = "http"
      url        = "https://${var.foundry_account_name}.services.ai.azure.com/"
      resourceId = "https://management.azure.com${var.foundry_account_id}"
      credentials = {
        managedIdentity = {
          resource = "https://ai.azure.com/"
        }
      }
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }
}

resource "azapi_resource" "portal_api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = var.foundry_account_name
  parent_id = var.apim_id

  body = {
    properties = {
      displayName          = "${var.foundry_project_name} - Model API (API Key + Portal Admin Center)"
      apiRevision          = "1"
      description          = "Portal-compatible subscription-key model gateway."
      path                 = var.foundry_account_name
      protocols            = ["https"]
      subscriptionRequired = true
      subscriptionKeyParameterNames = {
        header = "api-key"
        query  = "subscription-key"
      }
    }
  }
}

resource "azapi_resource" "portal_operation" {
  for_each = local.methods

  type      = "Microsoft.ApiManagement/service/apis/operations@2024-05-01"
  name      = "${lower(each.value)}-default"
  parent_id = azapi_resource.portal_api.id

  body = {
    properties = {
      displayName = each.value
      method      = each.value
      urlTemplate = "/*"
    }
  }
}

resource "azapi_resource" "portal_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.portal_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.portal_backend_policy
    }
  }

  depends_on = [
    azapi_resource.portal_operation,
    azapi_resource.backend,
  ]
}

resource "azapi_resource" "direct_api" {
  type                      = "Microsoft.ApiManagement/service/apis@2025-03-01-preview"
  name                      = local.direct_api_id
  parent_id                 = var.apim_id
  schema_validation_enabled = false

  body = {
    properties = {
      apiRevision          = "1"
      backendId            = azapi_resource.backend.name
      description          = "Foundry Responses model API used by the hosted agent."
      displayName          = "${var.foundry_project_name} - Hosted agent AI model"
      path                 = local.direct_api_path
      protocols            = ["https"]
      subscriptionRequired = false
    }
  }
}

resource "azapi_resource" "ai_model_tag" {
  type      = "Microsoft.ApiManagement/service/tags@2024-05-01"
  name      = "aimodel"
  parent_id = var.apim_id

  body = {
    properties = {
      displayName = "aimodel"
    }
  }
}

resource "azapi_resource" "direct_api_tag" {
  type      = "Microsoft.ApiManagement/service/apis/tags@2024-05-01"
  name      = azapi_resource.ai_model_tag.name
  parent_id = azapi_resource.direct_api.id
  body      = {}
}

resource "azapi_resource" "responses_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2024-05-01"
  name      = "createResponses"
  parent_id = azapi_resource.direct_api.id

  body = {
    properties = {
      description = "Creates a model response through the project-compatible direct hosted-agent route."
      displayName = "Create response"
      method      = "POST"
      urlTemplate = "/api/projects/${var.foundry_project_name}/openai/v1/responses"
    }
  }
}

resource "azapi_resource" "user_level_policy_fragment" {
  type      = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  name      = "foundry-model-user-level"
  parent_id = var.apim_id

  body = {
    properties = {
      description = "Per-user model token limit for direct hosted-agent Responses calls."
      format      = "rawxml"
      value       = local.rendered_user_level_policy
    }
  }
}

resource "azapi_resource" "direct_api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.direct_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.direct_responses_policy
    }
  }

  depends_on = [
    azapi_resource.responses_operation,
    azapi_resource.user_level_policy_fragment,
  ]
}

resource "azapi_resource" "product" {
  type      = "Microsoft.ApiManagement/service/products@2024-05-01"
  name      = local.product_name
  parent_id = var.apim_id

  body = {
    properties = {
      displayName          = local.product_name
      state                = "published"
      subscriptionRequired = true
      approvalRequired     = false
    }
  }
}

resource "azurerm_api_management_product_api" "product_api" {
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  product_id          = azapi_resource.product.name
  api_name            = azapi_resource.portal_api.name
}

resource "azapi_resource" "product_subscription" {
  type      = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  name      = local.product_name
  parent_id = var.apim_id

  body = {
    properties = {
      allowTracing = false
      displayName  = local.product_name
      scope        = azapi_resource.product.id
      state        = "active"
    }
  }

  depends_on = [azurerm_api_management_product_api.product_api]
}

output "portal_project_endpoint" {
  value = "https://${var.apim_name}.azure-api.net/${var.foundry_account_name}/api/projects/${var.foundry_project_name}"
}

output "model_deployment_name" {
  value = var.model_deployment_name
}

output "direct_project_endpoint" {
  value = "https://${var.apim_name}.azure-api.net/${local.direct_api_path}/api/projects/${var.foundry_project_name}"
}

output "product_id" {
  value = azapi_resource.product.id
}

output "product_name" {
  value = azapi_resource.product.name
}

output "product_subscription_name" {
  value = azapi_resource.product_subscription.name
}

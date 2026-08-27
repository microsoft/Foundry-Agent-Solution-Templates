terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  api_name          = "foundry-hosted-agent"
  route             = "agent"
  protocol_base_url = "https://${var.foundry_account_name}.services.ai.azure.com/api/projects/${var.foundry_project_name}/agents/${var.foundry_agent_name}/endpoint/protocols/openai"
  rendered_ingress_policy = replace(
    var.ingress_policy,
    "__TENANT_ID__",
    var.tenant_id
  )
}

resource "azapi_resource" "api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = local.api_name
  parent_id = var.apim_id

  body = {
    properties = {
      description          = "Authenticated APIM entry point for the Microsoft Foundry hosted agent."
      displayName          = "${var.foundry_project_name} - Hosted Agent Ingress"
      apiRevision          = "1"
      path                 = local.route
      protocols            = ["https"]
      serviceUrl           = local.protocol_base_url
      subscriptionRequired = false
    }
  }
}

resource "azapi_resource" "responses_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2024-05-01"
  name      = "create-response"
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      description = "Create a response with the configured Microsoft Foundry hosted agent."
      displayName = "Create response"
      method      = "POST"
      urlTemplate = "/responses"
    }
  }
}

resource "azapi_resource" "policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.rendered_ingress_policy
    }
  }

  depends_on = [azapi_resource.responses_operation]
}

resource "azapi_resource" "responses_content_safety_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.responses_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = var.content_safety_policy
    }
  }

  depends_on = [azapi_resource.policy]
}

output "gateway_url" {
  value = "https://${var.apim_name}.azure-api.net/${local.route}/responses"
}

resource "azapi_resource" "apim" {
  type      = "Microsoft.ApiManagement/service@2024-05-01"
  name      = local.effective_apim_name
  parent_id = data.azurerm_resource_group.current.id
  location  = var.location

  body = {
    identity = {
      type = "SystemAssigned"
    }
    sku = {
      name     = var.apim_sku_name
      capacity = 1
    }
    properties = {
      publisherEmail = var.publisher_email
      publisherName  = var.publisher_name
      customProperties = {
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2"           = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30" = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10" = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11" = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168"    = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30"         = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10"         = "False"
        "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11"         = "False"
      }
      developerPortalStatus = "Disabled"
      legacyPortalStatus    = "Disabled"
      natGatewayState       = "Enabled"
      publicNetworkAccess   = "Enabled"
      virtualNetworkType    = "None"
    }
  }

  response_export_values = ["identity.principalId"]
}

resource "azapi_resource" "policy_named_value" {
  for_each = local.policy_named_values

  type      = "Microsoft.ApiManagement/service/namedValues@2024-05-01"
  name      = each.key
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      displayName = each.key
      secret      = false
      value       = each.value
    }
  }
}

resource "azapi_resource" "agent_principal_named_value" {
  type      = "Microsoft.ApiManagement/service/namedValues@2024-05-01"
  name      = "foundry-agent-principal-id"
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      displayName = "foundry-agent-principal-id"
      secret      = false
      value       = data.azapi_resource.foundry_project.output.identity.principalId
    }
  }
}

resource "azurerm_role_assignment" "apim_cognitive_services_user" {
  scope                            = local.foundry_account_id
  role_definition_id               = local.cognitive_services_user_role_definition_id
  principal_id                     = azapi_resource.apim.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "content_safety_backend" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "foundry-content-safety"
  parent_id                 = azapi_resource.apim.id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol = "http"
      url      = "https://${var.foundry_account_name}.cognitiveservices.azure.com"
      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

resource "azapi_resource" "tool_content_safety_policy_fragment" {
  type      = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  name      = "foundry-tool-content-safety"
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      description = "Shared inbound and outbound Content Safety policy for governed MCP tools."
      format      = "rawxml"
      value       = file("${local.policy_dir}/foundry-tool-content-safety-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.content_safety_backend,
    azapi_resource.policy_named_value,
  ]
}

resource "azapi_resource" "model_content_safety_policy_fragment" {
  type      = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  name      = "foundry-model-content-safety"
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      description = "Content Safety checks for Foundry Responses model requests."
      format      = "rawxml"
      value       = file("${local.policy_dir}/foundry-model-content-safety-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.content_safety_backend,
    azapi_resource.policy_named_value,
  ]
}

module "agent" {
  source = "./modules/apim-agent"

  apim_id               = azapi_resource.apim.id
  apim_name             = azapi_resource.apim.name
  foundry_account_name  = var.foundry_account_name
  foundry_project_name  = var.foundry_project_name
  foundry_agent_name    = var.foundry_agent_name
  tenant_id             = data.azurerm_client_config.current.tenant_id
  ingress_policy        = file("${local.policy_dir}/foundry-agent-ingress-policy.xml")
  content_safety_policy = file("${local.policy_dir}/foundry-agent-content-safety-policy.xml")

  depends_on = [
    azapi_resource.policy_named_value,
    azapi_resource.content_safety_backend,
    azurerm_role_assignment.apim_cognitive_services_user,
  ]
}

module "model" {
  source = "./modules/apim-model"

  apim_id               = azapi_resource.apim.id
  apim_name             = azapi_resource.apim.name
  resource_group_name   = var.resource_group_name
  foundry_account_id    = local.foundry_account_id
  foundry_account_name  = var.foundry_account_name
  foundry_project_id    = local.foundry_project_id
  foundry_project_name  = var.foundry_project_name
  model_deployment_name = var.model_deployment_name
  tenant_id             = data.azurerm_client_config.current.tenant_id
  gateway_policy        = file("${local.policy_dir}/foundry-model-gateway-policy.xml")
  user_level_policy     = file("${local.policy_dir}/foundry-model-user-level-policy.xml")

  depends_on = [
    azapi_resource.policy_named_value,
    azapi_resource.agent_principal_named_value,
    azapi_resource.content_safety_backend,
    azapi_resource.model_content_safety_policy_fragment,
    azurerm_role_assignment.apim_cognitive_services_user,
  ]
}

module "learn_tool" {
  source = "./modules/apim-tool-learn"

  apim_id              = azapi_resource.apim.id
  apim_name            = azapi_resource.apim.name
  foundry_project_name = var.foundry_project_name
  policy               = file("${local.policy_dir}/foundry-tool-learn-mcp-policy.xml")

  depends_on = [
    azapi_resource.policy_named_value,
    azapi_resource.tool_content_safety_policy_fragment,
    azurerm_role_assignment.apim_cognitive_services_user,
  ]
}

module "github_tool" {
  count  = local.github_enabled ? 1 : 0
  source = "./modules/apim-tool-github"

  apim_id              = azapi_resource.apim.id
  apim_name            = azapi_resource.apim.name
  foundry_project_name = var.foundry_project_name
  policy               = file("${local.policy_dir}/foundry-tool-github-mcp-policy.xml")

  depends_on = [
    azapi_resource.policy_named_value,
    azapi_resource.tool_content_safety_policy_fragment,
    azurerm_role_assignment.apim_cognitive_services_user,
  ]
}

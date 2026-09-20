resource "azurerm_role_assignment" "project_foundry_user" {
  scope                            = local.foundry_account_id
  role_definition_id               = local.foundry_user_role_definition_id
  principal_id                     = data.azapi_resource.foundry_project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "learn_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "mslearn"
  parent_id = local.foundry_project_id

  body = {
    properties = {
      target   = module.learn_tool.gateway_url
      authType = "None"
      category = "RemoteTool"
      metadata = {
        toolEntityId = "microsoft-learn"
        type         = "catalog_MCP"
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.project_foundry_user,
    module.learn_tool,
  ]
}

resource "azapi_resource" "github_connection" {
  count = local.github_enabled ? 1 : 0

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "github"
  parent_id                 = local.foundry_project_id
  schema_validation_enabled = false

  body = {
    properties = {
      target   = module.github_tool[0].gateway_url
      authType = "OAuth2"
      category = "RemoteTool"
      metadata = {
        oAuthProvider = "custom"
        type          = "custom_MCP"
      }
      authorizationUrl = "https://github.com/login/oauth/authorize"
      tokenUrl         = "https://github.com/login/oauth/access_token"
      refreshUrl       = "https://github.com/login/oauth/access_token"
      scopes           = ["offline_access", "repo", "read:user"]
    }
  }

  sensitive_body = {
    properties = {
      credentials = {
        clientId     = var.github_oauth_client_id
        clientSecret = var.github_oauth_client_secret
      }
    }
  }

  response_export_values = ["properties.redirectUrl"]

  depends_on = [
    azapi_resource.learn_connection,
    module.github_tool,
  ]
}

resource "azapi_resource" "google_connection" {
  count = local.google_enabled ? 1 : 0

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "google"
  parent_id                 = local.foundry_project_id
  schema_validation_enabled = false

  body = {
    properties = {
      target           = module.google_tool[0].gateway_url
      authType         = "OAuth2"
      category         = "RemoteTool"
      peRequirement    = "NotRequired"
      authorizationUrl = "https://accounts.google.com/o/oauth2/v2/auth"
      tokenUrl         = "https://oauth2.googleapis.com/token"
      refreshUrl       = "https://oauth2.googleapis.com/token"
      scopes = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
      ]
    }
  }

  sensitive_body = {
    properties = {
      credentials = {
        clientId     = var.google_oauth_client_id
        clientSecret = var.google_oauth_client_secret
      }
    }
  }

  response_export_values = ["properties.redirectUrl"]

  depends_on = [
    azapi_resource.learn_connection,
    module.google_tool,
  ]
}

resource "azapi_resource" "account_to_apim_link" {
  type                      = "Microsoft.Resources/links@2016-09-01"
  name                      = substr(sha256("${local.foundry_account_id}|${azapi_resource.apim.id}"), 0, 16)
  parent_id                 = local.foundry_account_id
  schema_validation_enabled = false

  body = {
    properties = {
      targetId = azapi_resource.apim.id
    }
  }
}

resource "azapi_resource" "apim_to_account_link" {
  type                      = "Microsoft.Resources/links@2016-09-01"
  name                      = substr(sha256("${azapi_resource.apim.id}|${local.foundry_account_id}"), 0, 16)
  parent_id                 = azapi_resource.apim.id
  schema_validation_enabled = false

  body = {
    properties = {
      targetId = local.foundry_account_id
    }
  }
}

resource "azapi_resource" "project_to_product_link" {
  type                      = "Microsoft.Resources/links@2016-09-01"
  name                      = substr(sha256("${local.foundry_project_id}|${module.model.product_id}"), 0, 16)
  parent_id                 = local.foundry_project_id
  schema_validation_enabled = false

  body = {
    properties = {
      targetId = module.model.product_id
    }
  }
}

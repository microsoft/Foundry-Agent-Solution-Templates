output "APIM_NAME" {
  value = azapi_resource.apim.name
}

output "APIM_RESOURCE_ID" {
  value = azapi_resource.apim.id
}

output "APIM_GATEWAY_URL" {
  value = local.apim_gateway_url
}

output "APIM_AGENT_GATEWAY_URL" {
  value = module.agent.gateway_url
}

output "APIM_FOUNDRY_PROJECT_ENDPOINT" {
  value = module.model.portal_project_endpoint
}

output "APIM_FOUNDRY_MODEL_DEPLOYMENT_NAME" {
  value = var.model_deployment_name
}

output "APIM_FOUNDRY_DIRECT_PROJECT_ENDPOINT" {
  value = module.model.direct_project_endpoint
}

output "APIM_FOUNDRY_PRODUCT_NAME" {
  value = module.model.product_name
}

output "APIM_FOUNDRY_SUBSCRIPTION_NAME" {
  value = module.model.product_subscription_name
}

output "MSLEARN_MCP_URL" {
  value = module.learn_tool.gateway_url
}

output "GITHUB_MCP_ENABLED" {
  value = local.github_enabled
}

output "GITHUB_MCP_URL" {
  value = local.github_enabled ? module.github_tool[0].gateway_url : ""
}

output "GITHUB_OAUTH_REDIRECT_URL" {
  value = local.github_enabled ? azapi_resource.github_connection[0].output.properties.redirectUrl : ""
}

locals {
  foundry_account_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.CognitiveServices/accounts/${var.foundry_account_name}"
  foundry_project_id = "${local.foundry_account_id}/projects/${var.foundry_project_name}"
  effective_apim_name = var.apim_name != "" ? var.apim_name : "apim-${substr(
    md5("${var.subscription_id}${data.azurerm_resource_group.current.id}"),
    0,
    13
  )}"
  apim_gateway_url = "https://${local.effective_apim_name}.azure-api.net"
  github_enabled = (
    var.github_oauth_client_id != "" &&
    nonsensitive(var.github_oauth_client_secret != "")
  )
  policy_dir = "${path.module}/policies"

  policy_named_values = {
    policy-user-tokens-per-minute               = tostring(var.model_user_tokens_per_minute)
    policy-user-token-quota-per-hour            = tostring(var.model_user_token_quota_per_hour)
    policy-agent-rate-limit-requests            = tostring(var.agent_calls_per_period)
    policy-agent-rate-limit-window-seconds      = tostring(var.agent_call_renewal_period_seconds)
    policy-tool-rate-limit-requests             = tostring(var.tool_calls_per_period)
    policy-tool-rate-limit-window-seconds       = tostring(var.tool_call_renewal_period_seconds)
    policy-github-blocked-users                 = var.github_blocked_user_names != "" ? var.github_blocked_user_names : "__none__"
    policy-github-blocked-tools                 = var.github_blocked_tool_names != "" ? var.github_blocked_tool_names : "__none__"
    policy-content-safety-hate-threshold        = tostring(var.content_safety_hate_threshold)
    policy-content-safety-self-harm-threshold   = tostring(var.content_safety_self_harm_threshold)
    policy-content-safety-sexual-threshold      = tostring(var.content_safety_sexual_threshold)
    policy-content-safety-violence-threshold    = tostring(var.content_safety_violence_threshold)
    policy-content-safety-prompt-shield-enabled = tostring(var.content_safety_prompt_shield_enabled)
  }

  cognitive_services_user_role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/a97b65f3-24c7-4388-baec-2e87135dc908"
  foundry_user_role_definition_id            = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
}

variable "subscription_id" {
  description = "Azure subscription that contains the deployment."
  type        = string
}

variable "resource_group_name" {
  description = "Existing azd resource group created by the Foundry layer."
  type        = string
}

variable "location" {
  description = "Azure region for API Management."
  type        = string
}

variable "apim_name" {
  description = "Globally unique API Management service name. A deterministic name is generated when empty."
  type        = string
  default     = ""
}

variable "apim_sku_name" {
  description = "API Management v2 SKU. Use StandardV2 or PremiumV2 for production."
  type        = string
  default     = "BasicV2"

  validation {
    condition     = contains(["BasicV2", "StandardV2", "PremiumV2"], var.apim_sku_name)
    error_message = "apim_sku_name must be BasicV2, StandardV2, or PremiumV2."
  }
}

variable "publisher_name" {
  description = "Organization name shown by API Management."
  type        = string
  default     = "Foundry AI Gateway"
}

variable "publisher_email" {
  description = "Administrator email used by API Management notifications."
  type        = string
}

variable "foundry_account_name" {
  description = "Microsoft Foundry account that owns the project."
  type        = string
}

variable "foundry_project_name" {
  description = "Microsoft Foundry project used by the governed routes."
  type        = string
}

variable "foundry_agent_name" {
  description = "Microsoft Foundry hosted-agent name exposed through APIM."
  type        = string
  default     = "agent"
}

variable "model_deployment_name" {
  description = "Foundry model deployment exposed through the model gateways."
  type        = string
}

variable "model_user_tokens_per_minute" {
  description = "Maximum prompt and completion tokens allowed per minute for each end user."
  type        = number
  default     = 100000

  validation {
    condition     = var.model_user_tokens_per_minute >= 1
    error_message = "model_user_tokens_per_minute must be at least 1."
  }
}

variable "model_user_token_quota_per_hour" {
  description = "Maximum prompt and completion tokens allowed per hour for each end user."
  type        = number
  default     = 6000000

  validation {
    condition     = var.model_user_token_quota_per_hour >= 1
    error_message = "model_user_token_quota_per_hour must be at least 1."
  }
}

variable "tool_calls_per_period" {
  description = "Maximum requests to governed tool routes during each renewal period."
  type        = number
  default     = 60

  validation {
    condition     = var.tool_calls_per_period >= 1
    error_message = "tool_calls_per_period must be at least 1."
  }
}

variable "tool_call_renewal_period_seconds" {
  description = "Governed tool-call rate-limit renewal period in seconds."
  type        = number
  default     = 60

  validation {
    condition     = var.tool_call_renewal_period_seconds >= 1 && var.tool_call_renewal_period_seconds <= 300
    error_message = "tool_call_renewal_period_seconds must be between 1 and 300."
  }
}

variable "agent_calls_per_period" {
  description = "Maximum hosted-agent calls allowed per source IP during each renewal period."
  type        = number
  default     = 60

  validation {
    condition     = var.agent_calls_per_period >= 1
    error_message = "agent_calls_per_period must be at least 1."
  }
}

variable "agent_call_renewal_period_seconds" {
  description = "Hosted-agent rate-limit renewal period in seconds."
  type        = number
  default     = 60

  validation {
    condition     = var.agent_call_renewal_period_seconds >= 1 && var.agent_call_renewal_period_seconds <= 300
    error_message = "agent_call_renewal_period_seconds must be between 1 and 300."
  }
}

variable "github_oauth_client_id" {
  description = "Optional GitHub OAuth App client ID."
  type        = string
  default     = ""
}

variable "github_oauth_client_secret" {
  description = "Optional GitHub OAuth App client secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_blocked_user_names" {
  description = "Optional comma-separated GitHub user names denied access to the GitHub MCP route."
  type        = string
  default     = ""
}

variable "github_blocked_tool_names" {
  description = "Optional comma-separated GitHub MCP tool names denied by APIM."
  type        = string
  default     = ""
}

variable "content_safety_hate_threshold" {
  type    = number
  default = 7

  validation {
    condition     = var.content_safety_hate_threshold >= 0 && var.content_safety_hate_threshold <= 7
    error_message = "content_safety_hate_threshold must be between 0 and 7."
  }
}

variable "content_safety_self_harm_threshold" {
  type    = number
  default = 7

  validation {
    condition     = var.content_safety_self_harm_threshold >= 0 && var.content_safety_self_harm_threshold <= 7
    error_message = "content_safety_self_harm_threshold must be between 0 and 7."
  }
}

variable "content_safety_sexual_threshold" {
  type    = number
  default = 7

  validation {
    condition     = var.content_safety_sexual_threshold >= 0 && var.content_safety_sexual_threshold <= 7
    error_message = "content_safety_sexual_threshold must be between 0 and 7."
  }
}

variable "content_safety_violence_threshold" {
  type    = number
  default = 7

  validation {
    condition     = var.content_safety_violence_threshold >= 0 && var.content_safety_violence_threshold <= 7
    error_message = "content_safety_violence_threshold must be between 0 and 7."
  }
}

variable "content_safety_prompt_shield_enabled" {
  type    = bool
  default = true
}

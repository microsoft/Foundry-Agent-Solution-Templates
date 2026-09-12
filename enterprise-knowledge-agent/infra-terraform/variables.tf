variable "subscriptionId" {
  description = "Azure subscription containing the Foundry and Search resources."
  type        = string
}

variable "resourceGroupName" {
  description = "Existing resource group created by the Foundry infrastructure layer."
  type        = string
}

variable "principalId" {
  description = "Object ID of the user or workload identity provisioning Search data."
  type        = string
}

variable "searchMode" {
  description = "demo creates a template-owned Search service; byo uses an existing service."
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["demo", "byo"], var.searchMode)
    error_message = "searchMode must be demo or byo."
  }
}

variable "searchServiceName" {
  description = "Optional Search service name. A deterministic name is generated when empty."
  type        = string
  default     = ""
}

variable "searchLocation" {
  description = "Azure region for the demo Search service."
  type        = string
  default     = "westus2"
}

variable "searchSku" {
  description = "SKU for the demo Search service."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "standard"], var.searchSku)
    error_message = "searchSku must be basic or standard."
  }
}

variable "existingSearchEndpoint" {
  description = "Existing Search endpoint required in byo mode."
  type        = string
  default     = ""
}

variable "existingSearchServiceId" {
  description = "Existing Search ARM resource ID required in byo mode."
  type        = string
  default     = ""
}

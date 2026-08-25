variable "environmentName" {
  description = "Collision-safe azd environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])$", var.environmentName))
    error_message = "environmentName must be 3-32 lowercase alphanumeric or hyphen characters and cannot start or end with a hyphen."
  }
}

variable "location" {
  description = "Foundry, VNet, and Key Vault location."
  type        = string
  default     = "westus3"

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "searchLocation" {
  description = "Search location, independently configurable from the Foundry region."
  type        = string
  default     = "westus3"

  validation {
    condition     = length(trimspace(var.searchLocation)) > 0
    error_message = "searchLocation must not be empty."
  }
}

variable "deploymentPrincipalObjectId" {
  description = "Object ID of the operator or CI identity used for deployment and Search bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deploymentPrincipalObjectId))
    error_message = "deploymentPrincipalObjectId must be a UUID."
  }
}

variable "invocationTestPrincipalObjectId" {
  description = "Optional invoke-only validation principal."
  type        = string
  default     = ""

  validation {
    condition     = var.invocationTestPrincipalObjectId == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.invocationTestPrincipalObjectId))
    error_message = "invocationTestPrincipalObjectId must be empty or a UUID."
  }
}

variable "connectivityMode" {
  type    = string
  default = "pointToSite"

  validation {
    condition     = contains(["pointToSite", "siteToSite", "vnetPeering"], var.connectivityMode)
    error_message = "connectivityMode must be pointToSite, siteToSite, or vnetPeering."
  }
}

variable "vnetAddressPrefix" {
  type    = string
  default = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnetAddressPrefix, 0))
    error_message = "vnetAddressPrefix must be a valid CIDR prefix."
  }
}

variable "agentSubnetPrefix" {
  type    = string
  default = "10.42.0.0/24"

  validation {
    condition     = can(cidrhost(var.agentSubnetPrefix, 0))
    error_message = "agentSubnetPrefix must be a valid CIDR prefix."
  }
}

variable "privateEndpointSubnetPrefix" {
  type    = string
  default = "10.42.1.0/24"

  validation {
    condition     = can(cidrhost(var.privateEndpointSubnetPrefix, 0))
    error_message = "privateEndpointSubnetPrefix must be a valid CIDR prefix."
  }
}

variable "firewallSubnetPrefix" {
  type    = string
  default = "10.42.2.0/26"

  validation {
    condition     = can(cidrhost(var.firewallSubnetPrefix, 0))
    error_message = "firewallSubnetPrefix must be a valid CIDR prefix."
  }
}

variable "firewallCreationRequired" {
  description = "Internal orchestration flag set after a read-only Firewall existence check."
  type        = bool
  default     = true
}

variable "gatewaySubnetPrefix" {
  type    = string
  default = "10.42.3.0/27"

  validation {
    condition     = can(cidrhost(var.gatewaySubnetPrefix, 0))
    error_message = "gatewaySubnetPrefix must be a valid CIDR prefix."
  }
}

variable "dnsInboundSubnetPrefix" {
  type    = string
  default = "10.42.4.0/28"

  validation {
    condition     = can(cidrhost(var.dnsInboundSubnetPrefix, 0))
    error_message = "dnsInboundSubnetPrefix must be a valid CIDR prefix."
  }
}

variable "dnsInboundIpAddress" {
  type    = string
  default = "10.42.4.4"

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.dnsInboundIpAddress))
    error_message = "dnsInboundIpAddress must be an IPv4 address."
  }
}

variable "p2sAddressPool" {
  type    = string
  default = "172.20.0.0/24"

  validation {
    condition     = can(cidrhost(var.p2sAddressPool, 0))
    error_message = "p2sAddressPool must be a valid CIDR prefix."
  }
}

variable "p2sTenantId" {
  description = "P2S Microsoft Entra tenant. Empty selects the current provider tenant."
  type        = string
  default     = ""

  validation {
    condition     = var.p2sTenantId == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.p2sTenantId))
    error_message = "p2sTenantId must be empty or a UUID."
  }
}

variable "s2sGatewayIpAddress" {
  type    = string
  default = ""
}

variable "s2sRemoteAddressPrefixes" {
  type    = list(string)
  default = []

  validation {
    condition     = alltrue([for prefix in var.s2sRemoteAddressPrefixes : can(cidrhost(prefix, 0))])
    error_message = "Every s2sRemoteAddressPrefixes item must be a valid CIDR prefix."
  }
}

variable "s2sEnableBgp" {
  type    = bool
  default = false
}

variable "s2sRemoteAsn" {
  type    = number
  default = 65010

  validation {
    condition     = floor(var.s2sRemoteAsn) == var.s2sRemoteAsn
    error_message = "s2sRemoteAsn must be an integer."
  }
}

variable "s2sBgpPeeringAddress" {
  type    = string
  default = ""
}

variable "s2sSharedKey" {
  type      = string
  default   = ""
  sensitive = true
}

variable "remoteVnetResourceId" {
  type    = string
  default = ""

  validation {
    condition     = var.remoteVnetResourceId == "" || can(regex("(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.remoteVnetResourceId))
    error_message = "remoteVnetResourceId must be empty or a canonical virtual network ARM resource ID."
  }
}

variable "modelName" {
  type    = string
  default = "gpt-5.1"

  validation {
    condition     = var.modelName == "gpt-5.1"
    error_message = "modelName must be gpt-5.1."
  }
}

variable "modelVersion" {
  type    = string
  default = "2025-11-13"

  validation {
    condition     = var.modelVersion == "2025-11-13"
    error_message = "modelVersion must be 2025-11-13."
  }
}

variable "modelCapacity" {
  type    = number
  default = 10

  validation {
    condition     = floor(var.modelCapacity) == var.modelCapacity && var.modelCapacity >= 1 && var.modelCapacity <= 300
    error_message = "modelCapacity must be an integer between 1 and 300."
  }
}

variable "containerRegistryResourceId" {
  description = "Optional full ARM resource ID of an enterprise-owned Azure Container Registry."
  type        = string
  default     = ""

  validation {
    condition     = var.containerRegistryResourceId == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerRegistry/registries/[^/]+$", var.containerRegistryResourceId))
    error_message = "containerRegistryResourceId must be empty or a canonical Azure Container Registry ARM resource ID."
  }
}

variable "containerRegistryEndpoint" {
  description = "Optional exact login server of the enterprise-owned Azure Container Registry."
  type        = string
  default     = ""

  validation {
    condition     = var.containerRegistryEndpoint == "" || can(regex("^[a-z0-9-]+\\.azurecr\\.io$", var.containerRegistryEndpoint))
    error_message = "containerRegistryEndpoint must be empty or a lowercase AzureCloud ACR login server without a scheme or path."
  }
}

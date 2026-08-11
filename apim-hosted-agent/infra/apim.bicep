targetScope = 'resourceGroup'

@description('Globally unique API Management service name.')
param apimName string = ''

@description('Azure region for API Management.')
param location string = resourceGroup().location

@allowed([
  'BasicV2'
  'StandardV2'
  'PremiumV2'
])
@description('API Management v2 SKU. Use StandardV2 or PremiumV2 for production.')
param apimSkuName string = 'BasicV2'

@description('Organization name shown by API Management.')
param publisherName string = 'Foundry AI Gateway'

@description('Administrator email used by API Management notifications.')
param publisherEmail string

@description('APIM API ID used by the associated model gateway.')
param modelApiId string

@description('Microsoft Foundry project name used in the governed tool route.')
param foundryProjectName string

@description('Microsoft Foundry hosted agent exposed through the APIM ingress route.')
param foundryAgentName string = 'agent'

@description('Foundry model deployment name used by the project token policy.')
param modelDeploymentName string

@minValue(1)
@description('Maximum prompt and completion tokens allowed per minute for the project deployment.')
param modelTokenLimit int = 1000000

@minValue(1)
@description('Maximum prompt and completion tokens allowed in the project quota period.')
param modelTokenQuota int = 100000

@allowed([
  'Hourly'
  'Daily'
  'Weekly'
  'Monthly'
  'Yearly'
])
@description('Fixed period used by the project token quota.')
param modelTokenQuotaPeriod string = 'Hourly'

@minValue(1)
@description('Maximum requests to Portal-generated governed tool routes during each renewal period.')
param toolCallsPerPeriod int = 60

@minValue(1)
@maxValue(300)
@description('Governed tool-call rate-limit renewal period in seconds.')
param toolCallRenewalPeriodSeconds int = 60

@minValue(1)
@description('Maximum hosted-agent calls allowed per source IP during each renewal period.')
param agentCallsPerPeriod int = 60

@minValue(1)
@maxValue(300)
@description('Hosted-agent rate-limit renewal period in seconds.')
param agentCallRenewalPeriodSeconds int = 60

var cognitiveServicesUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'a97b65f3-24c7-4388-baec-2e87135dc908'
)
var effectiveApimName = empty(apimName)
  ? 'apim-${uniqueString(subscription().id, resourceGroup().id)}'
  : apimName
var foundryProductName = take('${toLower(modelApiId)}-${toLower(foundryProjectName)}-ai-${uniqueString(resourceGroup().id, modelApiId, foundryProjectName)}', 80)
var keylessModelApiId = '${toLower(modelApiId)}-keyless'
var keylessModelApiPath = '${toLower(modelApiId)}-keyless'
var foundryApiMethods = [
  'DELETE'
  'GET'
  'HEAD'
  'OPTIONS'
  'PATCH'
  'POST'
  'PUT'
  'TRACE'
]
var mcpToolRoute = 'tool-${toLower(foundryProjectName)}-mcp'
var mcpGatewayUrl = 'https://${effectiveApimName}.azure-api.net/${mcpToolRoute}'
var hostedAgentApiName = 'foundry-hosted-agent'
var hostedAgentRoute = 'agent'
var hostedAgentProtocolBaseUrl = 'https://${foundryAccount.name}.services.ai.azure.com/api/projects/${foundryProjectName}/agents/${foundryAgentName}/endpoint/protocols/openai'
var apimPolicyNamedValueDefinitions = [
  {
    name: 'foundry-backend-id'
    value: modelApiId
  }
  {
    name: 'foundry-model-deployment-name'
    value: modelDeploymentName
  }
  {
    name: 'foundry-model-token-limit'
    value: string(modelTokenLimit)
  }
  {
    name: 'foundry-model-token-quota'
    value: string(modelTokenQuota)
  }
  {
    name: 'foundry-model-token-quota-period'
    value: modelTokenQuotaPeriod
  }
  {
    name: 'foundry-project-name'
    value: foundryProjectName
  }
  {
    name: 'foundry-tenant-id'
    value: tenant().tenantId
  }
  {
    name: 'foundry-agent-calls-per-period'
    value: string(agentCallsPerPeriod)
  }
  {
    name: 'foundry-agent-call-renewal-period-seconds'
    value: string(agentCallRenewalPeriodSeconds)
  }
  {
    name: 'foundry-tool-calls-per-period'
    value: string(toolCallsPerPeriod)
  }
  {
    name: 'foundry-tool-call-renewal-period-seconds'
    value: string(toolCallRenewalPeriodSeconds)
  }
]

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: effectiveApimName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: apimSkuName
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
    }
    developerPortalStatus: 'Disabled'
    legacyPortalStatus: 'Disabled'
    natGatewayState: 'Enabled'
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
  }
}

resource apimPolicyNamedValues 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for definition in apimPolicyNamedValueDefinitions: {
  parent: apim
  name: definition.name
  properties: {
    displayName: definition.name
    secret: false
    value: definition.value
  }
}]

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: modelApiId
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource agentPrincipalNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'foundry-agent-principal-id'
  properties: {
    displayName: 'foundry-agent-principal-id'
    secret: false
    value: foundryProject.identity.principalId
  }
}

resource apimCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, apim.id, cognitiveServicesUserRoleDefinitionId)
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cognitiveServicesUserRoleDefinitionId
  }
}

resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: modelApiId
  properties: {
    protocol: 'http'
    url: 'https://${foundryAccount.name}.services.ai.azure.com/'
    credentials: {
      managedIdentity: {
        resource: 'https://ai.azure.com/'
      }
    }
    tls: {
      validateCertificateChain: false
      validateCertificateName: false
    }
  }
}

resource foundryModelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: modelApiId
  properties: {
    displayName: modelApiId
    apiRevision: '1'
    description: 'Portal-compatible model API retained for the Foundry project association; the hosted agent does not use this route.'
    path: modelApiId
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

resource foundryModelOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for method in foundryApiMethods: {
  parent: foundryModelApi
  name: '${toLower(method)}-default'
  properties: {
    displayName: method
    method: method
    urlTemplate: '/*'
  }
}]

resource keylessModelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: keylessModelApiId
  properties: {
    apiRevision: '1'
    description: 'Passwordless model gateway restricted to the hosted-agent managed identity.'
    displayName: '${modelApiId} passwordless'
    path: keylessModelApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource keylessModelOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for method in foundryApiMethods: {
  parent: keylessModelApi
  name: '${toLower(method)}-default'
  properties: {
    displayName: method
    method: method
    urlTemplate: '/*'
  }
}]

resource keylessModelApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: keylessModelApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/foundry-model-gateway-keyless.xml')
  }
  dependsOn: [
    apimPolicyNamedValues
    agentPrincipalNamedValue
  ]
}

resource foundryProjectProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: foundryProductName
  properties: {
    displayName: foundryProductName
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource foundryProjectProductApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: foundryProjectProduct
  name: foundryModelApi.name
}

resource foundryAccountApimLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryAccount
  name: uniqueString(foundryAccount.id, apim.id, 'account-apim')
  properties: {
    targetId: apim.id
  }
}

resource apimFoundryAccountLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: apim
  name: uniqueString(apim.id, foundryAccount.id, 'apim-account')
  properties: {
    targetId: foundryAccount.id
  }
}

resource foundryProjectProductLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryProject
  name: uniqueString(foundryProject.id, foundryProjectProduct.id, 'project-product')
  properties: {
    targetId: foundryProjectProduct.id
  }
}

resource hostedAgentApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: hostedAgentApiName
  properties: {
    description: 'Authenticated APIM entry point for the Microsoft Foundry hosted agent.'
    displayName: 'Microsoft Foundry hosted agent'
    apiRevision: '1'
    path: hostedAgentRoute
    protocols: [
      'https'
    ]
    serviceUrl: hostedAgentProtocolBaseUrl
    subscriptionRequired: false
  }
}

resource hostedAgentResponsesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: hostedAgentApi
  name: 'create-response'
  properties: {
    description: 'Create a response with the configured Microsoft Foundry hosted agent.'
    displayName: 'Create response'
    method: 'POST'
    urlTemplate: '/responses'
  }
}

resource hostedAgentApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: hostedAgentApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/foundry-hosted-agent-ingress.xml')
  }
  dependsOn: [
    apimPolicyNamedValues
    hostedAgentResponsesOperation
  ]
}

resource mcpBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'mcp'
  properties: {
    protocol: 'http'
    url: 'https://learn.microsoft.com/api/mcp'
  }
}

resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'foundry-content-safety'
  properties: {
    protocol: 'http'
    url: 'https://${foundryAccount.name}.cognitiveservices.azure.com'
    credentials: {
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  parent: apim
  name: mcpToolRoute
  properties: {
    displayName: mcpToolRoute
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: 'https://learn.microsoft.com/api/mcp'
    backendId: mcpBackend.name
    path: mcpToolRoute
    protocols: [
      'https'
    ]
    type: 'mcp'
    mcpProperties: {
      endpoints: {
        mcp: {
          uriTemplate: '/mcp'
        }
      }
      isFederationRouter: false
    }
  }
}

resource mcpApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-10-01-preview' = {
  parent: mcpApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/foundry-governed-tool.xml')
  }
  dependsOn: [
    apimPolicyNamedValues
    contentSafetyBackend
  ]
}

output APIM_NAME string = apim.name
output APIM_RESOURCE_ID string = apim.id
output APIM_GATEWAY_URL string = 'https://${apim.name}.azure-api.net'
output APIM_AGENT_GATEWAY_URL string = 'https://${apim.name}.azure-api.net/${hostedAgentRoute}/responses'
output APIM_FOUNDRY_PROJECT_ENDPOINT string = 'https://${apim.name}.azure-api.net/${modelApiId}/api/projects/${foundryProjectName}'
output APIM_KEYLESS_API_ID string = keylessModelApi.name
output APIM_KEYLESS_FOUNDRY_PROJECT_ENDPOINT string = 'https://${apim.name}.azure-api.net/${keylessModelApiPath}/api/projects/${foundryProjectName}'
output APIM_FOUNDRY_PRODUCT_NAME string = foundryProjectProduct.name
output MCP_URL string = mcpGatewayUrl

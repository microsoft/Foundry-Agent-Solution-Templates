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

@description('Foundry model deployment exposed through the model gateways.')
param modelDeploymentName string

@minValue(1)
@description('Maximum prompt and completion tokens allowed per minute for each end user.')
param modelUserTokenLimit int = 1000000

@minValue(1)
@description('Maximum prompt and completion tokens allowed for each end user in the quota period.')
param modelUserTokenQuota int = 10000000

@allowed([
  'Hourly'
  'Daily'
  'Weekly'
  'Monthly'
  'Yearly'
])
@description('Fixed period used by the per-user model token quota.')
param modelUserTokenQuotaPeriod string = 'Hourly'

@minValue(1)
@description('Maximum requests to governed tool routes during each renewal period.')
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

@description('Optional GitHub OAuth App client ID. GitHub APIM resources are created only when both OAuth values are set.')
param githubOAuthClientId string = ''

@secure()
@description('Optional GitHub OAuth App client secret. GitHub APIM resources are created only when both OAuth values are set.')
param githubOAuthClientSecret string = ''

@description('Optional comma-separated GitHub user names denied access to the GitHub MCP route. Matching is case-insensitive.')
param githubBlockedUserNames string = ''

@description('Optional comma-separated GitHub MCP tool names denied by APIM. Matching is case-insensitive.')
param githubBlockedToolNames string = ''

@minValue(0)
@maxValue(7)
param contentSafetyHateThreshold int = 4
@minValue(0)
@maxValue(7)
param contentSafetySelfHarmThreshold int = 4
@minValue(0)
@maxValue(7)
param contentSafetySexualThreshold int = 4
@minValue(0)
@maxValue(7)
param contentSafetyViolenceThreshold int = 4
param contentSafetyPromptShieldEnabled bool = true

var cognitiveServicesUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'a97b65f3-24c7-4388-baec-2e87135dc908'
)
var effectiveApimName = empty(apimName)
  ? 'apim-${uniqueString(subscription().id, resourceGroup().id)}'
  : apimName
var githubEnabled = !empty(githubOAuthClientId) && !empty(githubOAuthClientSecret)
var githubMcpGatewayUrl = 'https://${effectiveApimName}.azure-api.net/tool-${toLower(foundryProjectName)}-github-mcp'
var effectiveGithubBlockedUserNames = empty(githubBlockedUserNames) ? '__none__' : githubBlockedUserNames
var effectiveGithubBlockedToolNames = empty(githubBlockedToolNames) ? '__none__' : githubBlockedToolNames
var policyNamedValues = [
  {
    name: 'policy-user-token-limit-per-minute'
    value: string(modelUserTokenLimit)
  }
  {
    name: 'policy-user-token-quota'
    value: string(modelUserTokenQuota)
  }
  {
    name: 'policy-user-token-quota-period'
    value: modelUserTokenQuotaPeriod
  }
  {
    name: 'policy-agent-rate-limit-requests'
    value: string(agentCallsPerPeriod)
  }
  {
    name: 'policy-agent-rate-limit-window-seconds'
    value: string(agentCallRenewalPeriodSeconds)
  }
  {
    name: 'policy-tool-rate-limit-requests'
    value: string(toolCallsPerPeriod)
  }
  {
    name: 'policy-tool-rate-limit-window-seconds'
    value: string(toolCallRenewalPeriodSeconds)
  }
  {
    name: 'policy-github-blocked-users'
    value: effectiveGithubBlockedUserNames
  }
  {
    name: 'policy-github-blocked-tools'
    value: effectiveGithubBlockedToolNames
  }
  { name: 'policy-content-safety-hate-threshold', value: string(contentSafetyHateThreshold) }
  { name: 'policy-content-safety-self-harm-threshold', value: string(contentSafetySelfHarmThreshold) }
  { name: 'policy-content-safety-sexual-threshold', value: string(contentSafetySexualThreshold) }
  { name: 'policy-content-safety-violence-threshold', value: string(contentSafetyViolenceThreshold) }
  { name: 'policy-content-safety-prompt-shield-enabled', value: string(contentSafetyPromptShieldEnabled) }
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

resource policyNamedValueResources 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for definition in policyNamedValues: {
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

resource toolContentSafetyPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'foundry-tool-content-safety'
  properties: {
    description: 'Shared inbound and outbound Content Safety policy for governed MCP tools.'
    format: 'rawxml'
    value: loadTextContent('policies/foundry-tool-content-safety-policy.xml')
  }
  dependsOn: [
    contentSafetyBackend
  ]
}

module agent 'modules/apim-agent.bicep' = {
  name: 'agent'
  params: {
    apimName: apim.name
    foundryAccountName: modelApiId
    foundryProjectName: foundryProjectName
    foundryAgentName: foundryAgentName
    tenantId: tenant().tenantId
  }
  dependsOn: [
    policyNamedValueResources
    contentSafetyBackend
    apimCognitiveServicesUser
  ]
}

module model 'modules/apim-model.bicep' = {
  name: 'model'
  params: {
    apimName: apim.name
    foundryAccountName: modelApiId
    foundryProjectName: foundryProjectName
    modelDeploymentName: modelDeploymentName
    tenantId: tenant().tenantId
  }
  dependsOn: [
    policyNamedValueResources
    agentPrincipalNamedValue
    contentSafetyBackend
    apimCognitiveServicesUser
  ]
}

module learnTool 'modules/apim-tool-learn.bicep' = {
  name: 'tool-learn'
  params: {
    apimName: apim.name
    foundryProjectName: foundryProjectName
  }
  dependsOn: [
    policyNamedValueResources
    toolContentSafetyPolicyFragment
    apimCognitiveServicesUser
  ]
}

module githubTool 'modules/apim-tool-github.bicep' = if (githubEnabled) {
  name: 'tool-github'
  params: {
    apimName: apim.name
    foundryProjectName: foundryProjectName
  }
  dependsOn: [
    policyNamedValueResources
    toolContentSafetyPolicyFragment
    apimCognitiveServicesUser
  ]
}

output APIM_NAME string = apim.name
output APIM_RESOURCE_ID string = apim.id
output APIM_GATEWAY_URL string = 'https://${apim.name}.azure-api.net'
output APIM_AGENT_GATEWAY_URL string = agent.outputs.gatewayUrl
output APIM_FOUNDRY_PROJECT_ENDPOINT string = model.outputs.portalProjectEndpoint
output APIM_FOUNDRY_ADMIN_CONNECTION_NAME string = model.outputs.adminConnectionName
output APIM_FOUNDRY_ADMIN_CONNECTION_MODEL string = model.outputs.adminConnectionModel
output APIM_FOUNDRY_ADMIN_MODEL_DEPLOYMENT_NAME string = model.outputs.adminModelDeploymentName
output APIM_FOUNDRY_ADMIN_MODEL_API_URL string = model.outputs.adminModelApiUrl
output APIM_FOUNDRY_DIRECT_PROJECT_ENDPOINT string = model.outputs.directProjectEndpoint
output APIM_FOUNDRY_PRODUCT_NAME string = model.outputs.productName
output APIM_FOUNDRY_SUBSCRIPTION_NAME string = model.outputs.productSubscriptionName
output MCP_URL string = learnTool.outputs.gatewayUrl
output GITHUB_MCP_ENABLED bool = githubEnabled
output GITHUB_MCP_URL string = githubEnabled ? githubMcpGatewayUrl : ''

targetScope = 'resourceGroup'

@description('Existing API Management service name.')
param apimName string

@description('Microsoft Foundry account name that hosts the agent.')
param foundryAccountName string

@description('Microsoft Foundry project name that hosts the agent.')
param foundryProjectName string

@description('Microsoft Foundry hosted-agent name exposed through APIM.')
param foundryAgentName string
param tenantId string

var apiName = 'foundry-hosted-agent'
var route = 'agent'
var protocolBaseUrl = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${foundryProjectName}/agents/${foundryAgentName}/endpoint/protocols/openai'
var ingressPolicy = replace(loadTextContent('../policies/foundry-agent-ingress-policy.xml'), '__TENANT_ID__', tenantId)

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    description: 'Authenticated APIM entry point for the Microsoft Foundry hosted agent.'
    displayName: '${foundryProjectName} - Hosted Agent Ingress'
    apiRevision: '1'
    path: route
    protocols: [
      'https'
    ]
    serviceUrl: protocolBaseUrl
    subscriptionRequired: false
  }
}

resource responsesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'create-response'
  properties: {
    description: 'Create a response with the configured Microsoft Foundry hosted agent.'
    displayName: 'Create response'
    method: 'POST'
    urlTemplate: '/responses'
  }
}

resource policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: ingressPolicy
  }
  dependsOn: [
    responsesOperation
  ]
}

resource responsesContentSafetyPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: responsesOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/foundry-agent-content-safety-policy.xml')
  }
  dependsOn: [
    policy
  ]
}

output gatewayUrl string = 'https://${apim.name}.azure-api.net/${route}/responses'

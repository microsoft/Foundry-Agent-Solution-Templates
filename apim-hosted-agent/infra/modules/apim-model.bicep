targetScope = 'resourceGroup'

@description('Existing API Management service name.')
param apimName string

@description('Microsoft Foundry account name and portal-compatible model API ID.')
param foundryAccountName string

@description('Microsoft Foundry project name.')
param foundryProjectName string

@description('Foundry model deployment exposed through the model gateways.')
param modelDeploymentName string
param tenantId string

var methods = [
  'DELETE'
  'GET'
  'HEAD'
  'OPTIONS'
  'PATCH'
  'POST'
  'PUT'
  'TRACE'
]
var productName = take('${toLower(foundryAccountName)}-${toLower(foundryProjectName)}-ai-${uniqueString(resourceGroup().id, foundryAccountName, foundryProjectName)}', 80)
var directApiId = '${toLower(foundryAccountName)}-model-gateway'
var directApiPath = 'ai-gateway'
var portalBackendPolicy = replace(
  '''
  <policies>
    <inbound>
      <base />
      <set-backend-service backend-id="__BACKEND_ID__" />
    </inbound>
    <backend>
      <base />
    </backend>
    <outbound>
      <base />
    </outbound>
    <on-error>
      <base />
    </on-error>
  </policies>
  ''',
  '__BACKEND_ID__',
  foundryAccountName
)
var directResponsesPolicy = replace(
  replace(
    loadTextContent('../policies/foundry-model-gateway-policy.xml'),
    '__TENANT_ID__',
    tenantId
  ),
  '__BACKEND_ID__',
  foundryAccountName
)
var userLevelPolicy = replace(
  loadTextContent('../policies/foundry-model-user-level-policy.xml'),
  '__PROJECT_NAME__',
  foundryProjectName
)
resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: foundryAccountName
  properties: {
    protocol: 'http'
    url: 'https://${foundryAccount.name}.services.ai.azure.com/'
    resourceId: uri(environment().resourceManager, foundryAccount.id)
    credentials: {
      managedIdentity: {
        resource: 'https://ai.azure.com/'
      }
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource portalApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: foundryAccountName
  properties: {
    displayName: '${foundryProjectName} - Model API (API Key + Portal Admin Center)'
    apiRevision: '1'
    description: 'Portal-compatible subscription-key model gateway.'
    path: foundryAccountName
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

resource portalOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for method in methods: {
  parent: portalApi
  name: '${toLower(method)}-default'
  properties: {
    displayName: method
    method: method
    urlTemplate: '/*'
  }
}]

resource portalPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: portalApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: portalBackendPolicy
  }
  dependsOn: [
    portalOperations
    backend
  ]
}

resource directModelApi 'Microsoft.ApiManagement/service/apis@2025-03-01-preview' = {
  parent: apim
  name: directApiId
  properties: {
    apiRevision: '1'
    backendId: backend.name
    description: 'Foundry Responses model API used by the hosted agent.'
    displayName: '${foundryProjectName} - Hosted agent AI model'
    path: directApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource aiModelTag 'Microsoft.ApiManagement/service/tags@2024-05-01' = {
  parent: apim
  name: 'aimodel'
  properties: {
    displayName: 'aimodel'
  }
}

resource directModelApiTag 'Microsoft.ApiManagement/service/apis/tags@2024-05-01' = {
  parent: directModelApi
  name: aiModelTag.name
}

resource responsesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: directModelApi
  name: 'createResponses'
  properties: {
    description: 'Creates a model response through the project-compatible direct hosted-agent route.'
    displayName: 'Create response'
    method: 'POST'
    urlTemplate: '/api/projects/${foundryProjectName}/openai/v1/responses'
  }
}

resource userLevelPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'foundry-model-user-level'
  properties: {
    description: 'Per-user model token limit for direct hosted-agent Responses calls.'
    format: 'rawxml'
    value: userLevelPolicy
  }
}

resource directModelApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: directModelApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: directResponsesPolicy
  }
  dependsOn: [
    responsesOperation
    userLevelPolicyFragment
  ]
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: productName
  properties: {
    displayName: productName
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: portalApi.name
}

resource productSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: productName
  properties: {
    allowTracing: false
    displayName: productName
    scope: product.id
    state: 'active'
  }
  dependsOn: [
    productApi
  ]
}

resource accountToApimLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryAccount
  name: uniqueString(foundryAccount.id, apim.id, 'account-apim')
  properties: {
    targetId: apim.id
  }
}

resource apimToAccountLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: apim
  name: uniqueString(apim.id, foundryAccount.id, 'apim-account')
  properties: {
    targetId: foundryAccount.id
  }
}

resource projectToProductLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryProject
  name: uniqueString(foundryProject.id, product.id, 'project-product')
  properties: {
    targetId: product.id
  }
}

output portalProjectEndpoint string = 'https://${apim.name}.azure-api.net/${foundryAccountName}/api/projects/${foundryProjectName}'
output modelDeploymentName string = modelDeploymentName
output directProjectEndpoint string = 'https://${apim.name}.azure-api.net/${directApiPath}/api/projects/${foundryProjectName}'
output productName string = product.name
output productSubscriptionName string = productSubscription.name

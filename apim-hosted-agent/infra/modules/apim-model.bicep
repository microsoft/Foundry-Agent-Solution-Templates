targetScope = 'resourceGroup'

@description('Existing API Management service name.')
param apimName string

@description('Microsoft Foundry account name and portal-compatible model API ID.')
param foundryAccountName string

@description('Microsoft Foundry project name.')
param foundryProjectName string

@description('Foundry model deployment name used by token policy metadata.')
param modelDeploymentName string

@minValue(1)
param modelTokenLimit int

@minValue(1)
param modelTokenQuota int

@allowed([
  'Hourly'
  'Daily'
  'Weekly'
  'Monthly'
  'Yearly'
])
param modelTokenQuotaPeriod string
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
var oauthApiId = '${toLower(foundryAccountName)}-oauth'
var oauthApiPath = '${toLower(foundryAccountName)}-oauth'
var deploymentPolicySegment = replace(toLower(modelDeploymentName), '_', '-')
var portalModelPolicy = replace(loadTextContent('../policies/foundry-project-model-key-auth-policy.xml'), '__BACKEND_ID__', foundryAccountName)
var oauthModelPolicy = replace(replace(loadTextContent('../policies/foundry-model-oauth-policy.xml'), '__TENANT_ID__', tenantId), '__BACKEND_ID__', foundryAccountName)
var userLevelPolicy = replace(loadTextContent('../policies/foundry-model-user-level-policy.xml'), '__PROJECT_NAME__', foundryProjectName)
var projectTokenPolicy = replace(
  replace(
    replace(
      replace(
        loadTextContent('../policies/foundry-project-token-policy.xml'),
        '__MODEL_DEPLOYMENT__',
        deploymentPolicySegment
      ),
      '__TOKEN_LIMIT__',
      string(modelTokenLimit)
    ),
    '__TOKEN_QUOTA__',
    string(modelTokenQuota)
  ),
  '__TOKEN_QUOTA_PERIOD__',
  modelTokenQuotaPeriod
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

resource portalApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: foundryAccountName
  properties: {
    displayName: '${foundryProjectName} - Model API (API Key + Portal Admin Center)'
    apiRevision: '1'
    description: 'Portal-compatible subscription-key model gateway with aggregate project limits.'
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
    value: portalModelPolicy
  }
  dependsOn: [
    portalOperations
  ]
}

resource oauthApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: oauthApiId
  properties: {
    apiRevision: '1'
    description: 'OAuth model gateway restricted to the hosted-agent managed identity.'
    displayName: '${foundryProjectName} - Model API (OAuth + Hosted Agent Runtime)'
    path: oauthApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource oauthOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for method in methods: {
  parent: oauthApi
  name: '${toLower(method)}-default'
  properties: {
    displayName: method
    method: method
    urlTemplate: '/*'
  }
}]

resource oauthPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: oauthApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: oauthModelPolicy
  }
  dependsOn: [
    oauthOperations
  ]
}

resource oauthPostOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' existing = {
  parent: oauthApi
  name: 'post-default'
}

resource userLevelPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'foundry-model-user-level'
  properties: {
    description: 'Per-user model token limit derived from the trusted tenant and object identifiers.'
    format: 'rawxml'
    value: userLevelPolicy
  }
}

resource oauthPostContentSafetyPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: oauthPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/foudnry-model-content-safety-policy.xml')
  }
  dependsOn: [
    oauthOperations
    oauthPolicy
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

resource productPolicy 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = {
  parent: product
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: projectTokenPolicy
  }
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
output oauthApiId string = oauthApi.name
output oauthProjectEndpoint string = 'https://${apim.name}.azure-api.net/${oauthApiPath}/api/projects/${foundryProjectName}'
output productName string = product.name
output productSubscriptionName string = productSubscription.name

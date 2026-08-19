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
var adminApiId = '${toLower(foundryAccountName)}-model-gateway'
var adminApiPath = 'ai-gateway'
var adminBackendId = '${toLower(foundryAccountName)}-ai-endpoint'
var adminConnectionName = '${toLower(foundryAccountName)}-apim'
var inferenceApiVersion = '2024-05-01-preview'
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
var adminModelPolicy = replace(
  replace(
    replace(
      loadTextContent('../policies/foundry-hosted-admin-model-policy.xml'),
      '__TENANT_ID__',
      tenantId
    ),
    '__PROJECT_PRINCIPAL_ID__',
    foundryProject.identity.principalId
  ),
  '__BACKEND_ID__',
  adminBackendId
)
var directResponsesPolicy = replace(
  replace(
    loadTextContent('../policies/foundry-hosted-direct-responses-policy.xml'),
    '__TENANT_ID__',
    tenantId
  ),
  '__BACKEND_ID__',
  foundryAccountName
)
var userLevelPolicy = replace(
  replace(
    loadTextContent('../policies/foundry-model-user-level-policy.xml'),
    '__PROJECT_NAME__',
    foundryProjectName
  ),
  '__MODEL_DEPLOYMENT__',
  modelDeploymentName
)
var connectionModels = [
  {
    name: modelDeployment.name
    properties: {
      model: {
        name: modelDeployment.properties.model.name
        version: modelDeployment.properties.model.version
        format: modelDeployment.properties.model.format
      }
    }
  }
]
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

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' existing = {
  parent: foundryAccount
  name: modelDeploymentName
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

resource adminModelBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: adminBackendId
  properties: {
    protocol: 'http'
    url: 'https://${foundryAccount.name}.services.ai.azure.com/'
    resourceId: uri(environment().resourceManager, foundryAccount.id)
    credentials: {
      #disable-next-line BCP037
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com/'
      }
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

resource adminModelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: adminApiId
  properties: {
    apiRevision: '1'
    description: 'Managed-identity model gateway exposed as a Foundry Admin-connected model.'
    displayName: '${foundryProjectName} - Admin-connected model'
    path: adminApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: adminModelApi
  name: 'getChatCompletions'
  properties: {
    description: 'Gets chat completions for the configured Foundry model deployment.'
    displayName: 'Create chat completion'
    method: 'POST'
    templateParameters: [
      {
        name: 'api-version'
        description: 'Foundry model inference API version.'
        type: 'string'
        required: true
        values: [
          inferenceApiVersion
        ]
      }
    ]
    urlTemplate: '/models/chat/completions?api-version={api-version}'
  }
}

resource modelInfoOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: adminModelApi
  name: 'getModelInfo'
  properties: {
    description: 'Returns information about the configured Foundry model deployment.'
    displayName: 'Get model information'
    method: 'GET'
    templateParameters: [
      {
        name: 'api-version'
        description: 'Foundry model inference API version.'
        type: 'string'
        required: true
        values: [
          inferenceApiVersion
        ]
      }
    ]
    urlTemplate: '/models/info?api-version={api-version}'
  }
}

resource responsesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: adminModelApi
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

resource adminModelApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: adminModelApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: adminModelPolicy
  }
  dependsOn: [
    chatCompletionsOperation
    modelInfoOperation
    adminModelBackend
  ]
}

resource responsesOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: responsesOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: directResponsesPolicy
  }
  dependsOn: [
    backend
    userLevelPolicyFragment
  ]
}

resource foundryAdminConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: foundryAccount
  name: adminConnectionName
  properties: {
    #disable-next-line BCP036
    authType: 'ProjectManagedIdentity'
    audience: 'https://cognitiveservices.azure.com'
    category: 'ApiManagement'
    group: 'AzureAI'
    target: 'https://${apim.name}.azure-api.net/${adminApiPath}/models'
    useWorkspaceManagedIdentity: false
    isSharedToAll: true
    isDefault: true
    metadata: {
      deploymentInPath: 'false'
      inferenceAPIVersion: inferenceApiVersion
      customHeaders: '{}'
      models: string(connectionModels)
    }
  }
  dependsOn: [
    adminModelApiPolicy
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
output adminConnectionName string = foundryAdminConnection.name
output adminConnectionModel string = '${foundryAdminConnection.name}/${modelDeployment.name}'
output adminModelDeploymentName string = modelDeployment.name
output adminModelApiUrl string = 'https://${apim.name}.azure-api.net/${adminApiPath}/models'
output directProjectEndpoint string = 'https://${apim.name}.azure-api.net/${adminApiPath}/api/projects/${foundryProjectName}'
output productName string = product.name
output productSubscriptionName string = productSubscription.name

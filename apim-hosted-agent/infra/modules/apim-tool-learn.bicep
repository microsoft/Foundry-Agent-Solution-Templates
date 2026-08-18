targetScope = 'resourceGroup'

@description('Existing API Management service name.')
param apimName string

@description('Microsoft Foundry project name used in the MCP route.')
param foundryProjectName string

var route = 'tool-${toLower(foundryProjectName)}-mcp'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'mcp'
  properties: {
    protocol: 'http'
    url: 'https://learn.microsoft.com/api/mcp'
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  parent: apim
  name: route
  properties: {
    displayName: '${foundryProjectName} - MCP Tool (Microsoft Learn)'
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: 'https://learn.microsoft.com/api/mcp'
    backendId: backend.name
    path: route
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

resource policy 'Microsoft.ApiManagement/service/apis/policies@2024-10-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/foundry-tool-learn-mcp-policy.xml')
  }
}

output gatewayUrl string = 'https://${apim.name}.azure-api.net/${route}'
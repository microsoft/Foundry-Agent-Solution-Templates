targetScope = 'resourceGroup'

@description('Existing API Management service name.')
param apimName string

@description('Microsoft Foundry project name used in the MCP route.')
param foundryProjectName string

@description('Google OAuth-protected MCP HTTPS endpoint ending in /mcp.')
param googleMcpEndpoint string

var route = 'tool-${toLower(foundryProjectName)}-google-mcp'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'google-mcp'
  properties: {
    protocol: 'http'
    url: googleMcpEndpoint
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  parent: apim
  name: route
  properties: {
    displayName: '${foundryProjectName} - MCP Tool (Google)'
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: googleMcpEndpoint
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
    value: loadTextContent('../policies/foundry-tool-google-mcp-policy.xml')
  }
}

output gatewayUrl string = 'https://${apim.name}.azure-api.net/${route}'

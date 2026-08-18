targetScope = 'resourceGroup'

@description('Microsoft Foundry account that owns the project.')
param foundryAccountName string

@description('Microsoft Foundry project whose managed identity receives account access.')
param foundryProjectName string

@description('Governed Microsoft Learn MCP endpoint exposed by API Management.')
param learnMcpUrl string

@description('Governed GitHub MCP endpoint exposed by API Management.')
param githubMcpUrl string = ''

@description('Optional GitHub OAuth App client ID. The GitHub connection is created only when both OAuth values are set.')
param githubOAuthClientId string = ''

@secure()
@description('Optional GitHub OAuth App client secret. The GitHub connection is created only when both OAuth values are set.')
param githubOAuthClientSecret string = ''

var foundryUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)
var githubEnabled = !empty(githubMcpUrl) && !empty(githubOAuthClientId) && !empty(githubOAuthClientSecret)

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource projectFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, foundryProject.id, foundryUserRoleDefinitionId)
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: foundryUserRoleDefinitionId
  }
}

resource learnConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: 'mslearn'
  properties: {
    target: learnMcpUrl
    authType: 'None'
    category: 'RemoteTool'
    metadata: {
      toolEntityId: 'microsoft-learn'
      type: 'catalog_MCP'
    }
  }
}

resource githubConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (githubEnabled) {
  parent: foundryProject
  name: 'github'
  properties: {
    target: githubMcpUrl
    authType: 'OAuth2'
    category: 'RemoteTool'
    metadata: {
      oAuthProvider: 'custom'
      type: 'custom_MCP'
    }
    credentials: {
      clientId: githubOAuthClientId
      clientSecret: githubOAuthClientSecret
    }
    #disable-next-line BCP037
    authorizationUrl: 'https://github.com/login/oauth/authorize'
    #disable-next-line BCP037
    tokenUrl: 'https://github.com/login/oauth/access_token'
    #disable-next-line BCP037
    refreshUrl: 'https://github.com/login/oauth/access_token'
    #disable-next-line BCP037
    scopes: [
      'offline_access'
      'repo'
      'read:user'
    ]
  }
}

@description('Generated OAuth redirect URL for the GitHub MCP connection.')
output GITHUB_OAUTH_REDIRECT_URL string = githubEnabled ? any(githubConnection!).properties.redirectUrl : ''

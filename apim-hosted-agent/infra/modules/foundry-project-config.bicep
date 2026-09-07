targetScope = 'resourceGroup'

param foundryAccountName string
param foundryProjectName string
param learnMcpUrl string
param githubMcpUrl string = ''
param githubOAuthClientId string = ''
@secure()
param githubOAuthClientSecret string = ''
param googleMcpEnabled string = 'false'
param googleMcpUrl string = ''
param googleOAuthClientId string = ''
@secure()
param googleOAuthClientSecret string = ''

var foundryUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)
var githubEnabled = !empty(githubMcpUrl) && !empty(githubOAuthClientId) && !empty(githubOAuthClientSecret)
var googleEnabled = toLower(googleMcpEnabled) == 'true' && !empty(googleMcpUrl) && !empty(googleOAuthClientId) && !empty(googleOAuthClientSecret)

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

resource googleConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = if (googleEnabled) {
  parent: foundryProject
  name: 'google'
  properties: {
    target: googleMcpUrl
    authType: 'OAuth2'
    category: 'RemoteTool'
    peRequirement: 'NotRequired'
    credentials: {
      clientId: googleOAuthClientId
      clientSecret: googleOAuthClientSecret
    }
    #disable-next-line BCP037
    authorizationUrl: 'https://accounts.google.com/o/oauth2/v2/auth'
    #disable-next-line BCP037
    tokenUrl: 'https://oauth2.googleapis.com/token'
    #disable-next-line BCP037
    refreshUrl: 'https://oauth2.googleapis.com/token'
    #disable-next-line BCP037
    scopes: [
      'openid'
      'https://www.googleapis.com/auth/userinfo.email'
      'https://www.googleapis.com/auth/userinfo.profile'
    ]
  }
}

output GITHUB_OAUTH_REDIRECT_URL string = githubEnabled ? any(githubConnection!).properties.redirectUrl : ''
output GOOGLE_OAUTH_REDIRECT_URL string = googleEnabled ? any(googleConnection!).properties.redirectUrl : ''

targetScope = 'resourceGroup'

param foundryAccountName string
param foundryResourceGroupName string
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

module foundryProjectConfig 'modules/foundry-project-config.bicep' = {
  name: 'foundry-project-config'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    learnMcpUrl: learnMcpUrl
    githubMcpUrl: githubMcpUrl
    githubOAuthClientId: githubOAuthClientId
    githubOAuthClientSecret: githubOAuthClientSecret
    googleMcpEnabled: googleMcpEnabled
    googleMcpUrl: googleMcpUrl
    googleOAuthClientId: googleOAuthClientId
    googleOAuthClientSecret: googleOAuthClientSecret
  }
}

output GITHUB_OAUTH_REDIRECT_URL string = foundryProjectConfig.outputs.GITHUB_OAUTH_REDIRECT_URL
output GOOGLE_OAUTH_REDIRECT_URL string = foundryProjectConfig.outputs.GOOGLE_OAUTH_REDIRECT_URL

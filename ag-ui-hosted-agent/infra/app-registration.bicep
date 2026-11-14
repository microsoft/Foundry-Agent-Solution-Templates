extension microsoftGraphV1

@description('Stable unique name, so redeployments update the same registration.')
param uniqueName string
param displayName string
param webUrl string
@description('Principal ID of the web app managed identity used as the federated credential.')
param federatedIdentityPrincipalId string
param issuer string

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: uniqueName
  displayName: displayName
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: ['${webUrl}/.auth/login/aad/callback']
    implicitGrantSettings: { enableIdTokenIssuance: true }
  }

  resource managedIdentityCredential 'federatedIdentityCredentials@v1.0' = {
    name: '${app.uniqueName}/web-managed-identity'
    audiences: ['api://AzureADTokenExchange']
    issuer: issuer
    subject: federatedIdentityPrincipalId
  }
}

resource servicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: app.appId
}

output clientId string = app.appId

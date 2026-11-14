param environmentName string
param location string
param foundryAccountName string
param foundryProjectName string
param foundryProjectEndpoint string
param agentName string
param webExists bool
param gatewayExists bool

var token = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var tags = { 'azd-env-name': environmentName }
var azureAiUserRole = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var acrPullRole = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'cr${token}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource webIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-web-${token}'
  location: location
  tags: tags
}

resource gatewayIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-gateway-${token}'
  location: location
  tags: tags
}

resource webAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, webIdentity.id, acrPullRole)
  properties: {
    principalId: webIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRole)
  }
}

resource gatewayAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, gatewayIdentity.id, acrPullRole)
  properties: {
    principalId: gatewayIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRole)
  }
}

// Only the gateway calls Foundry. The web app holds no Foundry role.
resource gatewayFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(foundryProject.id, gatewayIdentity.id, azureAiUserRole)
  properties: {
    principalId: gatewayIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRole)
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${token}'
  location: location
  tags: tags
  properties: {}
}

module gatewayImage 'existing-image.bicep' = {
  name: 'gateway-image'
  params: { name: 'ca-gateway-${token}', exists: gatewayExists }
}

resource gateway 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-gateway-${token}'
  location: location
  tags: union(tags, { 'azd-service-name': 'gateway' })
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${gatewayIdentity.id}': {} } }
  dependsOn: [gatewayAcrPull]
  properties: {
    environmentId: environment.id
    configuration: {
      // Internal ingress: only apps in this environment can reach the gateway.
      ingress: { external: false, targetPort: 8000, transport: 'auto' }
      registries: [{ server: registry.properties.loginServer, identity: gatewayIdentity.id }]
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: gatewayImage.outputs.image
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'FOUNDRY_PROJECT_ENDPOINT', value: foundryProjectEndpoint }
            { name: 'FOUNDRY_AGENT_NAME', value: agentName }
            { name: 'AZURE_CLIENT_ID', value: gatewayIdentity.properties.clientId }
          ]
        }
      ]
      // Pending approvals live in gateway memory; one replica keeps a resume on the replica that issued it.
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
}

module webImage 'existing-image.bicep' = {
  name: 'web-image'
  params: { name: 'ca-web-${token}', exists: webExists }
}

resource web 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-web-${token}'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${webIdentity.id}': {} } }
  dependsOn: [webAcrPull]
  properties: {
    environmentId: environment.id
    configuration: {
      ingress: { external: true, targetPort: 3000, transport: 'auto' }
      registries: [{ server: registry.properties.loginServer, identity: webIdentity.id }]
      // Built-in sign-in uses the managed identity as a federated credential instead of a client secret.
      secrets: [{ name: 'override-use-mi-fic-assertion-client-id', value: webIdentity.properties.clientId }]
    }
    template: {
      containers: [
        {
          name: 'web'
          image: webImage.outputs.image
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [{ name: 'AGUI_GATEWAY_URL', value: 'https://${gateway.properties.configuration.ingress.fqdn}' }]
        }
      ]
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
}

var issuer = '${az.environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'

module registration 'app-registration.bicep' = {
  name: 'web-app-registration'
  params: {
    uniqueName: 'ag-ui-hosted-agent-${token}'
    displayName: 'Claims triage web (${environmentName})'
    webUrl: 'https://${web.properties.configuration.ingress.fqdn}'
    federatedIdentityPrincipalId: webIdentity.properties.principalId
    issuer: issuer
  }
}

resource webAuth 'Microsoft.App/containerApps/authConfigs@2024-10-02-preview' = {
  parent: web
  name: 'current'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: registration.outputs.clientId
          clientSecretSettingName: 'override-use-mi-fic-assertion-client-id'
          openIdIssuer: issuer
        }
      }
    }
  }
}

output registryEndpoint string = registry.properties.loginServer
output webUrl string = 'https://${web.properties.configuration.ingress.fqdn}'
output appRegistrationClientId string = registration.outputs.clientId

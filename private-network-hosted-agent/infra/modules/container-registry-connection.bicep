targetScope = 'resourceGroup'

param accountName string
param projectName string
param projectPrincipalId string
param connectionName string
param containerRegistryResourceId string
param containerRegistryEndpoint string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName

  resource project 'projects' existing = {
    name: projectName
  }
}

resource connection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: account::project
  name: connectionName
  properties: {
    category: 'ContainerRegistry'
    target: containerRegistryEndpoint
    authType: 'ManagedIdentity'
    isSharedToAll: true
    credentials: {
      clientId: projectPrincipalId
      resourceId: containerRegistryResourceId
    }
    metadata: {
      ResourceId: containerRegistryResourceId
    }
  }
}

output connectionName string = connection.name
output connectionId string = connection.id

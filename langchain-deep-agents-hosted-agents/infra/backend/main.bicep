targetScope = 'resourceGroup'

param environmentName string = resourceGroup().name
param location string = resourceGroup().location
param foundryAccountName string
param foundryProjectName string
param foundryProjectEndpoint string
param foundryAgentName string = 'langgraph-deep-agents'
param foundryAgentVersion string
param foundryModelName string

@minLength(5)
@maxLength(20)
param resourcePrefix string

@minLength(5)
@maxLength(50)
param containerRegistryName string

@minLength(1)
param cosmosDatabaseName string

@minLength(1)
param cosmosContainerName string

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)
var backendName = '${resourcePrefix}-api-${suffix}'
var identityName = '${resourcePrefix}-api-${suffix}'
var environmentResourceName = '${resourcePrefix}-${suffix}'
var cosmosName = take('${resourcePrefix}-${suffix}', 44)
var tags = {
  'azd-env-name': environmentName
  'azd-service-name': 'backend'
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource registryPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'AcrPull')
  scope: registry
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource registryPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, deployer().objectId, 'AcrPush')
  scope: registry
  properties: {
    principalId: deployer().objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: 'Enabled'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmos
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

resource domain 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/ownerId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
      }
    }
  }
}

resource dataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-05-15' existing = {
  parent: cosmos
  name: '00000000-0000-0000-0000-000000000002'
}

resource backendCosmosAccess 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, identity.id, dataContributor.id)
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: dataContributor.id
    scope: cosmos.id
  }
}

resource developerCosmosAccess 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, deployer().objectId, dataContributor.id)
  properties: {
    principalId: deployer().objectId
    roleDefinitionId: dataContributor.id
    scope: cosmos.id
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource backendFoundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryProject.id, identity.id, 'Cognitive Services User')
  scope: foundryProject
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentResourceName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
  }
}

resource backend 'Microsoft.App/containerApps@2025-07-01' = {
  name: backendName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8000
        transport: 'auto'
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: identity.properties.clientId
            }
            {
              name: 'COSMOS_ENDPOINT'
              value: cosmos.properties.documentEndpoint
            }
            {
              name: 'COSMOS_DATABASE_NAME'
              value: cosmosDatabaseName
            }
            {
              name: 'COSMOS_CONTAINER_NAME'
              value: cosmosContainerName
            }
            {
              name: 'FOUNDRY_PROJECT_ENDPOINT'
              value: foundryProjectEndpoint
            }
            {
              name: 'FOUNDRY_AGENT_NAME'
              value: foundryAgentName
            }
            {
              name: 'FOUNDRY_AGENT_VERSION'
              value: foundryAgentVersion
            }
            {
              name: 'FOUNDRY_MODEL_NAME'
              value: foundryModelName
            }
            {
              name: 'LOCAL_DEVELOPMENT'
              value: 'false'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8000
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    registryPull
    backendCosmosAccess
    backendFoundryAccess
  ]
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = registry.name
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = managedEnvironment.name
output COSMOS_ENDPOINT string = cosmos.properties.documentEndpoint
output COSMOS_DATABASE_NAME string = cosmosDatabaseName
output COSMOS_CONTAINER_NAME string = cosmosContainerName
output SERVICE_BACKEND_NAME string = backend.name
output SERVICE_BACKEND_ENDPOINT_URL string = 'https://${backend.properties.configuration.ingress.fqdn}'
output SERVICE_BACKEND_RESOURCE_ID string = backend.id
output SERVICE_BACKEND_IDENTITY_CLIENT_ID string = identity.properties.clientId

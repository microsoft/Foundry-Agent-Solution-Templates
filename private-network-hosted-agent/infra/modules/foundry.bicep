targetScope = 'resourceGroup'

param name string
param projectName string
param location string
param tags object
param agentSubnetId string
param privateEndpointSubnetId string
param privateDnsZoneIds array
param foundryCmkIdentityId string
param foundryCmkIdentityClientId string
param keyVaultName string
param foundryKeyName string
param foundryKeyVersion string
param deploymentPrincipalObjectId string
param invocationTestPrincipalObjectId string
param modelName string
param modelVersion string
param modelCapacity int

var keyVaultCryptoUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '12338af0-0e69-4776-bea7-57ae8d297424'
)
var foundryUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)
var foundryAgentConsumerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'
)

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${foundryCmkIdentityId}': {}
    }
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: name
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
    encryption: {
      keySource: 'Microsoft.KeyVault'
      keyVaultProperties: {
        keyVaultUri: keyVault.properties.vaultUri
        keyName: foundryKeyName
        keyVersion: foundryKeyVersion
        identityClientId: foundryCmkIdentityClientId
      }
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Private Hosted Agent'
    description: 'Private Python Hosted Agent with direct Azure AI Search SDK tool.'
  }
}

module accountKeyVaultRole './key-vault-role-assignment.bicep' = {
  name: '${name}-account-vault-role'
  params: {
    keyVaultName: keyVault.name
    principalId: account.identity.principalId
    roleDefinitionId: keyVaultCryptoUserRoleId
  }
}

module projectKeyVaultRole './key-vault-role-assignment.bicep' = {
  name: '${name}-project-vault-role'
  params: {
    keyVaultName: keyVault.name
    principalId: project.identity.principalId
    roleDefinitionId: keyVaultCryptoUserRoleId
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: modelName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

module projectFoundryRole './account-role-assignment.bicep' = {
  name: '${name}-project-foundry-role'
  params: {
    accountName: account.name
    principalId: project.identity.principalId
    roleDefinitionId: foundryUserRoleId
  }
}

resource deploymentFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, deploymentPrincipalObjectId, foundryUserRoleId)
  scope: project
  properties: {
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: foundryUserRoleId
  }
}

resource invocationConsumerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(invocationTestPrincipalObjectId)) {
  name: guid(project.id, invocationTestPrincipalObjectId, foundryAgentConsumerRoleId)
  scope: project
  properties: {
    principalId: invocationTestPrincipalObjectId
    roleDefinitionId: foundryAgentConsumerRoleId
  }
}

module privateEndpoint './private-endpoint.bicep' = {
  name: '${name}-private-endpoint'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    subnetId: privateEndpointSubnetId
    targetResourceId: account.id
    groupIds: [
      'account'
    ]
    privateDnsZoneIds: privateDnsZoneIds
  }
}

output accountName string = account.name
output accountId string = account.id
output accountPrincipalId string = account.identity.principalId
output projectName string = project.name
output projectId string = project.id
output projectPrincipalId string = project.identity.principalId
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output modelDeploymentId string = modelDeployment.id
output accountKeyVaultRoleId string = accountKeyVaultRole.outputs.id
output projectKeyVaultRoleId string = projectKeyVaultRole.outputs.id
output projectFoundryRoleId string = projectFoundryRole.outputs.id

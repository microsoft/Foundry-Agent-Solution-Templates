targetScope = 'resourceGroup'

param keyVaultName string
param keyName string
param principalId string
param roleDefinitionId string
param principalType string = 'ServicePrincipal'

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2024-11-01' existing = {
  parent: keyVault
  name: keyName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(key.id, principalId, roleDefinitionId)
  scope: key
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}

output id string = assignment.id


targetScope = 'resourceGroup'

param accountName string
param principalId string
param roleDefinitionId string
param principalType string = 'ServicePrincipal'

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, principalId, roleDefinitionId)
  scope: account
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}

output id string = assignment.id


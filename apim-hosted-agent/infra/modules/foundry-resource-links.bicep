targetScope = 'resourceGroup'

param foundryAccountName string
param foundryProjectName string
param apimId string
param productId string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource accountToApimLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryAccount
  name: uniqueString(foundryAccount.id, apimId, 'account-apim')
  properties: {
    targetId: apimId
  }
}

resource projectToProductLink 'Microsoft.Resources/links@2016-09-01' = {
  scope: foundryProject
  name: uniqueString(foundryProject.id, productId, 'project-product')
  properties: {
    targetId: productId
  }
}

targetScope = 'resourceGroup'

param name string
param location string
param privateEndpointLocation string
param tags object
param privateEndpointSubnetId string
param privateDnsZoneId string
param keyVaultName string
param searchKeyName string
param deploymentPrincipalObjectId string

var searchServiceContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
)
var searchIndexDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
)
var keyVaultCryptoServiceEncryptionUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'e147488a-f6f5-4113-8e2d-b22465e65bf6'
)

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'basic'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'Default'
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Enabled'
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource searchKey 'Microsoft.KeyVault/vaults/keys@2024-11-01' existing = {
  parent: keyVault
  name: searchKeyName
}

module searchKeyRole './key-role-assignment.bicep' = {
  name: '${name}-search-key-role'
  params: {
    keyVaultName: keyVault.name
    keyName: searchKey.name
    principalId: searchService.identity.principalId
    roleDefinitionId: keyVaultCryptoServiceEncryptionUserRoleId
  }
}

resource bootstrapServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, deploymentPrincipalObjectId, searchServiceContributorRoleId)
  scope: searchService
  properties: {
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: searchServiceContributorRoleId
  }
}

resource bootstrapDataRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, deploymentPrincipalObjectId, searchIndexDataContributorRoleId)
  scope: searchService
  properties: {
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: searchIndexDataContributorRoleId
  }
}

module privateEndpoint './private-endpoint.bicep' = {
  name: '${name}-private-endpoint'
  params: {
    name: 'pe-${name}'
    location: privateEndpointLocation
    tags: tags
    subnetId: privateEndpointSubnetId
    targetResourceId: searchService.id
    groupIds: [
      'searchService'
    ]
    privateDnsZoneIds: [
      privateDnsZoneId
    ]
  }
}

output searchServiceName string = searchService.name
output searchServiceId string = searchService.id
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
output searchPrincipalId string = searchService.identity.principalId
output searchKeyRoleId string = searchKeyRole.outputs.id

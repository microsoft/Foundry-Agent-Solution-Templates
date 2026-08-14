targetScope = 'resourceGroup'

param name string
param identityName string
param location string
param tags object
param privateEndpointSubnetId string
param privateDnsZoneId string

var keyVaultCryptoUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '12338af0-0e69-4776-bea7-57ae8d297424'
)

resource foundryCmkIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource foundryKey 'Microsoft.KeyVault/vaults/keys@2024-11-01' = {
  parent: keyVault
  name: 'cmk-foundry'
  properties: {
    kty: 'RSA'
    keySize: 3072
    attributes: {
      enabled: true
    }
    rotationPolicy: {
      attributes: {
        expiryTime: 'P2Y'
      }
      lifetimeActions: [
        {
          trigger: {
            timeAfterCreate: 'P18M'
          }
          action: {
            type: 'rotate'
          }
        }
      ]
    }
  }
}

resource searchKey 'Microsoft.KeyVault/vaults/keys@2024-11-01' = {
  parent: keyVault
  name: 'cmk-search'
  properties: {
    kty: 'RSA'
    keySize: 3072
    attributes: {
      enabled: true
    }
    rotationPolicy: {
      attributes: {
        expiryTime: 'P2Y'
      }
      lifetimeActions: [
        {
          trigger: {
            timeAfterCreate: 'P18M'
          }
          action: {
            type: 'rotate'
          }
        }
      ]
    }
  }
}

module foundryKeyRole './key-role-assignment.bicep' = {
  name: '${name}-foundry-key-role'
  params: {
    keyVaultName: keyVault.name
    keyName: foundryKey.name
    principalId: foundryCmkIdentity.properties.principalId
    roleDefinitionId: keyVaultCryptoUserRoleId
  }
}

module privateEndpoint './private-endpoint.bicep' = {
  name: '${name}-private-endpoint'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    subnetId: privateEndpointSubnetId
    targetResourceId: keyVault.id
    groupIds: [
      'vault'
    ]
    privateDnsZoneIds: [
      privateDnsZoneId
    ]
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output foundryKeyName string = foundryKey.name
output foundryKeyVersion string = last(split(foundryKey.properties.keyUriWithVersion, '/'))
output foundryKeyId string = foundryKey.id
output searchKeyName string = searchKey.name
output searchKeyVersion string = last(split(searchKey.properties.keyUriWithVersion, '/'))
output searchKeyId string = searchKey.id
output foundryCmkIdentityId string = foundryCmkIdentity.id
output foundryCmkIdentityClientId string = foundryCmkIdentity.properties.clientId
output foundryCmkIdentityPrincipalId string = foundryCmkIdentity.properties.principalId
output foundryKeyRoleId string = foundryKeyRole.outputs.id

targetScope = 'resourceGroup'

param tags object

var zoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.vaultcore.azure.net'
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in zoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

output foundryZoneIds array = [
  zones[0].id
  zones[1].id
  zones[2].id
]
output searchZoneId string = zones[3].id
output keyVaultZoneId string = zones[4].id
output zoneNames array = zoneNames

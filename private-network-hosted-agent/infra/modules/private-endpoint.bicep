targetScope = 'resourceGroup'

param name string
param location string
param tags object
param subnetId string
param targetResourceId string
param groupIds array
param privateDnsZoneIds array

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: groupIds
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Created by the private Hosted Agent solution template.'
            actionsRequired: 'None'
          }
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, index) in privateDnsZoneIds: {
        name: 'zone-${index}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}

output id string = privateEndpoint.id
output networkInterfaceIds array = privateEndpoint.properties.networkInterfaces


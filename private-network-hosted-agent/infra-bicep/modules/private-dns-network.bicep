targetScope = 'resourceGroup'

param name string
param location string
param tags object
param vnetId string
param dnsInboundSubnetId string
param dnsInboundIpAddress string
param zoneNames array

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [for zoneName in zoneNames: {
  name: zoneName
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in zoneNames: {
  parent: zones[index]
  name: 'link-${name}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: 'dnspr-${name}'
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'inbound'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Static'
        privateIpAddress: dnsInboundIpAddress
        subnet: {
          id: dnsInboundSubnetId
        }
      }
    ]
  }
}

output inboundIpAddress string = inbound.properties.ipConfigurations[0].privateIpAddress

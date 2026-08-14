targetScope = 'resourceGroup'

param name string
param remoteVnetName string
param localVnetId string

resource remoteVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: remoteVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = {
  parent: remoteVnet
  name: name
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: localVnetId
    }
  }
}

output id string = peering.id

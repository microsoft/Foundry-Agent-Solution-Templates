param localVnetName string
param peeringName string
param remoteVnetId string
resource local 'Microsoft.Network/virtualNetworks@2024-05-01' existing={name:localVnetName}
resource peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01'={
 parent:local
 name:peeringName
 properties:{remoteVirtualNetwork:{id:remoteVnetId},allowVirtualNetworkAccess:true,allowForwardedTraffic:false,allowGatewayTransit:false,useRemoteGateways:false}
}

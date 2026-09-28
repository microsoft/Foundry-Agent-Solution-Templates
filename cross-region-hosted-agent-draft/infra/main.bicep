targetScope = 'resourceGroup'
param enableStorage bool = true
param enableKnowledge bool = true
param connectionPrefix string = 'cross-region-draft'
param agentLocation string = 'southeastasia'
param agentVnetName string
param privateEndpointSubnetName string = 'snet-private-endpoints'
param blobDnsZoneResourceGroup string
param storageResourceGroup string
param storageAccountName string
param blobContainerName string
param agentPrincipalId string
param knowledgeResourceGroup string
param knowledgeVnetName string

resource agentVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: agentVnetName }
resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
 name: 'privatelink.blob.${environment().suffixes.storage}'
 scope: resourceGroup(blobDnsZoneResourceGroup)
}
module storage './modules/blob-endpoint.bicep' = if (enableStorage) {
 name: '${connectionPrefix}-blob'
 params: {
  name: '${connectionPrefix}-blob'
  location: agentLocation
  subnetId: '${agentVnet.id}/subnets/${privateEndpointSubnetName}'
  storageId: resourceId(storageResourceGroup, 'Microsoft.Storage/storageAccounts', storageAccountName)
  dnsZoneId: blobZone.id
 }
}
module reader './modules/blob-reader.bicep' = if (enableStorage) {
 name: '${connectionPrefix}-reader'
 scope: resourceGroup(storageResourceGroup)
 params: { accountName: storageAccountName, containerName: blobContainerName, principalId: agentPrincipalId }
}
module outbound './modules/peering.bicep' = if (enableKnowledge) {
 name: '${connectionPrefix}-outbound'
 params: {
  localVnetName: agentVnetName
  peeringName: '${connectionPrefix}-to-knowledge'
  remoteVnetId: resourceId(knowledgeResourceGroup, 'Microsoft.Network/virtualNetworks', knowledgeVnetName)
 }
}
module inbound './modules/peering.bicep' = if (enableKnowledge) {
 name: '${connectionPrefix}-return'
 scope: resourceGroup(knowledgeResourceGroup)
 params: { localVnetName: knowledgeVnetName, peeringName: '${connectionPrefix}-to-agent', remoteVnetId: agentVnet.id }
}
output blobEndpoint string = enableStorage ? 'https://${storageAccountName}.blob.${environment().suffixes.storage}' : ''
output knowledgeDnsAction string = enableKnowledge ? 'Link the knowledge private DNS zone or configure enterprise DNS forwarding before testing.' : ''

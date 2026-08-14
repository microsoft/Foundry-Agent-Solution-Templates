targetScope = 'subscription'

@description('Collision-safe azd environment name.')
@minLength(3)
@maxLength(32)
param environmentName string

@description('Foundry, VNet, and Key Vault location.')
param location string = 'westus3'

@description('Search location, independently configurable from the Foundry region.')
param searchLocation string = 'westus3'

param deploymentPrincipalObjectId string
param invocationTestPrincipalObjectId string = ''

@allowed([
  'pointToSite'
  'siteToSite'
  'vnetPeering'
])
param connectivityMode string = 'pointToSite'

param vnetAddressPrefix string = '10.42.0.0/16'
param agentSubnetPrefix string = '10.42.0.0/24'
param privateEndpointSubnetPrefix string = '10.42.1.0/24'
param firewallSubnetPrefix string = '10.42.2.0/26'
@description('Internal orchestration flag set by the unified deployment script after a read-only Firewall existence check.')
param firewallCreationRequired bool = true
param gatewaySubnetPrefix string = '10.42.3.0/27'
param dnsInboundSubnetPrefix string = '10.42.4.0/28'
param dnsInboundIpAddress string = '10.42.4.4'
param p2sAddressPool string = '172.20.0.0/24'
param p2sTenantId string = tenant().tenantId
param s2sGatewayIpAddress string = ''
param s2sRemoteAddressPrefixes array = []
param s2sEnableBgp bool = false
param s2sRemoteAsn int = 65010
param s2sBgpPeeringAddress string = ''

@secure()
param s2sSharedKey string = ''

param remoteVnetResourceId string = ''

@allowed([
  'gpt-5.1'
])
param modelName string = 'gpt-5.1'

@allowed([
  '2025-11-13'
])
param modelVersion string = '2025-11-13'

@minValue(1)
@maxValue(300)
param modelCapacity int = 10

param containerRegistryResourceId string = ''
param containerRegistryEndpoint string = ''

var resourceGroupName = 'rg-${environmentName}'
var ownershipTags = {
  'azd-env-name': environmentName
  'solution-template': 'foundry-private-hosted-agent'
  'resource-group-ownership': 'template-created'
}

resource managedResourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: ownershipTags
}

module solution './solution.bicep' = {
  name: 'fpha-${environmentName}'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    managedResourceGroup
  ]
  params: {
    environmentName: environmentName
    location: location
    searchLocation: searchLocation
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    invocationTestPrincipalObjectId: invocationTestPrincipalObjectId
    connectivityMode: connectivityMode
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    firewallCreationRequired: firewallCreationRequired
    gatewaySubnetPrefix: gatewaySubnetPrefix
    dnsInboundSubnetPrefix: dnsInboundSubnetPrefix
    dnsInboundIpAddress: dnsInboundIpAddress
    p2sAddressPool: p2sAddressPool
    p2sTenantId: p2sTenantId
    s2sGatewayIpAddress: s2sGatewayIpAddress
    s2sRemoteAddressPrefixes: s2sRemoteAddressPrefixes
    s2sEnableBgp: s2sEnableBgp
    s2sRemoteAsn: s2sRemoteAsn
    s2sBgpPeeringAddress: s2sBgpPeeringAddress
    s2sSharedKey: s2sSharedKey
    remoteVnetResourceId: remoteVnetResourceId
    modelName: modelName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
    containerRegistryResourceId: containerRegistryResourceId
    containerRegistryEndpoint: containerRegistryEndpoint
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_LOCATION string = solution.outputs.AZURE_LOCATION
output AZURE_SEARCH_LOCATION string = solution.outputs.AZURE_SEARCH_LOCATION
output RESOURCE_PREFIX string = solution.outputs.RESOURCE_PREFIX
output CONNECTIVITY_MODE string = solution.outputs.CONNECTIVITY_MODE
output AZURE_VNET_ID string = solution.outputs.AZURE_VNET_ID
output AZURE_FIREWALL_ID string = solution.outputs.AZURE_FIREWALL_ID
output AZURE_DNS_RESOLVER_INBOUND_IP string = solution.outputs.AZURE_DNS_RESOLVER_INBOUND_IP
output AZURE_VPN_GATEWAY_NAME string = solution.outputs.AZURE_VPN_GATEWAY_NAME
output AZURE_AI_ACCOUNT_NAME string = solution.outputs.AZURE_AI_ACCOUNT_NAME
output AZURE_AI_ACCOUNT_ID string = solution.outputs.AZURE_AI_ACCOUNT_ID
output AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID string = solution.outputs.AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID
output AZURE_AI_PROJECT_NAME string = solution.outputs.AZURE_AI_PROJECT_NAME
output AZURE_AI_PROJECT_ID string = solution.outputs.AZURE_AI_PROJECT_ID
output AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID string = solution.outputs.AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID
output FOUNDRY_PROJECT_ENDPOINT string = solution.outputs.FOUNDRY_PROJECT_ENDPOINT
output AZURE_AI_PROJECT_ENDPOINT string = solution.outputs.AZURE_AI_PROJECT_ENDPOINT
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = solution.outputs.AZURE_AI_MODEL_DEPLOYMENT_NAME
output AZURE_SEARCH_SERVICE_NAME string = solution.outputs.AZURE_SEARCH_SERVICE_NAME
output AZURE_SEARCH_SERVICE_ID string = solution.outputs.AZURE_SEARCH_SERVICE_ID
output AZURE_SEARCH_ENDPOINT string = solution.outputs.AZURE_SEARCH_ENDPOINT
output AZURE_SEARCH_INDEX_NAME string = solution.outputs.AZURE_SEARCH_INDEX_NAME
output AZURE_SEARCH_IDENTITY_PRINCIPAL_ID string = solution.outputs.AZURE_SEARCH_IDENTITY_PRINCIPAL_ID
output AZURE_KEY_VAULT_NAME string = solution.outputs.AZURE_KEY_VAULT_NAME
output AZURE_KEY_VAULT_ID string = solution.outputs.AZURE_KEY_VAULT_ID
output AZURE_KEY_VAULT_URI string = solution.outputs.AZURE_KEY_VAULT_URI
output AZURE_FOUNDRY_CMK_KEY_NAME string = solution.outputs.AZURE_FOUNDRY_CMK_KEY_NAME
output AZURE_FOUNDRY_CMK_KEY_VERSION string = solution.outputs.AZURE_FOUNDRY_CMK_KEY_VERSION
output AZURE_FOUNDRY_CMK_KEY_ID string = solution.outputs.AZURE_FOUNDRY_CMK_KEY_ID
output AZURE_FOUNDRY_CMK_IDENTITY_PRINCIPAL_ID string = solution.outputs.AZURE_FOUNDRY_CMK_IDENTITY_PRINCIPAL_ID
output AZURE_SEARCH_CMK_KEY_NAME string = solution.outputs.AZURE_SEARCH_CMK_KEY_NAME
output AZURE_SEARCH_CMK_KEY_VERSION string = solution.outputs.AZURE_SEARCH_CMK_KEY_VERSION
output AZURE_SEARCH_CMK_KEY_ID string = solution.outputs.AZURE_SEARCH_CMK_KEY_ID
output DEPLOYMENT_PRINCIPAL_OBJECT_ID string = solution.outputs.DEPLOYMENT_PRINCIPAL_OBJECT_ID
output RBAC_FOUNDRY_CMK_IDENTITY_ROLE_ID string = solution.outputs.RBAC_FOUNDRY_CMK_IDENTITY_ROLE_ID
output RBAC_SEARCH_CMK_IDENTITY_ROLE_ID string = solution.outputs.RBAC_SEARCH_CMK_IDENTITY_ROLE_ID
output RBAC_FOUNDRY_ACCOUNT_VAULT_ROLE_ID string = solution.outputs.RBAC_FOUNDRY_ACCOUNT_VAULT_ROLE_ID
output RBAC_FOUNDRY_PROJECT_VAULT_ROLE_ID string = solution.outputs.RBAC_FOUNDRY_PROJECT_VAULT_ROLE_ID
output RBAC_FOUNDRY_PROJECT_ACCOUNT_ROLE_ID string = solution.outputs.RBAC_FOUNDRY_PROJECT_ACCOUNT_ROLE_ID
output AZURE_CONTAINER_REGISTRY_RESOURCE_ID string = solution.outputs.AZURE_CONTAINER_REGISTRY_RESOURCE_ID
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = solution.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT
output AZURE_CONTAINER_REGISTRY_CONNECTION_NAME string = solution.outputs.AZURE_CONTAINER_REGISTRY_CONNECTION_NAME
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = solution.outputs.AZURE_AI_PROJECT_ACR_CONNECTION_NAME

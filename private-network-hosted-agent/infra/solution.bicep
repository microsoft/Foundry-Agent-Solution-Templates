targetScope = 'resourceGroup'

@description('Collision-safe azd environment name.')
@minLength(3)
@maxLength(32)
param environmentName string

@description('Foundry, VNet, and Key Vault location.')
param location string = resourceGroup().location

@description('Search location, independently configurable from the Foundry region.')
param searchLocation string = 'westus3'

@description('Object ID of the operator or CI identity used for deployment and Search bootstrap.')
param deploymentPrincipalObjectId string

@description('Optional invoke-only validation principal.')
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

@description('Optional full ARM resource ID of an enterprise-owned Azure Container Registry.')
param containerRegistryResourceId string = ''

@description('Optional exact login server of the enterprise-owned Azure Container Registry.')
param containerRegistryEndpoint string = ''

var sanitizedEnvironment = take(replace(toLower(environmentName), '-', ''), 10)
var uniqueSuffix = take(uniqueString(subscription().id, resourceGroup().id, environmentName), 6)
var resourcePrefix = 'fpha-${sanitizedEnvironment}-${uniqueSuffix}'
var compactPrefix = take('fpha${sanitizedEnvironment}${uniqueSuffix}', 20)
var hasContainerRegistryResourceId = !empty(trim(containerRegistryResourceId))
var hasContainerRegistryEndpoint = !empty(trim(containerRegistryEndpoint))
var containerRegistryInputsArePaired = hasContainerRegistryResourceId == hasContainerRegistryEndpoint
var containerRegistryResourceIdIsCanonical = containerRegistryResourceId == trim(containerRegistryResourceId) && startsWith(toLower(containerRegistryResourceId), '/subscriptions/') && contains(toLower(containerRegistryResourceId), '/resourcegroups/') && contains(toLower(containerRegistryResourceId), '/providers/microsoft.containerregistry/registries/')
var containerRegistryEndpointIsCanonical = containerRegistryEndpoint == trim(containerRegistryEndpoint) && containerRegistryEndpoint == toLower(containerRegistryEndpoint) && endsWith(containerRegistryEndpoint, '.azurecr.io') && !contains(containerRegistryEndpoint, '://') && !contains(containerRegistryEndpoint, '/')
var hasExistingContainerRegistry = containerRegistryInputsArePaired
  ? hasContainerRegistryResourceId
  : fail('AZURE_CONTAINER_REGISTRY_RESOURCE_ID and AZURE_CONTAINER_REGISTRY_ENDPOINT must be supplied together.')
var validatedContainerRegistryResourceId = !hasContainerRegistryResourceId || containerRegistryResourceIdIsCanonical
  ? containerRegistryResourceId
  : fail('AZURE_CONTAINER_REGISTRY_RESOURCE_ID must be a canonical Azure Container Registry ARM resource ID.')
var validatedContainerRegistryEndpoint = !hasContainerRegistryEndpoint || containerRegistryEndpointIsCanonical
  ? containerRegistryEndpoint
  : fail('AZURE_CONTAINER_REGISTRY_ENDPOINT must be a lowercase AzureCloud ACR login server without a scheme or path.')
var tags = {
  'azd-env-name': environmentName
  'solution-template': 'foundry-private-hosted-agent'
  'connectivity-mode': connectivityMode
}

module network './modules/network.bicep' = {
  name: '${resourcePrefix}-network'
  params: {
    name: resourcePrefix
    location: location
    tags: tags
    connectivityMode: connectivityMode
    p2sAddressPool: p2sAddressPool
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    firewallCreationRequired: firewallCreationRequired
    gatewaySubnetPrefix: gatewaySubnetPrefix
    dnsInboundSubnetPrefix: dnsInboundSubnetPrefix
  }
}

module privateDns './modules/private-dns.bicep' = {
  name: '${resourcePrefix}-private-dns'
  params: {
    tags: tags
  }
}

module privateDnsNetwork './modules/private-dns-network.bicep' = {
  name: '${resourcePrefix}-private-dns-network'
  params: {
    name: resourcePrefix
    location: location
    tags: tags
    vnetId: network.outputs.vnetId
    dnsInboundSubnetId: network.outputs.dnsInboundSubnetId
    dnsInboundIpAddress: dnsInboundIpAddress
    zoneNames: privateDns.outputs.zoneNames
  }
}

module connectivity './modules/connectivity.bicep' = {
  name: '${resourcePrefix}-connectivity'
  params: {
    name: resourcePrefix
    location: location
    tags: tags
    connectivityMode: connectivityMode
    vnetId: network.outputs.vnetId
    vnetName: network.outputs.vnetName
    gatewaySubnetId: network.outputs.gatewaySubnetId
    p2sAddressPool: p2sAddressPool
    p2sTenantId: p2sTenantId
    s2sGatewayIpAddress: s2sGatewayIpAddress
    s2sRemoteAddressPrefixes: s2sRemoteAddressPrefixes
    s2sEnableBgp: s2sEnableBgp
    s2sRemoteAsn: s2sRemoteAsn
    s2sBgpPeeringAddress: s2sBgpPeeringAddress
    s2sSharedKey: s2sSharedKey
    remoteVnetResourceId: remoteVnetResourceId
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: '${resourcePrefix}-key-vault'
  params: {
    name: take('kv-${sanitizedEnvironment}-${uniqueSuffix}', 24)
    identityName: '${resourcePrefix}-foundry-cmk'
    location: location
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDns.outputs.keyVaultZoneId
  }
}

module search './modules/search.bicep' = {
  name: '${resourcePrefix}-search'
  params: {
    name: take('srch-${sanitizedEnvironment}-${uniqueSuffix}', 60)
    location: searchLocation
    privateEndpointLocation: location
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDns.outputs.searchZoneId
    keyVaultName: keyVault.outputs.keyVaultName
    searchKeyName: keyVault.outputs.searchKeyName
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
  }
}

module foundry './modules/foundry.bicep' = {
  name: '${resourcePrefix}-foundry'
  params: {
    name: take('aif${compactPrefix}', 64)
    projectName: take('proj-${sanitizedEnvironment}-${uniqueSuffix}', 64)
    location: location
    tags: union(tags, {
      'azd-service-name': 'private-search-agent'
    })
    agentSubnetId: network.outputs.agentSubnetId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateDnsZoneIds: privateDns.outputs.foundryZoneIds
    foundryCmkIdentityId: keyVault.outputs.foundryCmkIdentityId
    foundryCmkIdentityClientId: keyVault.outputs.foundryCmkIdentityClientId
    keyVaultName: keyVault.outputs.keyVaultName
    foundryKeyName: keyVault.outputs.foundryKeyName
    foundryKeyVersion: keyVault.outputs.foundryKeyVersion
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    invocationTestPrincipalObjectId: invocationTestPrincipalObjectId
    modelName: modelName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
  }
}

module containerRegistryConnection './modules/container-registry-connection.bicep' = if (hasExistingContainerRegistry) {
  name: '${resourcePrefix}-acr-connection'
  params: {
    accountName: foundry.outputs.accountName
    projectName: foundry.outputs.projectName
    projectPrincipalId: foundry.outputs.projectPrincipalId
    connectionName: take('acr-${sanitizedEnvironment}-${uniqueSuffix}', 64)
    containerRegistryResourceId: validatedContainerRegistryResourceId
    containerRegistryEndpoint: validatedContainerRegistryEndpoint
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_LOCATION string = location
output AZURE_SEARCH_LOCATION string = searchLocation
output RESOURCE_PREFIX string = resourcePrefix
output CONNECTIVITY_MODE string = connectivityMode
output AZURE_VNET_ID string = network.outputs.vnetId
output AZURE_FIREWALL_ID string = network.outputs.firewallId
output AZURE_DNS_RESOLVER_INBOUND_IP string = privateDnsNetwork.outputs.inboundIpAddress
output AZURE_VPN_GATEWAY_NAME string = connectivity.outputs.vpnGatewayName
output AZURE_AI_ACCOUNT_NAME string = foundry.outputs.accountName
output AZURE_AI_ACCOUNT_ID string = foundry.outputs.accountId
output AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID string = foundry.outputs.accountPrincipalId
output AZURE_AI_PROJECT_NAME string = foundry.outputs.projectName
output AZURE_AI_PROJECT_ID string = foundry.outputs.projectId
output AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID string = foundry.outputs.projectPrincipalId
output FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output AZURE_AI_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = modelName
output AZURE_SEARCH_SERVICE_NAME string = search.outputs.searchServiceName
output AZURE_SEARCH_SERVICE_ID string = search.outputs.searchServiceId
output AZURE_SEARCH_ENDPOINT string = search.outputs.searchEndpoint
output AZURE_SEARCH_INDEX_NAME string = 'private-knowledge'
output AZURE_SEARCH_IDENTITY_PRINCIPAL_ID string = search.outputs.searchPrincipalId
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_KEY_VAULT_ID string = keyVault.outputs.keyVaultId
output AZURE_KEY_VAULT_URI string = keyVault.outputs.keyVaultUri
output AZURE_FOUNDRY_CMK_KEY_NAME string = keyVault.outputs.foundryKeyName
output AZURE_FOUNDRY_CMK_KEY_VERSION string = keyVault.outputs.foundryKeyVersion
output AZURE_FOUNDRY_CMK_KEY_ID string = keyVault.outputs.foundryKeyId
output AZURE_FOUNDRY_CMK_IDENTITY_PRINCIPAL_ID string = keyVault.outputs.foundryCmkIdentityPrincipalId
output AZURE_SEARCH_CMK_KEY_NAME string = keyVault.outputs.searchKeyName
output AZURE_SEARCH_CMK_KEY_VERSION string = keyVault.outputs.searchKeyVersion
output AZURE_SEARCH_CMK_KEY_ID string = keyVault.outputs.searchKeyId
output DEPLOYMENT_PRINCIPAL_OBJECT_ID string = deploymentPrincipalObjectId
output RBAC_FOUNDRY_CMK_IDENTITY_ROLE_ID string = keyVault.outputs.foundryKeyRoleId
output RBAC_SEARCH_CMK_IDENTITY_ROLE_ID string = search.outputs.searchKeyRoleId
output RBAC_FOUNDRY_ACCOUNT_VAULT_ROLE_ID string = foundry.outputs.accountKeyVaultRoleId
output RBAC_FOUNDRY_PROJECT_VAULT_ROLE_ID string = foundry.outputs.projectKeyVaultRoleId
output RBAC_FOUNDRY_PROJECT_ACCOUNT_ROLE_ID string = foundry.outputs.projectFoundryRoleId
output AZURE_CONTAINER_REGISTRY_RESOURCE_ID string = hasExistingContainerRegistry ? validatedContainerRegistryResourceId : ''
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = hasExistingContainerRegistry ? validatedContainerRegistryEndpoint : ''
output AZURE_CONTAINER_REGISTRY_CONNECTION_NAME string = hasExistingContainerRegistry ? containerRegistryConnection!.outputs.connectionName : ''
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = hasExistingContainerRegistry ? containerRegistryConnection!.outputs.connectionName : ''

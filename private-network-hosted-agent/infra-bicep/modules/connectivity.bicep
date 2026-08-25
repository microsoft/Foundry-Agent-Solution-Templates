targetScope = 'resourceGroup'

param name string
param location string
param tags object

@allowed([
  'pointToSite'
  'siteToSite'
  'vnetPeering'
])
param connectivityMode string

param vnetId string
param vnetName string
param gatewaySubnetId string
param p2sAddressPool string
param p2sTenantId string
param s2sGatewayIpAddress string
param s2sRemoteAddressPrefixes array
param s2sEnableBgp bool
param s2sRemoteAsn int
param s2sBgpPeeringAddress string

@secure()
param s2sSharedKey string

param remoteVnetResourceId string

var usesGateway = connectivityMode == 'pointToSite' || connectivityMode == 'siteToSite'
var isPointToSite = connectivityMode == 'pointToSite'
var isSiteToSite = connectivityMode == 'siteToSite'
var isPeering = connectivityMode == 'vnetPeering'
var gatewayName = 'vpng-${name}'

resource gatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (usesGateway) {
  name: 'pip-${name}-gateway'
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' = if (usesGateway) {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    enableBgp: isSiteToSite && s2sEnableBgp
    activeActive: false
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    sku: {
      name: 'VpnGw2AZ'
      tier: 'VpnGw2AZ'
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: gatewayPublicIp.id
          }
        }
      }
    ]
    vpnClientConfiguration: isPointToSite ? {
      vpnClientAddressPool: {
        addressPrefixes: [
          p2sAddressPool
        ]
      }
      vpnClientProtocols: [
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        'AAD'
      ]
      aadTenant: '${environment().authentication.loginEndpoint}${p2sTenantId}/'
      aadAudience: 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'
      aadIssuer: 'https://sts.windows.net/${p2sTenantId}/'
    } : null
  }
}

resource localGateway 'Microsoft.Network/localNetworkGateways@2024-07-01' = if (isSiteToSite) {
  name: 'lng-${name}'
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: s2sGatewayIpAddress
    localNetworkAddressSpace: {
      addressPrefixes: s2sRemoteAddressPrefixes
    }
    bgpSettings: s2sEnableBgp ? {
      asn: s2sRemoteAsn
      bgpPeeringAddress: s2sBgpPeeringAddress
      peerWeight: 0
    } : null
  }
}

resource s2sConnection 'Microsoft.Network/connections@2024-07-01' = if (isSiteToSite) {
  name: 'conn-${name}-s2s'
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: {
      id: vpnGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: localGateway.id
      properties: {}
    }
    sharedKey: s2sSharedKey
    enableBgp: s2sEnableBgp
    routingWeight: 0
  }
}

var effectiveRemoteVnetResourceId = isPeering
  ? remoteVnetResourceId
  : '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/unused'
var remoteVnetParts = split(effectiveRemoteVnetResourceId, '/')
var paddedRemoteVnetParts = concat(remoteVnetParts, [
  ''
  ''
  ''
  ''
  ''
  ''
  ''
  ''
  ''
])
var remoteVnetResourceIdHasCanonicalScope = empty(paddedRemoteVnetParts[0]) && toLower(paddedRemoteVnetParts[1]) == 'subscriptions' && !empty(paddedRemoteVnetParts[2]) && toLower(paddedRemoteVnetParts[3]) == 'resourcegroups' && !empty(paddedRemoteVnetParts[4])
var remoteVnetResourceIdHasCanonicalProviderPath = toLower(paddedRemoteVnetParts[5]) == 'providers' && toLower(paddedRemoteVnetParts[6]) == 'microsoft.network' && toLower(paddedRemoteVnetParts[7]) == 'virtualnetworks' && !empty(paddedRemoteVnetParts[8])
var remoteVnetResourceIdIsCanonical = effectiveRemoteVnetResourceId == trim(effectiveRemoteVnetResourceId) && length(remoteVnetParts) == 9 && remoteVnetResourceIdHasCanonicalScope && remoteVnetResourceIdHasCanonicalProviderPath
var validatedRemoteVnetResourceId = !isPeering || remoteVnetResourceIdIsCanonical
  ? effectiveRemoteVnetResourceId
  : fail('REMOTE_VNET_RESOURCE_ID must be a canonical virtual network ARM resource ID.')
var validatedRemoteVnetParts = split(validatedRemoteVnetResourceId, '/')
var remoteSubscriptionId = validatedRemoteVnetParts[2]
var remoteResourceGroupName = validatedRemoteVnetParts[4]
var remoteVnetName = last(validatedRemoteVnetParts)

resource localVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
}

resource localToRemote 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = if (isPeering) {
  parent: localVnet
  name: 'to-${remoteVnetName}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: validatedRemoteVnetResourceId
    }
  }
}

module remoteToLocal './remote-peering.bicep' = if (isPeering) {
  name: '${name}-remote-peering'
  scope: resourceGroup(remoteSubscriptionId, remoteResourceGroupName)
  params: {
    name: 'to-${vnetName}'
    remoteVnetName: remoteVnetName
    localVnetId: vnetId
  }
}

output vpnGatewayName string = usesGateway ? vpnGateway.name : ''
output connectivityResourceIds array = concat(
  usesGateway ? [
    vpnGateway.id
  ] : [],
  isSiteToSite ? [
    localGateway.id
    s2sConnection.id
  ] : [],
  isPeering ? [
    localToRemote.id
    remoteToLocal!.outputs.id
  ] : []
)

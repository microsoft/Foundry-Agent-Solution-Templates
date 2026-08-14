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
param p2sAddressPool string

param vnetAddressPrefix string
param agentSubnetPrefix string
param privateEndpointSubnetPrefix string
param firewallSubnetPrefix string
param firewallCreationRequired bool
param gatewaySubnetPrefix string
param dnsInboundSubnetPrefix string

var usesGateway = connectivityMode == 'pointToSite' || connectivityMode == 'siteToSite'
var loginHost = replace(replace(environment().authentication.loginEndpoint, 'https://', ''), '/', '')
var firewallPolicyName = 'afwp-${name}'

@onlyIfNotExists()
resource agentNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-${name}-agent'
  location: location
  tags: tags
  properties: {}
}

resource agentVnetRule 'Microsoft.Network/networkSecurityGroups/securityRules@2024-07-01' = {
  parent: agentNsg
  name: 'AllowVnetInbound'
  properties: {
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: 'VirtualNetwork'
  }
}

@onlyIfNotExists()
resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-${name}-private-endpoints'
  location: location
  tags: tags
  properties: {}
}

resource privateEndpointP2sRule 'Microsoft.Network/networkSecurityGroups/securityRules@2024-07-01' = if (connectivityMode == 'pointToSite') {
  parent: privateEndpointNsg
  name: 'AllowPointToSitePrivateHttps'
  properties: {
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: p2sAddressPool
    destinationAddressPrefix: privateEndpointSubnetPrefix
  }
  dependsOn: [
    privateEndpointDenyInboundRule
  ]
}

resource privateEndpointVnetRule 'Microsoft.Network/networkSecurityGroups/securityRules@2024-07-01' = {
  parent: privateEndpointNsg
  name: 'AllowApprovedPrivateHttps'
  properties: {
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: privateEndpointSubnetPrefix
  }
}

resource privateEndpointDenyInboundRule 'Microsoft.Network/networkSecurityGroups/securityRules@2024-07-01' = {
  parent: privateEndpointNsg
  name: 'DenyOtherPrivateEndpointInbound'
  properties: {
    priority: 120
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: privateEndpointSubnetPrefix
  }
  dependsOn: [
    privateEndpointVnetRule
  ]
}

module firewallBase './firewall-base.bicep' = {
  name: '${name}-firewall-base'
  params: {
    name: name
    location: location
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    firewallPolicyName: firewallPolicyName
  }
}

module firewallCreation './firewall-create.bicep' = if (firewallCreationRequired) {
  name: '${name}-firewall-create'
  params: {
    name: name
    location: location
    tags: tags
    vnetName: firewallBase.outputs.vnetName
    firewallPublicIpName: firewallBase.outputs.firewallPublicIpName
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-07-01' existing = {
  name: firewallPolicyName
}

resource firewallRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-07-01' = {
  parent: firewallPolicy
  name: 'agent-egress'
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'allow-entra'
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'allow-entra-https'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              agentSubnetPrefix
            ]
            destinationAddresses: [
              'AzureActiveDirectory'
            ]
            destinationPorts: [
              '443'
            ]
          }
        ]
      }
      {
        name: 'allow-hosted-agent-source-runtime'
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'documented-source-runtime-dependencies'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              agentSubnetPrefix
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'mcr.microsoft.com'
              '*.login.microsoft.com'
              '*.${loginHost}'
            ]
            terminateTLS: false
          }
        ]
      }
    ]
  }
  dependsOn: [
    firewallBase
  ]
}

resource routeTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: 'rt-${name}-agent'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

module vnetConfiguration './vnet-configuration.bicep' = {
  name: '${name}-vnet-configuration'
  params: {
    name: name
    location: location
    tags: tags
    usesGateway: usesGateway
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    gatewaySubnetPrefix: gatewaySubnetPrefix
    dnsInboundSubnetPrefix: dnsInboundSubnetPrefix
    agentNsgId: agentNsg.id
    privateEndpointNsgId: privateEndpointNsg.id
    routeTableId: routeTable.id
  }
  dependsOn: [
    firewallBase
    firewallCreation
  ]
}

module firewallPolicyAttachment './firewall-policy-attachment.bicep' = {
  name: '${name}-firewall-policy'
  params: {
    name: name
    location: location
    tags: tags
    vnetName: vnetConfiguration.outputs.vnetName
    firewallPublicIpName: firewallBase.outputs.firewallPublicIpName
    firewallPolicyName: firewallBase.outputs.firewallPolicyName
  }
  dependsOn: [
    firewallCreation
    firewallRules
  ]
}

resource defaultRoute 'Microsoft.Network/routeTables/routes@2024-07-01' = {
  parent: routeTable
  name: 'default-via-firewall'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: firewallPolicyAttachment.outputs.firewallPrivateIp
  }
}

output vnetId string = vnetConfiguration.outputs.vnetId
output vnetName string = vnetConfiguration.outputs.vnetName
output agentSubnetId string = vnetConfiguration.outputs.agentSubnetId
output privateEndpointSubnetId string = vnetConfiguration.outputs.privateEndpointSubnetId
output dnsInboundSubnetId string = vnetConfiguration.outputs.dnsInboundSubnetId
output gatewaySubnetId string = vnetConfiguration.outputs.gatewaySubnetId
output firewallId string = firewallPolicyAttachment.outputs.firewallId
output firewallPrivateIp string = firewallPolicyAttachment.outputs.firewallPrivateIp

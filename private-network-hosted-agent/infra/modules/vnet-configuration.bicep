targetScope = 'resourceGroup'

param name string
param location string
param tags object
param usesGateway bool
param vnetAddressPrefix string
param agentSubnetPrefix string
param privateEndpointSubnetPrefix string
param firewallSubnetPrefix string
param gatewaySubnetPrefix string
param dnsInboundSubnetPrefix string
param agentNsgId string
param privateEndpointNsgId string
param routeTableId string

var vnetName = 'vnet-${name}'
var agentSubnetName = 'snet-agent'
var privateEndpointSubnetName = 'snet-private-endpoints'
var firewallSubnetName = 'AzureFirewallSubnet'
var gatewaySubnetName = 'GatewaySubnet'
var dnsInboundSubnetName = 'snet-dns-inbound'

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: concat([
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnetPrefix
          networkSecurityGroup: {
            id: agentNsgId
          }
          routeTable: {
            id: routeTableId
          }
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointNsgId
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: firewallSubnetName
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
      {
        name: dnsInboundSubnetName
        properties: {
          addressPrefix: dnsInboundSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ], usesGateway ? [
      {
        name: gatewaySubnetName
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
    ] : [])
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output agentSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, agentSubnetName)
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
output dnsInboundSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, dnsInboundSubnetName)
output gatewaySubnetId string = usesGateway ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, gatewaySubnetName) : ''

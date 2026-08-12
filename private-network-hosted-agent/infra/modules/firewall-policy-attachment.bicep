targetScope = 'resourceGroup'

param name string
param location string
param tags object
param vnetName string
param firewallPublicIpName string
param firewallPolicyName string

var firewallSubnetName = 'AzureFirewallSubnet'

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'afw-${name}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    firewallPolicy: {
      id: resourceId('Microsoft.Network/firewallPolicies', firewallPolicyName)
    }
    ipConfigurations: [
      {
        name: 'configuration'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, firewallSubnetName)
          }
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', firewallPublicIpName)
          }
        }
      }
    ]
  }
}

output firewallId string = firewall.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress

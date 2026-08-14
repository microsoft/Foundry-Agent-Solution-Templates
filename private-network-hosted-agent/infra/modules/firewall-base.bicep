targetScope = 'resourceGroup'

param name string
param location string
param tags object
param vnetAddressPrefix string
param firewallSubnetPrefix string
param firewallPolicyName string

var vnetName = 'vnet-${name}'
var firewallSubnetName = 'AzureFirewallSubnet'
var firewallPublicIpName = 'pip-${name}-firewall'

@onlyIfNotExists()
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: firewallSubnetName
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
    ]
  }
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: firewallPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    dnsSettings: {
      enableProxy: false
    }
  }
}

output firewallPolicyName string = firewallPolicy.name
output firewallPublicIpName string = firewallPublicIp.name
output vnetName string = vnet.name

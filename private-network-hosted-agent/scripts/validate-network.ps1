param(
    [switch]$RequirePrivateResolution,
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"

function Get-ArmResource {
    param(
        [string]$ResourceId,
        [string]$ApiVersion
    )

    $json = az resource show `
        --ids $ResourceId `
        --api-version $ApiVersion `
        --output json `
        --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "Unable to read Azure resource '$ResourceId'."
    }
    return $json | ConvertFrom-Json
}

function Assert-ExactValues {
    param(
        [object[]]$Actual,
        [object[]]$Expected,
        [string]$Label
    )

    $difference = @(Compare-Object `
        -ReferenceObject @($Expected | ForEach-Object { [string]$_ } | Sort-Object) `
        -DifferenceObject @($Actual | ForEach-Object { [string]$_ } | Sort-Object))
    if ($difference.Count -gt 0) {
        throw "$Label does not match the fail-closed network contract."
    }
}

function Assert-ManagedInboundNsgRule {
    param(
        [object[]]$Rules,
        [string]$Name,
        [int]$Priority,
        [string]$Access,
        [string]$Protocol,
        [string]$SourceAddressPrefix,
        [string]$DestinationAddressPrefix,
        [string]$DestinationPortRange
    )

    $matches = @($Rules | Where-Object { $_.name -eq $Name })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one template-managed NSG rule '$Name'."
    }
    $properties = $matches[0].properties
    if ($properties.priority -ne $Priority -or
        $properties.direction -ne 'Inbound' -or
        $properties.access -ne $Access -or
        $properties.protocol -ne $Protocol -or
        $properties.sourcePortRange -ne '*' -or
        $properties.destinationPortRange -ne $DestinationPortRange -or
        $properties.sourceAddressPrefix -ne $SourceAddressPrefix -or
        $properties.destinationAddressPrefix -ne $DestinationAddressPrefix) {
        throw "Template-managed NSG rule '$Name' does not match the private endpoint ingress contract."
    }
}

$values = Get-AzdValues -EnvironmentName $EnvironmentName
$resourceGroup = Require-Value $values 'AZURE_RESOURCE_GROUP'
$foundry = Require-Value $values 'AZURE_AI_ACCOUNT_NAME'
$search = Require-Value $values 'AZURE_SEARCH_SERVICE_NAME'
$vault = Require-Value $values 'AZURE_KEY_VAULT_NAME'
$foundryId = Require-Value $values 'AZURE_AI_ACCOUNT_ID'
$searchId = Require-Value $values 'AZURE_SEARCH_SERVICE_ID'
$vaultId = Require-Value $values 'AZURE_KEY_VAULT_ID'
$vnetId = Require-Value $values 'AZURE_VNET_ID'
$firewallId = Require-Value $values 'AZURE_FIREWALL_ID'
$agentSubnetPrefix = Require-Value $values 'AGENT_SUBNET_PREFIX'
$privateEndpointSubnetPrefix = Require-Value $values 'PRIVATE_ENDPOINT_SUBNET_PREFIX'
$p2sAddressPool = Require-Value $values 'P2S_ADDRESS_POOL'
$connectivityMode = Require-Value $values 'CONNECTIVITY_MODE'
$containerRegistryEndpoint = Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_ENDPOINT'

$foundryPna = az cognitiveservices account show -g $resourceGroup -n $foundry `
    --query properties.publicNetworkAccess -o tsv
$searchPna = az search service show -g $resourceGroup -n $search `
    --query publicNetworkAccess -o tsv
$vaultPna = az keyvault show -g $resourceGroup -n $vault `
    --query properties.publicNetworkAccess -o tsv

foreach ($entry in @{
    Foundry = $foundryPna
    Search = $searchPna
    KeyVault = $vaultPna
}.GetEnumerator()) {
    if ($entry.Value.ToLowerInvariant() -ne 'disabled') {
        throw "$($entry.Key) public network access is '$($entry.Value)'."
    }
}

$privateEndpoints = @(az network private-endpoint list -g $resourceGroup |
    ConvertFrom-Json)
foreach ($targetId in @($foundryId, $searchId, $vaultId)) {
    $matches = @($privateEndpoints | Where-Object {
        $_.privateLinkServiceConnections[0].privateLinkServiceId -eq $targetId
    })
    if ($matches.Count -ne 1) {
        throw "Expected one private endpoint for '$targetId'; found $($matches.Count)."
    }
    $state = $matches[0].privateLinkServiceConnections[0].privateLinkServiceConnectionState.status
    if ($state -ne 'Approved') {
        throw "Private endpoint '$($matches[0].name)' is '$state'."
    }
}

$privateEndpointSubnet = Get-ArmResource `
    -ResourceId "$($vnetId.TrimEnd('/'))/subnets/snet-private-endpoints" `
    -ApiVersion '2024-07-01'
$privateEndpointNsgId = [string]$privateEndpointSubnet.properties.networkSecurityGroup.id
if ([string]::IsNullOrWhiteSpace($privateEndpointNsgId)) {
    throw 'The private endpoint subnet is not associated with a network security group.'
}
$privateEndpointNsg = Get-ArmResource `
    -ResourceId $privateEndpointNsgId `
    -ApiVersion '2024-07-01'
$privateEndpointRules = @($privateEndpointNsg.properties.securityRules)
Assert-ManagedInboundNsgRule `
    -Rules $privateEndpointRules `
    -Name 'AllowApprovedPrivateHttps' `
    -Priority 110 `
    -Access 'Allow' `
    -Protocol 'Tcp' `
    -SourceAddressPrefix 'VirtualNetwork' `
    -DestinationAddressPrefix $privateEndpointSubnetPrefix `
    -DestinationPortRange '443'
Assert-ManagedInboundNsgRule `
    -Rules $privateEndpointRules `
    -Name 'DenyOtherPrivateEndpointInbound' `
    -Priority 120 `
    -Access 'Deny' `
    -Protocol '*' `
    -SourceAddressPrefix '*' `
    -DestinationAddressPrefix $privateEndpointSubnetPrefix `
    -DestinationPortRange '*'
$p2sRules = @($privateEndpointRules | Where-Object {
    $_.name -eq 'AllowPointToSitePrivateHttps'
})
if ($connectivityMode -eq 'pointToSite') {
    Assert-ManagedInboundNsgRule `
        -Rules $privateEndpointRules `
        -Name 'AllowPointToSitePrivateHttps' `
        -Priority 100 `
        -Access 'Allow' `
        -Protocol 'Tcp' `
        -SourceAddressPrefix $p2sAddressPool `
        -DestinationAddressPrefix $privateEndpointSubnetPrefix `
        -DestinationPortRange '443'
}
elseif ($p2sRules.Count -ne 0) {
    throw 'The point-to-site private endpoint NSG rule exists outside pointToSite mode.'
}

$agentSubnet = Get-ArmResource `
    -ResourceId "$($vnetId.TrimEnd('/'))/subnets/snet-agent" `
    -ApiVersion '2024-07-01'
$routeTableId = [string]$agentSubnet.properties.routeTable.id
if ([string]::IsNullOrWhiteSpace($routeTableId)) {
    throw 'The Agent subnet is not associated with a route table.'
}
$routeTable = Get-ArmResource -ResourceId $routeTableId -ApiVersion '2024-07-01'
$routes = @($routeTable.properties.routes)
if ($routes.Count -ne 1 -or $routes[0].name -ne 'default-via-firewall') {
    throw 'The Agent route table must contain only default-via-firewall.'
}

$firewall = Get-ArmResource -ResourceId $firewallId -ApiVersion '2024-07-01'
$firewallPrivateIp = [string]$firewall.properties.ipConfigurations[0].properties.privateIPAddress
$firewallPolicyId = [string]$firewall.properties.firewallPolicy.id
if ([string]::IsNullOrWhiteSpace($firewallPrivateIp) -or
    [string]::IsNullOrWhiteSpace($firewallPolicyId)) {
    throw 'Azure Firewall does not expose its expected private IP and policy.'
}
$defaultRoute = $routes[0].properties
if ($defaultRoute.addressPrefix -ne '0.0.0.0/0' -or
    $defaultRoute.nextHopType -ne 'VirtualAppliance' -or
    $defaultRoute.nextHopIpAddress -ne $firewallPrivateIp) {
    throw 'The Agent default route does not point to Azure Firewall.'
}

$firewallPolicy = Get-ArmResource `
    -ResourceId $firewallPolicyId `
    -ApiVersion '2024-07-01'
$enableProxyProperty = $firewallPolicy.properties.dnsSettings.PSObject.Properties['enableProxy']
$dnsProxyEnabled = $null -ne $enableProxyProperty -and $enableProxyProperty.Value -eq $true
$basePolicyProperty = $firewallPolicy.properties.PSObject.Properties['basePolicy']
$hasBasePolicy = $null -ne $basePolicyProperty -and
    $null -ne $basePolicyProperty.Value -and
    -not [string]::IsNullOrWhiteSpace([string]$basePolicyProperty.Value.id)
$childPolicies = @($firewallPolicy.properties.childPolicies)
if ($firewallPolicy.properties.sku.tier -ne 'Standard' -or
    $firewallPolicy.properties.threatIntelMode -ne 'Alert' -or
    $dnsProxyEnabled -or
    $hasBasePolicy -or
    $childPolicies.Count -ne 0) {
    throw 'Azure Firewall Policy does not match the expected security baseline.'
}
$policyRuleGroups = @($firewallPolicy.properties.ruleCollectionGroups)
if ($policyRuleGroups.Count -ne 1 -or
    $policyRuleGroups[0].id.TrimEnd('/').ToLowerInvariant() -ne
        "$($firewallPolicyId.TrimEnd('/'))/ruleCollectionGroups/agent-egress".ToLowerInvariant()) {
    throw 'Azure Firewall Policy has an unexpected rule-collection group.'
}
$ruleGroup = Get-ArmResource `
    -ResourceId "$($firewallPolicyId.TrimEnd('/'))/ruleCollectionGroups/agent-egress" `
    -ApiVersion '2024-07-01'
$collections = @($ruleGroup.properties.ruleCollections)
Assert-ExactValues `
    -Actual @($collections.name) `
    -Expected @('allow-entra', 'allow-hosted-agent-source-runtime') `
    -Label 'Azure Firewall rule collections'

$entraCollection = @($collections | Where-Object { $_.name -eq 'allow-entra' })[0]
$entraRules = @($entraCollection.rules)
if ($entraCollection.priority -ne 100 -or
    $entraCollection.action.type -ne 'Allow' -or
    $entraRules.Count -ne 1 -or
    $entraRules[0].name -ne 'allow-entra-https' -or
    $entraRules[0].ruleType -ne 'NetworkRule') {
    throw 'The Entra firewall collection does not match the expected structure.'
}
Assert-ExactValues -Actual @($entraRules[0].sourceAddresses) -Expected @($agentSubnetPrefix) -Label 'Entra rule sources'
Assert-ExactValues -Actual @($entraRules[0].destinationAddresses) -Expected @('AzureActiveDirectory') -Label 'Entra rule destinations'
Assert-ExactValues -Actual @($entraRules[0].destinationPorts) -Expected @('443') -Label 'Entra rule ports'
Assert-ExactValues -Actual @($entraRules[0].ipProtocols) -Expected @('TCP') -Label 'Entra rule protocols'

$runtimeCollection = @(
    $collections | Where-Object { $_.name -eq 'allow-hosted-agent-source-runtime' }
)[0]
$runtimeRules = @($runtimeCollection.rules)
if ($runtimeCollection.priority -ne 200 -or
    $runtimeCollection.action.type -ne 'Allow' -or
    $runtimeRules.Count -ne 1 -or
    $runtimeRules[0].name -ne 'documented-source-runtime-dependencies' -or
    $runtimeRules[0].ruleType -ne 'ApplicationRule' -or
    $runtimeRules[0].terminateTLS -ne $false) {
    throw 'The Hosted Agent runtime firewall collection does not match the expected structure.'
}
$activeDirectoryEndpoint = az cloud show --query endpoints.activeDirectory --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($activeDirectoryEndpoint)) {
    throw 'Unable to resolve the active Azure cloud authentication endpoint.'
}
$loginHost = ([Uri]$activeDirectoryEndpoint).Host
Assert-ExactValues -Actual @($runtimeRules[0].sourceAddresses) -Expected @($agentSubnetPrefix) -Label 'Runtime rule sources'
Assert-ExactValues `
    -Actual @($runtimeRules[0].targetFqdns) `
    -Expected @('mcr.microsoft.com', '*.login.microsoft.com', "*.$loginHost") `
    -Label 'Runtime rule FQDNs'
$protocols = @($runtimeRules[0].protocols)
if ($protocols.Count -ne 1 -or
    $protocols[0].protocolType -ne 'Https' -or
    $protocols[0].port -ne 443) {
    throw 'The Hosted Agent runtime firewall protocol is not HTTPS/443.'
}

if ($RequirePrivateResolution) {
    $hostnames = @(
        "$foundry.services.ai.azure.com",
        "$search.search.windows.net",
        "$vault.vault.azure.net",
        $containerRegistryEndpoint
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
    foreach ($hostname in $hostnames) {
        $addresses = @(Resolve-DnsName $hostname -Type A -ErrorAction Stop |
            ForEach-Object {
                $addressProperty = $_.PSObject.Properties['IPAddress']
                if ($null -ne $addressProperty) {
                    $addressProperty.Value
                }
            })
        Assert-OnlyPrivateIPv4Addresses -Addresses $addresses -Hostname $hostname
    }
}

Write-Host '[OK] Public access, private endpoints, and fail-closed Agent egress are validated.'

Set-StrictMode -Version Latest

function Test-IPv4Literal {
    param([string]$Value)

    $address = [Net.IPAddress]::None
    return [Net.IPAddress]::TryParse($Value, [ref]$address) -and
        $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
}

function Test-IPv4Cidr {
    param([string]$Value)

    if ($Value -notmatch '^(?<address>[^/]+)/(?<prefix>[0-9]{1,2})$') {
        return $false
    }
    return (Test-IPv4Literal -Value $Matches.address) -and
        [int]$Matches.prefix -le 32
}

function Test-CanonicalVirtualNetworkResourceId {
    param([string]$Value)

    return $Value -match
        '(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+$'
}

function New-DeploymentEnvironmentName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'ExistingPrivateAcr')]
        [string]$DeploymentMode
    )

    $modeToken = if ($DeploymentMode -eq 'Source') { 'src' } else { 'acr' }
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 6)
    return "fpha-$modeToken-$suffix"
}

function Assert-DeploymentInputs {
    param(
        [string]$DeploymentMode,
        [string]$SubscriptionId,
        [string]$EnvironmentName,
        [string]$ContainerRegistryResourceId,
        [string]$ContainerRegistryEndpoint,
        [string]$ContainerImage,
        [string]$ConnectivityMode,
        [string]$RemoteVnetResourceId,
        [string]$S2sGatewayIpAddress,
        [string[]]$S2sRemoteAddressPrefixes,
        [switch]$S2sEnableBgp,
        [string]$S2sBgpPeeringAddress,
        [switch]$NoPrompt
    )

    if ([string]::IsNullOrWhiteSpace($DeploymentMode)) {
        if ($NoPrompt) {
            throw 'DeploymentMode is required when -NoPrompt is used.'
        }
        return
    }
    if ($DeploymentMode -notin @('Source', 'ExistingPrivateAcr')) {
        throw "DeploymentMode '$DeploymentMode' is unsupported."
    }
    $subscriptionGuid = [Guid]::Empty
    if (-not [Guid]::TryParse($SubscriptionId, [ref]$subscriptionGuid)) {
        throw 'SubscriptionId must be a GUID.'
    }
    if ($EnvironmentName -and
        $EnvironmentName -notmatch '^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$') {
        throw 'EnvironmentName must be 3-32 lowercase letters, digits, or hyphens and must start and end with a letter or digit.'
    }
    if ($ConnectivityMode -notin @('pointToSite', 'siteToSite', 'vnetPeering')) {
        throw "ConnectivityMode '$ConnectivityMode' is unsupported."
    }
    if ($ConnectivityMode -eq 'vnetPeering' -and
        -not (Test-CanonicalVirtualNetworkResourceId -Value $RemoteVnetResourceId)) {
        throw 'RemoteVnetResourceId must be a canonical virtual network ARM resource ID for vnetPeering.'
    }
    if ($ConnectivityMode -eq 'siteToSite') {
        if ([string]::IsNullOrWhiteSpace($env:S2S_SHARED_KEY)) {
            throw 'Set S2S_SHARED_KEY only in the current process before using siteToSite.'
        }
        if (-not (Test-IPv4Literal -Value $S2sGatewayIpAddress)) {
            throw 'S2sGatewayIpAddress must be the customer VPN gateway IPv4 address.'
        }
        $remotePrefixes = @($S2sRemoteAddressPrefixes | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        })
        if ($remotePrefixes.Count -eq 0 -or
            @($remotePrefixes | Where-Object { -not (Test-IPv4Cidr -Value $_) }).Count -gt 0) {
            throw 'S2sRemoteAddressPrefixes must contain at least one valid IPv4 CIDR.'
        }
        if ($S2sEnableBgp -and
            -not (Test-IPv4Literal -Value $S2sBgpPeeringAddress)) {
            throw 'S2sBgpPeeringAddress must be a valid IPv4 address when BGP is enabled.'
        }
    }

    $acrValues = @(
        $ContainerRegistryResourceId,
        $ContainerRegistryEndpoint,
        $ContainerImage
    )
    $acrValueCount = @($acrValues | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }).Count
    if ($DeploymentMode -eq 'Source') {
        if ($acrValueCount -gt 0) {
            throw 'Source mode does not accept existing ACR inputs.'
        }
        return
    }
    if ($acrValueCount -ne 3) {
        throw 'ExistingPrivateAcr requires ContainerRegistryResourceId, ContainerRegistryEndpoint, and ContainerImage together.'
    }
    if ($ContainerRegistryResourceId -notmatch
        '(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\.ContainerRegistry/registries/[a-z0-9]+$') {
        throw 'ContainerRegistryResourceId must be a canonical ACR ARM resource ID.'
    }
    if ($ContainerRegistryEndpoint -cnotmatch '^[a-z0-9-]+\.azurecr\.io$') {
        throw 'ContainerRegistryEndpoint must be the exact lowercase AzureCloud ACR login server.'
    }
    if ($ContainerImage -cnotmatch
        '^[a-z0-9-]+\.azurecr\.io/[a-z0-9]+(?:[._/-][a-z0-9]+)*@sha256:[a-f0-9]{64}$') {
        throw 'ContainerImage must be a lowercase ACR image reference pinned by sha256 digest.'
    }
    if (-not $ContainerImage.StartsWith(
        "$ContainerRegistryEndpoint/",
        [StringComparison]::Ordinal
    )) {
        throw 'ContainerImage host must exactly match ContainerRegistryEndpoint.'
    }
}

function Get-GeneratedResourceGroupName {
    param([Parameter(Mandatory)][string]$EnvironmentName)
    return "rg-$EnvironmentName"
}

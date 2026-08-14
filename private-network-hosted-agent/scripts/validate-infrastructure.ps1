param([string]$EnvironmentName = '')

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName
$resourceGroup = Require-Value $values 'AZURE_RESOURCE_GROUP'
$environmentName = Require-Value $values 'AZURE_ENV_NAME'

$owned = @(az resource list --resource-group $resourceGroup | ConvertFrom-Json |
    Where-Object {
        $null -ne $_.tags -and
        $null -ne $_.tags.PSObject.Properties['azd-env-name'] -and
        $_.tags.'azd-env-name' -eq $environmentName
    })
if ($owned.Count -eq 0) {
    throw "No resources tagged for azd environment '$environmentName' were found."
}

$failed = @($owned | Where-Object {
    $null -ne $_.properties -and
    $null -ne $_.properties.PSObject.Properties['provisioningState'] -and
    $_.properties.provisioningState -ne 'Succeeded'
})
if ($failed.Count -gt 0) {
    throw "Resources are not ready: $($failed | ConvertTo-Json -Compress)"
}

$requiredTypes = @(
    'Microsoft.Network/virtualNetworks',
    'Microsoft.Network/azureFirewalls',
    'Microsoft.CognitiveServices/accounts',
    'Microsoft.CognitiveServices/accounts/projects',
    'Microsoft.Search/searchServices',
    'Microsoft.KeyVault/vaults'
)
$ownedTypes = @($owned | ForEach-Object { $_.type.ToLowerInvariant() })
foreach ($type in $requiredTypes) {
    if ($type.ToLowerInvariant() -notin $ownedTypes) {
        throw "Required repository-owned resource type '$type' was not found."
    }
}

$disallowed = @($owned | Where-Object {
    $_.type -in @(
        'microsoft.insights/components',
        'microsoft.operationalinsights/workspaces',
        'microsoft.containerregistry/registries'
    )
})
if ($disallowed.Count -gt 0) {
    throw "Disallowed template-owned resources exist: $($disallowed.id -join ', ')"
}
Write-Host '[OK] Repository-owned resources are provisioned and no disallowed service was introduced.'

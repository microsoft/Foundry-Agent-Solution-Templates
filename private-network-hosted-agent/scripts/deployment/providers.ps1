Set-StrictMode -Version Latest

function Get-RequiredProviderNamespaces {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'ExistingPrivateAcr')]
        [string]$DeploymentMode
    )

    $providers = @(
        'Microsoft.CognitiveServices',
        'Microsoft.Search',
        'Microsoft.Network',
        'Microsoft.KeyVault',
        'Microsoft.ManagedIdentity',
        'Microsoft.App'
    )
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        $providers += 'Microsoft.ContainerRegistry'
    }
    return $providers
}

function Get-AzureSearchProviderRecord {
    param([Parameter(Mandatory)][string]$SubscriptionId)

    $result = Invoke-CheckedCommand `
        -Stage 'Inspect Microsoft.Search provider and regional availability' `
        -FilePath 'az' `
        -Arguments @(
            'provider', 'show', '--subscription', $SubscriptionId,
            '--namespace', 'Microsoft.Search',
            '--query',
            "{namespace:namespace,registrationState:registrationState,searchLocations:resourceTypes[?resourceType=='searchServices'].locations | [0]}",
            '--output', 'json'
        ) `
        -Quiet
    return $result.Output -join "`n" | ConvertFrom-Json
}

function Get-AzureProviderValidation {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'ExistingPrivateAcr')]
        [string]$DeploymentMode
    )

    $requiredProviders = @(Get-RequiredProviderNamespaces -DeploymentMode $DeploymentMode)
    $listedProviders = @(
        $requiredProviders | Where-Object { $_ -ne 'Microsoft.Search' }
    ) + 'Microsoft.Quota'
    $filter = ($listedProviders | ForEach-Object {
        "namespace=='$_'"
    }) -join ' || '
    $listResult = Invoke-CheckedCommand `
        -Stage 'Inspect required Azure provider registrations' `
        -FilePath 'az' `
        -Arguments @(
            'provider', 'list', '--subscription', $SubscriptionId,
            '--query',
            "[?$filter].{namespace:namespace,registrationState:registrationState}",
            '--output', 'json'
        ) `
        -Quiet
    $listedRecords = @($listResult.Output -join "`n" | ConvertFrom-Json)
    $searchRecord = Get-AzureSearchProviderRecord -SubscriptionId $SubscriptionId

    $providerRecords = foreach ($namespace in $requiredProviders) {
        $record = if ($namespace -eq 'Microsoft.Search') {
            $searchRecord
        }
        else {
            $listedRecords |
                Where-Object { $_.namespace -eq $namespace } |
                Select-Object -First 1
        }
        [pscustomobject]@{
            namespace = $namespace
            registrationState = if ($null -eq $record) {
                'NotRegistered'
            }
            else {
                [string]$record.registrationState
            }
        }
    }
    $quotaRecord = $listedRecords |
        Where-Object { $_.namespace -eq 'Microsoft.Quota' } |
        Select-Object -First 1

    return [pscustomobject]@{
        deploymentMode = $DeploymentMode
        requiredProviders = $requiredProviders
        providerRegistrations = @($providerRecords)
        quotaProviderState = if ($null -eq $quotaRecord) {
            'NotRegistered'
        }
        else {
            [string]$quotaRecord.registrationState
        }
        searchLocations = @($searchRecord.searchLocations)
    }
}

function Assert-AzureProviderValidation {
    param(
        [Parameter(Mandatory)][object]$Validation,
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'ExistingPrivateAcr')]
        [string]$DeploymentMode,
        [switch]$QuietSuccess
    )

    $expectedProviders = @(Get-RequiredProviderNamespaces -DeploymentMode $DeploymentMode)
    $validatedProviders = @($Validation.requiredProviders)
    $expectedSignature = ($expectedProviders | Sort-Object) -join "`n"
    $validatedSignature = ($validatedProviders | Sort-Object) -join "`n"
    if ($expectedSignature -ne $validatedSignature) {
        throw "Provider validation does not match deployment mode '$DeploymentMode'."
    }
    foreach ($namespace in $expectedProviders) {
        $record = @($Validation.providerRegistrations |
            Where-Object { $_.namespace -eq $namespace })
        if ($record.Count -ne 1 -or $record[0].registrationState -ne 'Registered') {
            $state = if ($record.Count -eq 1) {
                $record[0].registrationState
            }
            else {
                'Missing'
            }
            throw "Provider '$namespace' is '$state'."
        }
        if (-not $QuietSuccess) {
            Write-Host "[OK] Provider: $namespace"
        }
    }

    if (-not $QuietSuccess) {
        if ($Validation.quotaProviderState -eq 'Registered') {
            Write-Host '[OK] Optional provider: Microsoft.Quota'
        }
        else {
            Write-Warning "Optional provider 'Microsoft.Quota' is '$($Validation.quotaProviderState)'. Microsoft.Quota-specific validation is skipped because the provider is not registered; model availability and regional Standard quota are still checked through Microsoft.CognitiveServices."
        }
    }
    if (@($Validation.searchLocations).Count -eq 0) {
        throw 'Unable to read Azure AI Search regional availability.'
    }
}

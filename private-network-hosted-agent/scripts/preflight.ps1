param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,
    [ValidateSet('pointToSite', 'siteToSite', 'vnetPeering')]
    [string]$ConnectivityMode = 'pointToSite',
    [string]$Location = 'westus3',
    [string]$SearchLocation = 'westus3',
    [string]$RemoteVnetResourceId = '',
    [string]$ContainerRegistryResourceId = '',
    [string]$ContainerRegistryEndpoint = '',
    [string]$ContainerImage = '',
    [string]$FoundryProjectId = '',
    [ValidateSet('Source', 'ExistingPrivateAcr')]
    [string]$DeploymentMode = 'Source',
    [ValidateSet('Terraform', 'Bicep')]
    [string]$InfrastructureProvider = 'Terraform',
    [string]$ProviderValidationJson = '',
    [ValidateSet('', 'true', 'false')]
    [string]$ResourceGroupExists = '',
    [string]$EnvironmentName = '',
    [string]$ExistingFoundryAccountId = '',
    [string]$ExistingFoundryProjectId = '',
    [switch]$AllowExistingModelCapacityReuse,
    [switch]$AllowMissingResourceGroup
)

. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/deployment/contract.ps1"
. "$PSScriptRoot/deployment/commands.ps1"
. "$PSScriptRoot/deployment/model-quota.ps1"
. "$PSScriptRoot/deployment/permissions.ps1"
. "$PSScriptRoot/deployment/providers.ps1"

foreach ($command in @('git', 'az', 'azd', 'python')) {
    Assert-Command $command
}

$accountResult = Invoke-CheckedCommand `
    -Stage 'Read Azure subscription' `
    -FilePath 'az' `
    -Arguments @('account', 'show', '--subscription', $SubscriptionId, '--output', 'json') `
    -Quiet
$account = $accountResult.Output -join "`n" | ConvertFrom-Json
if ($account.state -ne 'Enabled') {
    throw "Subscription '$SubscriptionId' is not enabled."
}

Write-Host "[OK] Subscription: $($account.name) ($SubscriptionId)"
$groupExists = $ResourceGroupExists
if ([string]::IsNullOrWhiteSpace($groupExists)) {
    $groupExistsResult = Invoke-CheckedCommand `
        -Stage 'Check resource group for preflight' `
        -FilePath 'az' `
        -Arguments @(
            'group', 'exists', '--subscription', $SubscriptionId,
            '--name', $ResourceGroupName, '-o', 'tsv'
        ) `
        -Quiet
    $groupExists = ($groupExistsResult.Output -join '').Trim()
}
if ($groupExists -eq 'true') {
    $groupResult = Invoke-CheckedCommand `
        -Stage 'Read existing resource group' `
        -FilePath 'az' `
        -Arguments @(
            'group', 'show', '--subscription', $SubscriptionId,
            '--name', $ResourceGroupName, '--output', 'json'
        ) `
        -Quiet
    $group = $groupResult.Output -join "`n" | ConvertFrom-Json
    Write-Host "[OK] Existing resource group: $($group.name) ($($group.location))"
}
elseif ($AllowMissingResourceGroup) {
    Write-Host "[OK] Dedicated resource group will be created by ${InfrastructureProvider}: $ResourceGroupName"
}
else {
    throw "Resource group '$ResourceGroupName' does not exist."
}

$effectivePermissions = Get-AzureEffectivePermissions `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -ResourceGroupExists ($groupExists -eq 'true')
$roleAssignmentWrite = 'Microsoft.Authorization/roleAssignments/write'
if (-not (Test-AzurePermissionsAllowAction `
        -Permissions $effectivePermissions.Permissions `
        -Action $roleAssignmentWrite)) {
    throw "Deployment identity lacks '$roleAssignmentWrite' at '$($effectivePermissions.Scope)'. Grant a role that permits RBAC assignment at this scope, then retry."
}
Write-Host (
    "[OK] Effective permissions include '$roleAssignmentWrite' at " +
    "'$($effectivePermissions.Scope)'. Preview still evaluates ABAC conditions; " +
    'time-bound grants must remain active through provisioning and its bounded retry.'
)

$hasAnyAcrInput = @(@(
    $ContainerRegistryResourceId,
    $ContainerRegistryEndpoint,
    $ContainerImage
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (($DeploymentMode -eq 'ExistingPrivateAcr') -ne ($hasAnyAcrInput.Count -gt 0)) {
    throw "DeploymentMode '$DeploymentMode' does not match the ACR input contract."
}
$reusedProviderValidation = -not [string]::IsNullOrWhiteSpace($ProviderValidationJson)
$providerValidation = if (-not $reusedProviderValidation) {
    Get-AzureProviderValidation `
        -SubscriptionId $SubscriptionId `
        -DeploymentMode $DeploymentMode
}
else {
    $ProviderValidationJson | ConvertFrom-Json
}
Assert-AzureProviderValidation `
    -Validation $providerValidation `
    -DeploymentMode $DeploymentMode `
    -QuietSuccess:$reusedProviderValidation
if ($reusedProviderValidation) {
    Write-Host '[REUSE] Required providers and Search regional metadata were validated earlier in this run.'
}

if ($ConnectivityMode -in @('pointToSite', 'siteToSite')) {
    $locationsResult = Invoke-CheckedCommand `
        -Stage 'Check VPN Gateway availability-zone region' `
        -FilePath 'az' `
        -Arguments @(
            'rest',
            '--method', 'get',
            '--url',
            "https://management.azure.com/subscriptions/$SubscriptionId/locations?api-version=2022-12-01",
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Quiet
    $locations = @(
        (($locationsResult.Output -join "`n" | ConvertFrom-Json).value)
    )
    $normalizedCoreLocation = ($Location -replace '\s', '').ToLowerInvariant()
    $locationMetadata = @($locations | Where-Object {
        (($_.name -replace '\s', '').ToLowerInvariant()) -eq $normalizedCoreLocation
    })
    if ($locationMetadata.Count -ne 1 -or
        @($locationMetadata[0].availabilityZoneMappings).Count -eq 0) {
        throw "Connectivity mode '$ConnectivityMode' requires an availability-zone region for VpnGw2AZ; '$Location' does not expose availability zones to this subscription."
    }
    Write-Host "[OK] VPN Gateway availability-zone region: $Location"
}

$modelResult = Invoke-CheckedCommand `
    -Stage 'Check regional model availability' `
    -FilePath 'az' `
    -Arguments @(
        'cognitiveservices', 'model', 'list',
        '--subscription', $SubscriptionId,
        '--location', $Location,
        '--query', "[?model.name=='gpt-5.1' && model.version=='2025-11-13'] | [0]",
        '--output', 'json'
    ) `
    -Quiet
$model = $modelResult.Output -join "`n" | ConvertFrom-Json
if (-not $model) {
    throw "gpt-5.1 2025-11-13 is unavailable in '$Location'."
}
if ('Standard' -notin $model.model.skus.name) {
    throw "Regional Standard is unavailable for gpt-5.1 in '$Location'."
}
$usageResult = Invoke-CheckedCommand `
    -Stage 'Check regional model quota' `
    -FilePath 'az' `
    -Arguments @(
        'cognitiveservices', 'usage', 'list',
        '--subscription', $SubscriptionId,
        '--location', $Location,
        '--query', "[?name.value=='OpenAI.Standard.gpt-5.1'] | [0]",
        '--output', 'json'
    ) `
    -Quiet
$usage = $usageResult.Output -join "`n" | ConvertFrom-Json
$desiredModelCapacity = 10
$reusableExistingCapacity = 0
if ($AllowExistingModelCapacityReuse) {
    $reusableExistingCapacity = Get-ExactReusableModelDeploymentCapacity `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -EnvironmentName $EnvironmentName `
        -Location $Location `
        -ExpectedAccountId $ExistingFoundryAccountId `
        -ExpectedProjectId $ExistingFoundryProjectId `
        -DeploymentName 'gpt-5.1' `
        -ModelName 'gpt-5.1' `
        -ModelVersion '2025-11-13' `
        -SkuName 'Standard'
}
$quota = Assert-RegionalModelQuota `
    -Usage $usage `
    -DesiredCapacity $desiredModelCapacity `
    -ReusableExistingCapacity $reusableExistingCapacity `
    -ModelName 'gpt-5.1' `
    -Location $Location
Write-Host "[OK] Regional model: gpt-5.1 2025-11-13 / Standard (available quota: $($quota.AvailableCapacity)K TPM; reusable capacity: $($quota.ReusableExistingCapacity)K TPM; additional required: $($quota.RequiredAdditionalCapacity)K TPM)"

$searchLocations = @($providerValidation.searchLocations)
$normalizedSearchLocation = ($SearchLocation -replace '\s', '').ToLowerInvariant()
$supportedSearchLocations = @($searchLocations | ForEach-Object {
    ($_ -replace '\s', '').ToLowerInvariant()
})
if ($normalizedSearchLocation -notin $supportedSearchLocations) {
    throw "Azure AI Search isn't available in '$SearchLocation'."
}
Write-Host "[OK] Azure AI Search region: $SearchLocation"

if ($ConnectivityMode -eq 'siteToSite' -and [string]::IsNullOrWhiteSpace($env:S2S_SHARED_KEY)) {
    throw 'Set S2S_SHARED_KEY only in the current process before provisioning siteToSite.'
}
if ($ConnectivityMode -eq 'vnetPeering' -and
    -not (Test-CanonicalVirtualNetworkResourceId -Value $RemoteVnetResourceId)) {
    throw 'RemoteVnetResourceId must be a canonical virtual network ARM resource ID for vnetPeering.'
}

$templateRoot = Split-Path $PSScriptRoot
$infraTerraformRoot = Join-Path $templateRoot 'infra-terraform'
$forbiddenArtifacts = @(Get-ChildItem -Path $templateRoot -Recurse -File |
    Where-Object {
        $_.Name -eq 'Dockerfile' -or
        (
            $_.Extension -in @('.tf', '.tfvars') -and
            $_.FullName -notlike (Join-Path $infraTerraformRoot '*')
        )
    })
if ($forbiddenArtifacts.Count -gt 0) {
    throw "Infrastructure artifacts violate the template repository contract: $($forbiddenArtifacts.FullName -join ', ')."
}

if ($hasAnyAcrInput.Count -gt 0) {
    Invoke-CheckedCommand `
        -Stage 'Validate existing private ACR inputs' `
        -FilePath 'pwsh' `
        -Arguments @(
            '-NoProfile', '-File', "$PSScriptRoot/validate-existing-acr.ps1",
            '-ContainerRegistryResourceId', $ContainerRegistryResourceId,
            '-ContainerRegistryEndpoint', $ContainerRegistryEndpoint,
            '-ContainerImage', $ContainerImage,
            '-FoundryProjectId', $FoundryProjectId
        ) | Out-Null
}

Write-Host "[OK] Connectivity mode: $ConnectivityMode"
Write-Host "[OK] Core location: $Location"
Write-Host "[OK] Search location: $SearchLocation"
Write-Host '[OK] Preflight completed without changing Azure resources.'

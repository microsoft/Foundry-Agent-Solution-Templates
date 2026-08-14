[CmdletBinding()]
param(
    [string]$DeploymentMode = '',
    [string]$SubscriptionId = '',
    [string]$EnvironmentName = '',
    [string]$Location = 'westus3',
    [string]$SearchLocation = 'westus3',
    [ValidateSet('pointToSite', 'siteToSite', 'vnetPeering')]
    [string]$ConnectivityMode = 'pointToSite',
    [string]$RemoteVnetResourceId = '',
    [string]$VnetAddressPrefix = '10.42.0.0/16',
    [string]$AgentSubnetPrefix = '10.42.0.0/24',
    [string]$PrivateEndpointSubnetPrefix = '10.42.1.0/24',
    [string]$FirewallSubnetPrefix = '10.42.2.0/26',
    [string]$GatewaySubnetPrefix = '10.42.3.0/27',
    [string]$DnsInboundSubnetPrefix = '10.42.4.0/28',
    [string]$DnsInboundIpAddress = '10.42.4.4',
    [string]$P2sAddressPool = '172.20.0.0/24',
    [string]$S2sGatewayIpAddress = '',
    [string[]]$S2sRemoteAddressPrefixes = @(),
    [switch]$S2sEnableBgp,
    [int]$S2sRemoteAsn = 65010,
    [string]$S2sBgpPeeringAddress = '',
    [string]$InvocationTestPrincipalObjectId = '',
    [string]$ContainerRegistryResourceId = '',
    [string]$ContainerRegistryEndpoint = '',
    [string]$ContainerImage = '',
    [switch]$NoPrompt,
    [switch]$ValidateInputsOnly,
    [switch]$PreviewOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot
$existingPrivateAcrGuidePath = Join-Path $repositoryRoot 'docs/existing-private-acr.md'
. "$PSScriptRoot/deployment/contract.ps1"
. "$PSScriptRoot/deployment/commands.ps1"
. "$PSScriptRoot/deployment/diagnostics.ps1"
. "$PSScriptRoot/deployment/providers.ps1"
. "$PSScriptRoot/deployment/workflow.ps1"

if ([string]::IsNullOrWhiteSpace($DeploymentMode) -and -not $NoPrompt) {
    $selection = Read-Host 'Deployment mode: [1] Source/ZIP or [2] Existing private ACR'
    $DeploymentMode = switch ($selection) {
        '1' { 'Source' }
        '2' { 'ExistingPrivateAcr' }
        default { throw "Deployment mode selection '$selection' is invalid." }
    }
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId) -and -not $NoPrompt) {
    $SubscriptionId = Read-Host 'Azure subscription ID'
}

Assert-DeploymentInputs `
    -DeploymentMode $DeploymentMode `
    -SubscriptionId $SubscriptionId `
    -EnvironmentName $EnvironmentName `
    -ContainerRegistryResourceId $ContainerRegistryResourceId `
    -ContainerRegistryEndpoint $ContainerRegistryEndpoint `
    -ContainerImage $ContainerImage `
    -ConnectivityMode $ConnectivityMode `
    -RemoteVnetResourceId $RemoteVnetResourceId `
    -S2sGatewayIpAddress $S2sGatewayIpAddress `
    -S2sRemoteAddressPrefixes $S2sRemoteAddressPrefixes `
    -S2sEnableBgp:$S2sEnableBgp `
    -S2sBgpPeeringAddress $S2sBgpPeeringAddress `
    -NoPrompt:$NoPrompt

$projectDirectory = Get-DeploymentProjectDirectory `
    -RepositoryRoot $repositoryRoot `
    -DeploymentMode $DeploymentMode
if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
    if ($ValidateInputsOnly) {
        $EnvironmentName = New-DeploymentEnvironmentName -DeploymentMode $DeploymentMode
    }
}

if ($ValidateInputsOnly) {
    $ResourceGroupName = Get-GeneratedResourceGroupName `
        -EnvironmentName $EnvironmentName
    [pscustomobject]@{
        deploymentMode = $DeploymentMode
        subscriptionId = $SubscriptionId
        environmentName = $EnvironmentName
        resourceGroupName = $ResourceGroupName
        projectDirectory = $projectDirectory
    } | ConvertTo-Json
    return
}

Ensure-RequiredCommands
$account = Ensure-AzureAuthentication `
    -SubscriptionId $SubscriptionId `
    -NoPrompt:$NoPrompt
$environmentContext = Resolve-AzdEnvironmentContext `
    -ProjectDirectory $projectDirectory `
    -EnvironmentName $EnvironmentName `
    -DeploymentMode $DeploymentMode `
    -SubscriptionId $SubscriptionId
$EnvironmentName = $environmentContext.Name
$ResourceGroupName = $environmentContext.ResourceGroupName
$existingEnvironmentValues = $environmentContext.Values
$azdEnvironmentNames = @($environmentContext.Names)

$groupExists = Test-ResourceGroupExists `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName
if ($groupExists) {
    if (-not $environmentContext.BindingValidated) {
        throw "Generated resource group name '$ResourceGroupName' already exists and does not match this workflow."
    }
    Assert-TemplateResourceGroupOwnership `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -EnvironmentName $EnvironmentName
}

Ensure-AzdExtensions `
    -DeploymentMode $DeploymentMode `
    -ProjectDirectory $projectDirectory
$providerValidation = Ensure-RequiredProviders `
    -SubscriptionId $SubscriptionId `
    -DeploymentMode $DeploymentMode
$deploymentPrincipalObjectId = Get-DeploymentPrincipalObjectId -Account $account

$environmentValues = @{
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    AZURE_TENANT_ID = $account.tenantId
    AZURE_LOCATION = $Location
    AZURE_SEARCH_LOCATION = $SearchLocation
    AZURE_RESOURCE_GROUP = $ResourceGroupName
    DEPLOYMENT_PRINCIPAL_OBJECT_ID = $deploymentPrincipalObjectId
    INVOCATION_TEST_PRINCIPAL_OBJECT_ID = $InvocationTestPrincipalObjectId
    CONNECTIVITY_MODE = $ConnectivityMode
    VNET_ADDRESS_PREFIX = $VnetAddressPrefix
    AGENT_SUBNET_PREFIX = $AgentSubnetPrefix
    PRIVATE_ENDPOINT_SUBNET_PREFIX = $PrivateEndpointSubnetPrefix
    FIREWALL_SUBNET_PREFIX = $FirewallSubnetPrefix
    GATEWAY_SUBNET_PREFIX = $GatewaySubnetPrefix
    DNS_INBOUND_SUBNET_PREFIX = $DnsInboundSubnetPrefix
    DNS_INBOUND_IP_ADDRESS = $DnsInboundIpAddress
    P2S_ADDRESS_POOL = $P2sAddressPool
    S2S_GATEWAY_IP_ADDRESS = $S2sGatewayIpAddress
    S2S_REMOTE_ADDRESS_PREFIXES = ConvertTo-Json `
        -InputObject @($S2sRemoteAddressPrefixes) `
        -Compress
    S2S_ENABLE_BGP = $S2sEnableBgp.IsPresent.ToString().ToLowerInvariant()
    S2S_REMOTE_ASN = $S2sRemoteAsn
    S2S_BGP_PEERING_ADDRESS = $S2sBgpPeeringAddress
    REMOTE_VNET_RESOURCE_ID = $RemoteVnetResourceId
    FPHA_DEPLOYMENT_MODE = $DeploymentMode
}
if ($DeploymentMode -eq 'ExistingPrivateAcr') {
    $environmentValues.AZURE_CONTAINER_REGISTRY_RESOURCE_ID = $ContainerRegistryResourceId
    $environmentValues.AZURE_CONTAINER_REGISTRY_ENDPOINT = $ContainerRegistryEndpoint
    $environmentValues.AZURE_CONTAINER_IMAGE = $ContainerImage
    $environmentValues.AZD_AGENT_SKIP_ACR = 'true'
    $environmentValues.AZD_AGENT_SKIP_ROLE_ASSIGNMENTS = 'true'
}
$fingerprintValues = $environmentValues.Clone()
if ($ConnectivityMode -eq 'siteToSite') {
    $fingerprintValues.S2S_SHARED_KEY_SHA256 = Get-StringSha256 -Value $env:S2S_SHARED_KEY
}
$infrastructureFingerprint = Get-InfrastructureFingerprint `
    -RepositoryRoot $repositoryRoot `
    -ProjectDirectory $projectDirectory `
    -Values $fingerprintValues

$currentEnvironmentValues = Initialize-AzdEnvironment `
    -ProjectDirectory $projectDirectory `
    -EnvironmentName $EnvironmentName `
    -SubscriptionId $SubscriptionId `
    -Location $Location `
    -Values $environmentValues `
    -CurrentValues $existingEnvironmentValues `
    -EnvironmentNames $azdEnvironmentNames

Invoke-CheckedCommand `
    -Stage 'Select azd environment' `
    -FilePath 'azd' `
    -Arguments @('env', 'select', $EnvironmentName, '--no-prompt') `
    -WorkingDirectory $projectDirectory `
    -Quiet | Out-Null

$preflightArguments = @(
    '-NoProfile', '-File', "$PSScriptRoot/preflight.ps1",
    '-SubscriptionId', $SubscriptionId,
    '-ResourceGroupName', $ResourceGroupName,
    '-ConnectivityMode', $ConnectivityMode,
    '-Location', $Location,
    '-SearchLocation', $SearchLocation,
    '-RemoteVnetResourceId', $RemoteVnetResourceId,
    '-DeploymentMode', $DeploymentMode,
    '-ProviderValidationJson', ($providerValidation | ConvertTo-Json -Compress -Depth 5),
    '-ResourceGroupExists', $groupExists.ToString().ToLowerInvariant(),
    '-EnvironmentName', $EnvironmentName,
    '-ExistingFoundryAccountId', [string]$currentEnvironmentValues['AZURE_AI_ACCOUNT_ID'],
    '-ExistingFoundryProjectId', [string]$currentEnvironmentValues['AZURE_AI_PROJECT_ID']
)
if (-not $groupExists) {
    $preflightArguments += '-AllowMissingResourceGroup'
}
if ($environmentContext.BindingValidated -and $groupExists) {
    $preflightArguments += '-AllowExistingModelCapacityReuse'
}
if ($DeploymentMode -eq 'ExistingPrivateAcr') {
    $preflightArguments += @(
        '-ContainerRegistryResourceId', $ContainerRegistryResourceId,
        '-ContainerRegistryEndpoint', $ContainerRegistryEndpoint,
        '-ContainerImage', $ContainerImage
    )
}
Invoke-CheckedCommand `
    -Stage 'Read-only deployment preflight' `
    -FilePath 'pwsh' `
    -Arguments $preflightArguments `
    -WorkingDirectory $projectDirectory `
    -RedactArgumentIndexes @(18) | Out-Null

Set-AzdFirewallCreationMode `
    -ProjectDirectory $projectDirectory `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -EnvironmentName $EnvironmentName
$preview = Invoke-CheckedCommand `
    -Stage 'Provision preview' `
    -FilePath 'azd' `
    -Arguments @(
        'provision', '-e', $EnvironmentName, '--preview', '--no-prompt'
    ) `
    -WorkingDirectory $projectDirectory
Assert-SafeProvisionPreview `
    -PreviewOutput $preview.Output `
    -DeploymentMode $DeploymentMode

if ($PreviewOnly) {
    Write-Host '[COMPLETE] Provision preview passed the workflow safety checks.'
    [pscustomobject]@{
        deploymentMode = $DeploymentMode
        environmentName = $EnvironmentName
        resourceGroupName = $ResourceGroupName
        validation = 'preview-passed'
    } | ConvertTo-Json
    return
}

$fingerprintMatches = $currentEnvironmentValues['FPHA_INFRASTRUCTURE_FINGERPRINT'] -eq
    $infrastructureFingerprint
$infrastructureReady = $fingerprintMatches -and
    (Test-InfrastructureReady `
        -ProjectDirectory $projectDirectory `
        -EnvironmentName $EnvironmentName `
        -DeploymentMode $DeploymentMode `
        -ValidatorDirectory $PSScriptRoot)
if ($infrastructureReady) {
    Write-Host '[RESUME] Infrastructure fingerprint and live validation match; skipping provision.'
}
else {
    try {
        Invoke-ProvisionWithArmDiagnostics `
            -ProjectDirectory $projectDirectory `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -EnvironmentName $EnvironmentName | Out-Null
    }
    catch {
        $nativeExitCode = $_.Exception.Data['NativeExitCode']
        if ($null -eq $nativeExitCode) {
            throw
        }
        $Host.UI.WriteErrorLine($_.Exception.Message)
        exit [int]$nativeExitCode
    }
    Invoke-CheckedCommand `
        -Stage 'Persist infrastructure fingerprint' `
        -FilePath 'azd' `
        -Arguments @(
            'env', 'set', 'FPHA_INFRASTRUCTURE_FINGERPRINT',
            $infrastructureFingerprint, '-e', $EnvironmentName
        ) `
        -WorkingDirectory $projectDirectory `
        -Quiet `
        -RedactArgumentIndexes @(3) | Out-Null
}

foreach ($validator in @(
    'validate-infrastructure.ps1',
    'validate-rbac.ps1',
    'validate-cmk.ps1',
    'validate-network.ps1'
)) {
    Invoke-CheckedCommand `
        -Stage "Run $validator" `
        -FilePath 'pwsh' `
        -Arguments @(
            '-NoProfile', '-File', (Join-Path $PSScriptRoot $validator),
            '-EnvironmentName', $EnvironmentName
        ) `
        -WorkingDirectory $projectDirectory | Out-Null
}
if ($DeploymentMode -eq 'ExistingPrivateAcr') {
    Invoke-CheckedCommand `
        -Stage 'Validate Foundry ACR connection' `
        -FilePath 'pwsh' `
        -Arguments @(
            '-NoProfile', '-File', "$PSScriptRoot/validate-existing-acr.ps1",
            '-ValidateConnection',
            '-EnvironmentName', $EnvironmentName
        ) `
        -WorkingDirectory $projectDirectory | Out-Null
}

$profilePath = ''
if ($ConnectivityMode -eq 'pointToSite') {
    $additionalDnsSuffixes = @()
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        $additionalDnsSuffixes = Get-AcrDnsSuffixes `
            -ContainerRegistryResourceId $ContainerRegistryResourceId `
            -ContainerRegistryEndpoint $ContainerRegistryEndpoint
    }
    $profileOutputDirectory = Join-Path $repositoryRoot "artifacts/p2s/$EnvironmentName"
    $profilePath = Join-Path $profileOutputDirectory 'AzureVPN/azurevpnconfig-resource-dns.xml'
    $profileWasExported = $false
    if ($infrastructureReady -and
        (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        Write-Host "[RESUME] Reusing the existing VPN profile: $profilePath"
        Write-Host '[RESUME] If Azure VPN Client is already connected with this profile, do not re-import it.'
    }
    else {
        $exportArguments = @(
            '-NoProfile', '-File', "$PSScriptRoot/export-p2s-profile.ps1",
            '-OutputDirectory', $profileOutputDirectory,
            '-EnvironmentName', $EnvironmentName
        )
        if ($additionalDnsSuffixes.Count -gt 0) {
            $exportArguments += @(
                '-AdditionalDnsSuffixesJson',
                ($additionalDnsSuffixes | ConvertTo-Json -Compress)
            )
        }
        Invoke-CheckedCommand `
            -Stage 'Export resource-scoped VPN profile' `
            -FilePath 'pwsh' `
            -Arguments $exportArguments `
            -WorkingDirectory $projectDirectory | Out-Null
        $profileWasExported = $true
    }
    if (-not $NoPrompt) {
        if ($profileWasExported) {
            Write-Host "Import and connect this profile in Azure VPN Client: $profilePath"
        }
        else {
            Write-Host "Keep Azure VPN Client connected with this profile: $profilePath"
        }
        if ($DeploymentMode -eq 'ExistingPrivateAcr') {
            Write-Host '[ACTION] Existing private ACR network handoff:'
            Write-Host "[ACTION] Detailed guide: $existingPrivateAcrGuidePath"
            Write-Host '[ACTION] Section: Complete the external private network handoff'
            Write-Host "[ACTION] Confirm the Azure Public Cloud ACR Private DNS zone 'privatelink.azurecr.io' is linked to this Foundry solution VNet."
            Write-Host "[ACTION] Confirm this VNet can reach the selected registry's Private Endpoint directly or through approved routing/peering."
            Write-Host '[ACTION] Use this Foundry VPN profile for validation; an ACR-side VPN profile does not validate the deployment path.'
            Write-Host '[INFO] This workflow has separate network and IAM handoffs.'
            Write-Host '[INFO] After network validation, the initial Agent deployment creates its stable identity.'
            Write-Host '[INFO] A registry-authentication ImageError is expected until the later IAM handoff is complete; do not grant a guessed Agent identity.'
        }
        Read-Host 'Press Enter only after Azure VPN Client shows Connected' | Out-Null
    }
}

Invoke-CheckedCommand `
    -Stage 'Validate private connectivity' `
    -FilePath 'pwsh' `
    -Arguments @(
        '-NoProfile', '-File', "$PSScriptRoot/validate-network.ps1",
        '-RequirePrivateResolution',
        '-EnvironmentName', $EnvironmentName
    ) `
    -WorkingDirectory $projectDirectory | Out-Null

$serviceName = if ($DeploymentMode -eq 'Source') {
    'private-search-agent'
}
else {
    'private-search-agent-acr'
}
$agent = $null
if ($DeploymentMode -eq 'ExistingPrivateAcr') {
    try {
        $agent = Get-AgentRecord `
            -ProjectDirectory $projectDirectory `
            -EnvironmentName $EnvironmentName `
            -ServiceName $serviceName
        Write-Host '[RESUME] Existing Hosted Agent identity found; continuing at the external IAM handoff.'
    }
    catch {
        $agent = $null
    }
}
if ($DeploymentMode -eq 'Source' -or $null -eq $agent) {
    $deployArguments = @(
        'deploy', $serviceName, '-e', $EnvironmentName, '--no-prompt'
    )
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        Write-Host '[INFO] Initializing the Hosted Agent to create its stable identity.'
        Write-Host '[INFO] Missing ACR pull authorization at this bootstrap stage will be handled as the IAM handoff, not as a completed deployment.'
        $firstDeploy = Invoke-CheckedCommand `
            -Stage 'Initialize Hosted Agent identity' `
            -FilePath 'azd' `
            -Arguments $deployArguments `
            -WorkingDirectory $projectDirectory `
            -AllowFailure `
            -Quiet
    }
    else {
        $firstDeploy = Invoke-CheckedCommand `
            -Stage 'Deploy Hosted Agent' `
            -FilePath 'azd' `
            -Arguments $deployArguments `
            -WorkingDirectory $projectDirectory `
            -AllowFailure
    }
    if ($DeploymentMode -eq 'Source' -and $firstDeploy.ExitCode -ne 0) {
        throw "Source Hosted Agent deployment failed. Command: $($firstDeploy.Command)"
    }
    $expectedBootstrapAuthorizationFailure =
        $DeploymentMode -eq 'ExistingPrivateAcr' -and
        (Test-ExpectedAcrBootstrapAuthorizationFailure `
            -ExitCode $firstDeploy.ExitCode `
            -Output $firstDeploy.Output)
    if ($DeploymentMode -eq 'ExistingPrivateAcr' -and
        $firstDeploy.ExitCode -ne 0 -and
        -not $expectedBootstrapAuthorizationFailure) {
        $firstDeploy.Output | ForEach-Object { Write-Host $_ }
        throw "Initial Hosted Agent deployment failed before the expected ACR IAM handoff. Command: $($firstDeploy.Command)"
    }
    try {
        $agent = Get-AgentRecord `
            -ProjectDirectory $projectDirectory `
            -EnvironmentName $EnvironmentName `
            -ServiceName $serviceName
    }
    catch {
        if ($DeploymentMode -eq 'ExistingPrivateAcr') {
            $firstDeploy.Output | ForEach-Object { Write-Host $_ }
        }
        throw "Hosted Agent identity was not created. Initial deploy command: $($firstDeploy.Command)"
    }
    if ($expectedBootstrapAuthorizationFailure) {
        Write-Host '[INFO] The expected ACR authorization boundary was reached and the stable Hosted Agent identity was created.'
    }
}
$agentPrincipalId = Get-AgentPrincipalId -Agent $agent
Invoke-CheckedCommand `
    -Stage 'Persist Agent principal ID' `
    -FilePath 'azd' `
    -Arguments @(
        'env', 'set', 'AZURE_AI_AGENT_PRINCIPAL_ID',
        $agentPrincipalId, '-e', $EnvironmentName
    ) `
    -WorkingDirectory $projectDirectory `
    -Quiet `
    -RedactArgumentIndexes @(3) | Out-Null

$projectPrincipalId = ''
if ($DeploymentMode -eq 'ExistingPrivateAcr') {
    $identityValues = Get-AzdEnvironmentValues `
        -ProjectDirectory $projectDirectory `
        -EnvironmentName $EnvironmentName
    $projectPrincipalId = $identityValues['AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID']
    if ([string]::IsNullOrWhiteSpace($projectPrincipalId)) {
        throw 'Provisioning did not return AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID.'
    }
    $acrValidationArguments = @(
        '-NoProfile', '-File', "$PSScriptRoot/validate-existing-acr.ps1",
        '-FoundryProjectPrincipalId', $projectPrincipalId,
        '-AgentPrincipalId', $agentPrincipalId,
        '-EnvironmentName', $EnvironmentName,
        '-ValidateConnection',
        '-ValidatePullAuthorization',
        '-RequirePrivateDataPlane'
    )
    $acrValidation = Invoke-CheckedCommand `
        -Stage 'Validate external ACR handoff' `
        -FilePath 'pwsh' `
        -Arguments $acrValidationArguments `
        -WorkingDirectory $projectDirectory `
        -AllowFailure `
        -Quiet
    if ($acrValidation.ExitCode -ne 0) {
        $missingPullAuthorization = Test-MissingAcrPullAuthorizationFailure `
            -ExitCode $acrValidation.ExitCode `
            -Output $acrValidation.Output
        if (-not $missingPullAuthorization) {
            $acrValidation.Output | ForEach-Object { Write-Host $_ }
            throw 'External ACR validation failed before the expected IAM handoff.'
        }
        Write-Host '[ACTION] Existing private ACR IAM handoff required:'
        $acrValidation.Output |
            Where-Object { $_ -match '^\[ACTION\]' } |
            ForEach-Object { Write-Host $_ }
        if ($NoPrompt) {
            throw "External ACR IAM handoff is incomplete for Foundry project principal '$projectPrincipalId' and Agent principal '$agentPrincipalId'. The script did not modify ACR IAM."
        }
        Write-Host '[ACTION] An enterprise ACR administrator must grant the role printed above to every reported identity.'
        Write-Host "[ACTION] Foundry project principal: $projectPrincipalId"
        Write-Host "[ACTION] Hosted Agent principal: $agentPrincipalId"
        Write-Host "[ACTION] Registry scope: $ContainerRegistryResourceId"
        Write-Host '[ACTION] Use exact-scope AcrPull for RBAC Registry Permissions, or Container Registry Repository Reader for an ABAC-enabled registry.'
        Write-Host '[ACTION] The deployment script validates this handoff but does not modify enterprise ACR IAM.'
        Write-Host "[ACTION] Detailed guide: $existingPrivateAcrGuidePath"
        Write-Host '[ACTION] Section: Create the Agent identity and complete the external RBAC handoff'
        Read-Host 'Press Enter only after all reported role assignments have propagated' | Out-Null
        Invoke-CheckedCommand `
            -Stage 'Revalidate external ACR handoff' `
            -FilePath 'pwsh' `
            -Arguments $acrValidationArguments `
            -WorkingDirectory $projectDirectory | Out-Null
    }
    Invoke-CheckedCommand `
        -Stage 'Continue Hosted Agent deployment' `
        -FilePath 'azd' `
        -Arguments @(
            'deploy', $serviceName, '-e', $EnvironmentName, '--no-prompt'
        ) `
        -WorkingDirectory $projectDirectory | Out-Null
}

$deployedValues = Get-AzdEnvironmentValues `
    -ProjectDirectory $projectDirectory `
    -EnvironmentName $EnvironmentName
$versionKey = if ($DeploymentMode -eq 'Source') {
    'AGENT_PRIVATE_SEARCH_AGENT_VERSION'
}
else {
    'AGENT_PRIVATE_SEARCH_AGENT_ACR_VERSION'
}
$expectedVersion = $deployedValues[$versionKey]
$agent = Wait-ForAgentActive `
    -ProjectDirectory $projectDirectory `
    -EnvironmentName $EnvironmentName `
    -ServiceName $serviceName `
    -ExpectedVersion $expectedVersion
$liveVersionProperty = $agent.PSObject.Properties['version']
$liveVersion = if ($null -ne $liveVersionProperty) {
    [string]$liveVersionProperty.Value
}
else {
    ''
}
if ([string]::IsNullOrWhiteSpace($liveVersion)) {
    throw "Hosted Agent '$serviceName' did not report an exact active version."
}
if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
    $expectedVersion = $liveVersion
}
elseif ($liveVersion -ne [string]$expectedVersion) {
    throw "Hosted Agent '$serviceName' is active at version '$liveVersion', not expected version '$expectedVersion'."
}

Invoke-CheckedCommand `
    -Stage 'Assign query-only Search access' `
    -FilePath 'pwsh' `
    -Arguments @(
        '-NoProfile', '-File', "$PSScriptRoot/assign-agent-search-role.ps1",
        '-AgentPrincipalId', $agentPrincipalId,
        '-AgentServiceName', $serviceName,
        '-EnvironmentName', $EnvironmentName
    ) `
    -WorkingDirectory $projectDirectory | Out-Null
Invoke-CheckedCommand `
    -Stage 'Seed private Search index' `
    -FilePath 'pwsh' `
    -Arguments @(
        '-NoProfile', '-File', "$PSScriptRoot/seed-search.ps1",
        '-EnvironmentName', $EnvironmentName
    ) `
    -WorkingDirectory $projectDirectory | Out-Null
$securityValidationReportDirectory = Join-Path `
    $repositoryRoot `
    "artifacts/validation/$EnvironmentName"
$securityValidationReportPath = Join-Path `
    $securityValidationReportDirectory `
    'latest.md'
Invoke-CheckedCommand `
    -Stage 'Run full private validation' `
    -FilePath 'pwsh' `
    -Arguments @(
        '-NoProfile', '-File', "$PSScriptRoot/validate-all.ps1",
        '-IncludePrivateDataPlane',
        '-AgentServiceName', $serviceName,
        '-AgentVersion', $expectedVersion,
        '-DeploymentMode', $DeploymentMode,
        '-ReportDirectory', $securityValidationReportDirectory,
        '-EnvironmentName', $EnvironmentName
    ) `
    -WorkingDirectory $projectDirectory | Out-Null
if (-not (Test-Path -LiteralPath $securityValidationReportPath -PathType Leaf)) {
    throw 'Full private validation completed without writing the security validation report.'
}

$agentMetadata = Get-AgentRecord `
    -ProjectDirectory $projectDirectory `
    -EnvironmentName $EnvironmentName `
    -ServiceName $serviceName
if ([string]$agentMetadata.version -ne [string]$expectedVersion) {
    throw "Hosted Agent metadata reports version '$($agentMetadata.version)', not expected version '$expectedVersion'."
}
$playgroundProperty = $agentMetadata.PSObject.Properties['playground_url']
$playgroundUrl = if ($null -ne $playgroundProperty) {
    [string]$playgroundProperty.Value
}
else {
    ''
}
$invokePrompt = 'What information is available in the private search index?'
$projectEndpoint = $deployedValues['FOUNDRY_PROJECT_ENDPOINT']
if ([string]::IsNullOrWhiteSpace($projectEndpoint)) {
    throw 'Deployment did not return FOUNDRY_PROJECT_ENDPOINT for the invoke handoff.'
}
$agentEndpoint = "$($projectEndpoint.TrimEnd('/'))/agents/$serviceName/endpoint/protocols/openai/responses?api-version=v1"
$invokeCommand = "azd ai agent invoke --agent-endpoint '$agentEndpoint' --version '$expectedVersion' '$invokePrompt'"
Write-Host ''
Write-Host '[COMPLETE] Unified Foundry deployment succeeded.'
Write-Host "[REPORT] Security validation report: $securityValidationReportPath"
Write-Host '[NEXT] Invoke the validated Hosted Agent from any PowerShell directory:'
Write-Host $invokeCommand
[pscustomobject]@{
    deploymentMode = $DeploymentMode
    environmentName = $EnvironmentName
    resourceGroupName = $ResourceGroupName
    agentService = $serviceName
    agentVersion = $expectedVersion
    agentPrincipalId = $agentPrincipalId
    projectPrincipalId = $projectPrincipalId
    playgroundUrl = $playgroundUrl
    agentEndpoint = $agentEndpoint
    invokeCommand = $invokeCommand
    vpnProfile = $profilePath
    securityValidationReport = $securityValidationReportPath
    validation = 'passed'
} | ConvertTo-Json

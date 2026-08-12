Set-StrictMode -Version Latest

function Get-DeploymentProjectDirectory {
    param(
        [string]$RepositoryRoot,
        [string]$DeploymentMode
    )
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        return Join-Path $RepositoryRoot 'scenarios/existing-private-acr'
    }
    return $RepositoryRoot
}

function Get-AzdEnvironmentValues {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName
    )
    $result = Invoke-CheckedCommand `
        -Stage 'Read azd environment' `
        -FilePath 'azd' `
        -Arguments @('env', 'get-values', '-e', $EnvironmentName) `
        -WorkingDirectory $ProjectDirectory `
        -Quiet
    return ConvertFrom-AzdEnvironmentOutput $result.Output
}

function Get-ReusableAzdEnvironmentContext {
    param(
        [string]$ProjectDirectory,
        [string]$DeploymentMode,
        [string]$SubscriptionId,
        [string[]]$EnvironmentNames
    )

    $configPath = Join-Path $ProjectDirectory '.azure/config.json'
    if (-not (Test-Path $configPath)) {
        $configPath = Join-Path (Split-Path $ProjectDirectory) '.azure/config.json'
    }
    if (-not (Test-Path $configPath)) {
        return $null
    }
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $nameProperty = $config.PSObject.Properties['defaultEnvironment']
    if ($null -eq $nameProperty -or [string]::IsNullOrWhiteSpace($nameProperty.Value)) {
        return $null
    }
    if ($PSBoundParameters.ContainsKey('EnvironmentNames') -and
        $nameProperty.Value -notin @($EnvironmentNames)) {
        return $null
    }
    try {
        $values = Get-AzdEnvironmentValues `
            -ProjectDirectory $ProjectDirectory `
            -EnvironmentName $nameProperty.Value
    }
    catch {
        return $null
    }
    $expectedResourceGroup = Get-GeneratedResourceGroupName `
        -EnvironmentName $nameProperty.Value
    if ($values['FPHA_DEPLOYMENT_MODE'] -eq $DeploymentMode -and
        $values['AZURE_SUBSCRIPTION_ID'] -eq $SubscriptionId -and
        $values['AZURE_RESOURCE_GROUP'] -eq $expectedResourceGroup) {
        return [pscustomobject]@{
            Name = [string]$nameProperty.Value
            Values = $values
        }
    }
    return $null
}

function Assert-AzdEnvironmentBinding {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$DeploymentMode,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string[]]$EnvironmentNames,
        [hashtable]$CurrentValues
    )

    $environmentNames = if ($PSBoundParameters.ContainsKey('EnvironmentNames')) {
        @($EnvironmentNames)
    }
    else {
        @(Get-AzdEnvironmentNames -ProjectDirectory $ProjectDirectory)
    }
    if ($EnvironmentName -notin $environmentNames) {
        return @{}
    }
    $values = if ($PSBoundParameters.ContainsKey('CurrentValues')) {
        $CurrentValues
    }
    else {
        Get-AzdEnvironmentValues `
            -ProjectDirectory $ProjectDirectory `
            -EnvironmentName $EnvironmentName
    }
    $binding = @{
        FPHA_DEPLOYMENT_MODE = $DeploymentMode
        AZURE_SUBSCRIPTION_ID = $SubscriptionId
        AZURE_RESOURCE_GROUP = $ResourceGroupName
    }
    $hasExistingBinding = @(
        $binding.Keys | Where-Object {
            $values.ContainsKey($_) -and
            -not [string]::IsNullOrWhiteSpace($values[$_])
        }
    ).Count -gt 0
    if (-not $hasExistingBinding) {
        return $values
    }

    foreach ($name in $binding.Keys) {
        if (-not $values.ContainsKey($name) -or
            $values[$name] -ne [string]$binding[$name]) {
            throw "azd environment '$EnvironmentName' is already bound to a different subscription, mode, or derived resource group."
        }
    }
    return $values
}

function Resolve-AzdEnvironmentContext {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$DeploymentMode,
        [string]$SubscriptionId
    )

    $environmentNames = @(Get-AzdEnvironmentNames `
        -ProjectDirectory $ProjectDirectory)
    $cachedValues = $null
    if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $reusable = Get-ReusableAzdEnvironmentContext `
            -ProjectDirectory $ProjectDirectory `
            -DeploymentMode $DeploymentMode `
            -SubscriptionId $SubscriptionId `
            -EnvironmentNames $environmentNames
        if ($null -eq $reusable) {
            $EnvironmentName = New-DeploymentEnvironmentName `
                -DeploymentMode $DeploymentMode
        }
        else {
            $EnvironmentName = $reusable.Name
            $cachedValues = $reusable.Values
        }
    }
    $ResourceGroupName = Get-GeneratedResourceGroupName `
        -EnvironmentName $EnvironmentName

    $bindingParameters = @{
        ProjectDirectory = $ProjectDirectory
        EnvironmentName = $EnvironmentName
        DeploymentMode = $DeploymentMode
        SubscriptionId = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        EnvironmentNames = $environmentNames
    }
    if ($null -ne $cachedValues) {
        $bindingParameters.CurrentValues = $cachedValues
    }
    $values = Assert-AzdEnvironmentBinding @bindingParameters
    $bindingValidated = $EnvironmentName -in $environmentNames -and
        $values['FPHA_DEPLOYMENT_MODE'] -eq $DeploymentMode -and
        $values['AZURE_SUBSCRIPTION_ID'] -eq $SubscriptionId -and
        $values['AZURE_RESOURCE_GROUP'] -eq $ResourceGroupName
    return [pscustomobject]@{
        Name = $EnvironmentName
        ResourceGroupName = $ResourceGroupName
        Values = $values
        Names = $environmentNames
        BindingValidated = $bindingValidated
    }
}

function Get-AzdEnvironmentNames {
    param([string]$ProjectDirectory)

    $result = Invoke-CheckedCommand `
        -Stage 'List azd environments' `
        -FilePath 'azd' `
        -Arguments @('env', 'list', '--output', 'json') `
        -WorkingDirectory $ProjectDirectory `
        -Quiet
    $environments = @($result.Output -join "`n" | ConvertFrom-Json)
    return @($environments | ForEach-Object { [string]$_.Name })
}

function Get-InfrastructureFingerprint {
    param(
        [string]$RepositoryRoot,
        [string]$ProjectDirectory,
        [hashtable]$Values
    )

    $paths = @(
        Get-ChildItem (Join-Path $RepositoryRoot 'infra') -Recurse -File |
            Where-Object { $_.Extension -in @('.bicep', '.json') }
    )
    $projectDefinition = Join-Path $ProjectDirectory 'azure.yaml'
    if (Test-Path $projectDefinition) {
        $paths += Get-Item $projectDefinition
    }
    $parts = foreach ($path in $paths | Sort-Object FullName) {
        $relativePath = $path.FullName.Substring($RepositoryRoot.Length).TrimStart('\', '/')
        "$relativePath`n$(Get-Content $path.FullName -Raw)"
    }
    $parts += foreach ($name in $Values.Keys | Sort-Object) {
        "$name=$([string]$Values[$name])"
    }
    return Get-StringSha256 -Value ($parts -join "`n---`n")
}

function Get-StringSha256 {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha256.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Ensure-RequiredCommands {
    foreach ($command in @('git', 'az', 'azd', 'pwsh', 'python')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Required command '$command' is not installed."
        }
    }
}

function Ensure-AzureAuthentication {
    param(
        [string]$SubscriptionId,
        [switch]$NoPrompt
    )

    $accountResult = Invoke-CheckedCommand `
        -Stage 'Check Azure CLI authentication' `
        -FilePath 'az' `
        -Arguments @('account', 'show', '--output', 'json') `
        -AllowFailure `
        -Quiet
    if ($accountResult.ExitCode -ne 0) {
        if ($NoPrompt) {
            throw 'Azure CLI is not authenticated. Run az login before using -NoPrompt.'
        }
        Invoke-CheckedCommand -Stage 'Azure CLI login' -FilePath 'az' -Arguments @('login')
    }

    Invoke-CheckedCommand `
        -Stage 'Select Azure subscription' `
        -FilePath 'az' `
        -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
    $accountResult = Invoke-CheckedCommand `
        -Stage 'Read Azure subscription' `
        -FilePath 'az' `
        -Arguments @(
            'account', 'show', '--subscription', $SubscriptionId,
            '--output', 'json'
        ) `
        -Quiet
    $account = $accountResult.Output -join "`n" | ConvertFrom-Json
    if ($account.state -ne 'Enabled') {
        throw "Subscription '$SubscriptionId' is not enabled."
    }

    $azdStatus = Invoke-CheckedCommand `
        -Stage 'Check azd authentication' `
        -FilePath 'azd' `
        -Arguments @('auth', 'login', '--check-status') `
        -AllowFailure `
        -Quiet
    if ($azdStatus.ExitCode -ne 0) {
        if ($NoPrompt) {
            throw 'azd is not authenticated. Run azd auth login before using -NoPrompt.'
        }
        Invoke-CheckedCommand -Stage 'azd login' -FilePath 'azd' -Arguments @('auth', 'login')
    }
    return $account
}

function Get-DeploymentPrincipalObjectId {
    param([object]$Account)

    if ($Account.user.type -eq 'servicePrincipal') {
        $result = Invoke-CheckedCommand `
            -Stage 'Resolve deployment service principal' `
            -FilePath 'az' `
            -Arguments @('ad', 'sp', 'show', '--id', $Account.user.name, '--query', 'id', '-o', 'tsv') `
            -Quiet
    }
    else {
        $result = Invoke-CheckedCommand `
            -Stage 'Resolve deployment user' `
            -FilePath 'az' `
            -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv') `
            -Quiet
    }
    $principalId = ($result.Output -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($principalId)) {
        throw 'Unable to resolve the deployment principal object ID.'
    }
    return $principalId
}

function Ensure-AzdExtensions {
    param(
        [string]$DeploymentMode,
        [string]$ProjectDirectory
    )

    $requiredAgentVersion = if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        '1.0.0-beta.7'
    }
    else {
        '1.0.0-beta.4'
    }
    $extensionsResult = Invoke-CheckedCommand `
        -Stage 'Inspect azd extensions' `
        -FilePath 'azd' `
        -Arguments @('extension', 'list', '--output', 'json') `
        -WorkingDirectory $ProjectDirectory `
        -Quiet
    $extensions = @($extensionsResult.Output -join "`n" | ConvertFrom-Json)
    $agents = @($extensions | Where-Object { $_.id -eq 'azure.ai.agents' })
    $projects = @($extensions | Where-Object { $_.id -eq 'azure.ai.projects' })
    $agentNeedsInstall = $agents.Count -eq 0 -or
        [string]::IsNullOrWhiteSpace($agents[0].installedVersion) -or
        ($DeploymentMode -eq 'ExistingPrivateAcr' -and
            $agents[0].installedVersion -ne $requiredAgentVersion)
    if ($agentNeedsInstall) {
        Invoke-CheckedCommand `
            -Stage 'Install Foundry agent extension' `
            -FilePath 'azd' `
            -Arguments @(
                'extension', 'install', 'azure.ai.agents',
                '--version', $requiredAgentVersion,
                '--force', '--no-prompt'
            ) `
            -WorkingDirectory $ProjectDirectory | Out-Null
    }
    if ($projects.Count -eq 0 -or [string]::IsNullOrWhiteSpace($projects[0].installedVersion)) {
        Invoke-CheckedCommand `
            -Stage 'Install Foundry project extension' `
            -FilePath 'azd' `
            -Arguments @(
                'extension', 'install', 'azure.ai.projects',
                '--force', '--no-prompt'
            ) `
            -WorkingDirectory $ProjectDirectory | Out-Null
    }
}

function Ensure-RequiredProviders {
    param(
        [string]$SubscriptionId,
        [string]$DeploymentMode
    )

    $validation = Get-AzureProviderValidation `
        -SubscriptionId $SubscriptionId `
        -DeploymentMode $DeploymentMode
    foreach ($record in $validation.providerRegistrations) {
        if ($record.registrationState -ne 'Registered') {
            Invoke-CheckedCommand `
                -Stage "Register provider $($record.namespace)" `
                -FilePath 'az' `
                -Arguments @(
                    'provider', 'register', '--subscription', $SubscriptionId,
                    '--namespace', $record.namespace, '--wait'
                ) | Out-Null
            $record.registrationState = 'Registered'
        }
    }
    if (@($validation.searchLocations).Count -eq 0) {
        $searchRecord = Get-AzureSearchProviderRecord -SubscriptionId $SubscriptionId
        $validation.searchLocations = @($searchRecord.searchLocations)
    }
    Assert-AzureProviderValidation `
        -Validation $validation `
        -DeploymentMode $DeploymentMode
    return $validation
}

function Test-ResourceGroupExists {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName
    )
    $result = Invoke-CheckedCommand `
        -Stage 'Check resource group' `
        -FilePath 'az' `
        -Arguments @(
            'group', 'exists', '--subscription', $SubscriptionId,
            '--name', $ResourceGroupName, '-o', 'tsv'
        ) `
        -Quiet
    return (($result.Output -join '').Trim().ToLowerInvariant() -eq 'true')
}

function Assert-TemplateResourceGroupOwnership {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName
    )
    $result = Invoke-CheckedCommand `
        -Stage 'Verify resource group ownership' `
        -FilePath 'az' `
        -Arguments @(
            'group', 'show', '--subscription', $SubscriptionId,
            '--name', $ResourceGroupName, '--output', 'json'
        ) `
        -Quiet
    $group = $result.Output -join "`n" | ConvertFrom-Json
    if ($group.tags.'resource-group-ownership' -ne 'template-created' -or
        $group.tags.'solution-template' -ne 'foundry-private-hosted-agent' -or
        $group.tags.'azd-env-name' -ne $EnvironmentName) {
        throw "Resource group '$ResourceGroupName' exists without matching template ownership metadata."
    }
}

function Initialize-AzdEnvironment {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$SubscriptionId,
        [string]$Location,
        [hashtable]$Values,
        [hashtable]$CurrentValues = @{},
        [string[]]$EnvironmentNames
    )

    $environmentNames = if ($PSBoundParameters.ContainsKey('EnvironmentNames')) {
        @($EnvironmentNames)
    }
    else {
        @(Get-AzdEnvironmentNames -ProjectDirectory $ProjectDirectory)
    }
    $exists = $EnvironmentName -in $environmentNames
    if (-not $exists) {
        Invoke-CheckedCommand `
            -Stage 'Create azd environment' `
            -FilePath 'azd' `
            -Arguments @(
                'env', 'new', $EnvironmentName,
                '--subscription', $SubscriptionId,
                '--location', $Location,
                '--no-prompt'
            ) `
            -WorkingDirectory $ProjectDirectory | Out-Null
    }
    else {
        Invoke-CheckedCommand `
            -Stage 'Select azd environment' `
            -FilePath 'azd' `
            -Arguments @('env', 'select', $EnvironmentName) `
            -WorkingDirectory $ProjectDirectory | Out-Null
    }

    $updatedValues = @{}
    foreach ($name in $CurrentValues.Keys) {
        $updatedValues[$name] = $CurrentValues[$name]
    }
    $valueNames = @($Values.Keys | Sort-Object)
    for ($index = 0; $index -lt $valueNames.Count; $index++) {
        $name = $valueNames[$index]
        $value = [string]$Values[$name]
        $updatedValues[$name] = $value
        if ($CurrentValues.ContainsKey($name) -and
            [string]$CurrentValues[$name] -eq $value) {
            Write-Host "[SKIP] azd value $name is already current."
            continue
        }
        Invoke-CheckedCommand `
            -Stage "Set azd value $name ($($index + 1)/$($valueNames.Count))" `
            -FilePath 'azd' `
            -Arguments @('env', 'set', $name, $value, '-e', $EnvironmentName) `
            -WorkingDirectory $ProjectDirectory `
            -Quiet `
            -RedactArgumentIndexes @(3) | Out-Null
    }
    return $updatedValues
}

function Assert-SafeProvisionPreview {
    param(
        [string[]]$PreviewOutput,
        [string]$DeploymentMode
    )
    $preview = $PreviewOutput -join "`n"
    if ($preview -match '(?im)^\s*(Delete|Replace)\s*:' -or
        $preview -match '(?im)^\s*[-!]\s+.*\b(Delete|Replace)\b' -or
        $preview -match '(?i)\b(to delete|to replace)\b') {
        throw 'Provision preview contains a delete or replacement operation.'
    }
    if ($DeploymentMode -eq 'ExistingPrivateAcr' -and
        ($preview -match '(?im)^\s*(Create|Modify|Delete|Replace)\s*:\s*Azure Container Registry\b' -or
            $preview -match '(?im)^\s*[+~\-!]\s+Microsoft\.ContainerRegistry/registries(?:/|@|\s)')) {
        throw 'Provision preview attempts to modify the enterprise-owned ACR.'
    }
    if ($DeploymentMode -eq 'ExistingPrivateAcr' -and
        $preview -match '(?im)^\s*[+~\-!]\s+.*Microsoft\.Authorization/roleAssignments(?:/|@|\s).*(Container Registry|AcrPull)') {
        throw 'Provision preview attempts to modify enterprise-owned ACR IAM.'
    }
}

function Wait-ForAgentActive {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$ServiceName,
        [string]$ExpectedVersion,
        [int]$Attempts = 20,
        [int]$DelaySeconds = 15
    )

    $values = Get-AzdEnvironmentValues `
        -ProjectDirectory $ProjectDirectory `
        -EnvironmentName $EnvironmentName
    $projectEndpoint = $values['AZURE_AI_PROJECT_ENDPOINT']
    if ([string]::IsNullOrWhiteSpace($projectEndpoint)) {
        throw 'AZURE_AI_PROJECT_ENDPOINT is required for exact Agent version validation.'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        $latest = Get-AgentRecord `
            -ProjectDirectory $ProjectDirectory `
            -EnvironmentName $EnvironmentName `
            -ServiceName $ServiceName
        $ExpectedVersion = [string]$latest.version
    }
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $agent = Invoke-FoundryAgentApi `
            -Uri "$($projectEndpoint.TrimEnd('/'))/agents/$ServiceName/versions/$ExpectedVersion`?api-version=v1"
        if ($agent.status -in @('active', 'deployed') -and
            [string]$agent.version -eq [string]$ExpectedVersion) {
            return $agent
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    throw "Hosted Agent '$ServiceName' did not reach the expected active version '$ExpectedVersion'."
}

function Invoke-FoundryAgentApi {
    param([Parameter(Mandatory)][string]$Uri)
    $tokenResult = Invoke-CheckedCommand `
        -Stage 'Acquire Foundry API token' `
        -FilePath 'az' `
        -Arguments @(
            'account', 'get-access-token',
            '--resource', 'https://ai.azure.com',
            '--query', 'accessToken', '--output', 'tsv'
        ) `
        -Quiet
    $token = ($tokenResult.Output -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to acquire a Foundry API token.'
    }
    try {
        return Invoke-RestMethod `
            -Method Get `
            -Uri $Uri `
            -Headers @{ Authorization = "Bearer $token" }
    }
    finally {
        Remove-Variable token -ErrorAction SilentlyContinue
    }
}

function Get-AgentRecord {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$ServiceName
    )

    $show = Invoke-CheckedCommand `
        -Stage 'Read Hosted Agent' `
        -FilePath 'azd' `
        -Arguments @('ai', 'agent', 'show', $ServiceName, '--output', 'json') `
        -WorkingDirectory $ProjectDirectory `
        -AllowFailure `
        -Quiet
    if ($show.ExitCode -eq 0) {
        return $show.Output -join "`n" | ConvertFrom-Json
    }

    $values = Get-AzdEnvironmentValues `
        -ProjectDirectory $ProjectDirectory `
        -EnvironmentName $EnvironmentName
    $projectEndpoint = $values['AZURE_AI_PROJECT_ENDPOINT']
    if ([string]::IsNullOrWhiteSpace($projectEndpoint)) {
        throw "Hosted Agent '$ServiceName' cannot be resolved without AZURE_AI_PROJECT_ENDPOINT."
    }
    $response = Invoke-FoundryAgentApi `
        -Uri "$($projectEndpoint.TrimEnd('/'))/agents/$ServiceName/versions?api-version=v1"
    $items = if ($response.PSObject.Properties['data']) {
        @($response.data)
    }
    elseif ($response.PSObject.Properties['value']) {
        @($response.value)
    }
    else {
        @($response)
    }
    if ($items.Count -eq 0) {
        throw "Hosted Agent '$ServiceName' has no versions."
    }
    return $items |
        Sort-Object { [int]$_.version } -Descending |
        Select-Object -First 1
}

function Get-AgentPrincipalId {
    param([object]$Agent)
    foreach ($path in @(
        @('instance_identity', 'principal_id'),
        @('identity', 'principalId'),
        @('identity', 'principal_id'),
        @('agent_identity', 'principal_id'),
        @('agentIdentity', 'principalId')
    )) {
        $value = $Agent
        foreach ($name in $path) {
            if ($null -eq $value) {
                break
            }
            $property = $value.PSObject.Properties[$name]
            if ($null -eq $property) {
                $value = $null
                break
            }
            $value = $property.Value
        }
        if ($value) {
            return [string]$value
        }
    }
    throw 'The Hosted Agent instance identity principal ID is unavailable.'
}

function Get-AcrDnsSuffixes {
    param(
        [string]$ContainerRegistryResourceId,
        [string]$ContainerRegistryEndpoint
    )
    $resourceIdPattern = '(?i)^/subscriptions/(?<subscription>[^/]+)/resourceGroups/(?<resourceGroup>[^/]+)/providers/Microsoft\.ContainerRegistry/registries/(?<name>[^/]+)$'
    if ($ContainerRegistryResourceId -notmatch $resourceIdPattern) {
        throw 'ContainerRegistryResourceId is not a canonical ACR ARM resource ID.'
    }
    $result = Invoke-CheckedCommand `
        -Stage 'Read ACR data endpoints' `
        -FilePath 'az' `
        -Arguments @(
            'acr', 'show',
            '--subscription', $Matches.subscription,
            '--resource-group', $Matches.resourceGroup,
            '--name', $Matches.name,
            '--query', 'dataEndpointHostNames', '--output', 'json',
            '--only-show-errors'
        ) `
        -Quiet
    $hosts = @($ContainerRegistryEndpoint)
    $dataEndpoints = @($result.Output -join "`n" | ConvertFrom-Json)
    $hosts += $dataEndpoints
    $privateHosts = @($hosts | ForEach-Object {
        $_ -replace '\.azurecr\.io$', '.privatelink.azurecr.io'
    })
    return @($hosts + $privateHosts | Sort-Object -Unique)
}

function Test-InfrastructureReady {
    param(
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [string]$DeploymentMode,
        [string]$ValidatorDirectory
    )

    try {
        $values = Get-AzdEnvironmentValues `
            -ProjectDirectory $ProjectDirectory `
            -EnvironmentName $EnvironmentName
    }
    catch {
        return $false
    }
    $requiredIds = @(
        'AZURE_AI_ACCOUNT_ID',
        'AZURE_SEARCH_SERVICE_ID',
        'AZURE_KEY_VAULT_ID',
        'AZURE_VNET_ID'
    )
    foreach ($name in $requiredIds) {
        if (-not $values.ContainsKey($name) -or
            [string]::IsNullOrWhiteSpace($values[$name])) {
            return $false
        }
        $result = Invoke-CheckedCommand `
            -Stage "Inspect live resource $name" `
            -FilePath 'az' `
            -Arguments @(
                'resource', 'show', '--ids', $values[$name],
                '--output', 'none', '--only-show-errors'
            ) `
            -AllowFailure `
            -Quiet
        if ($result.ExitCode -ne 0) {
            return $false
        }
    }
    if (-not $values.ContainsKey('AZURE_AI_PROJECT_ID') -or
        [string]::IsNullOrWhiteSpace($values['AZURE_AI_PROJECT_ID'])) {
        return $false
    }
    $project = Invoke-CheckedCommand `
        -Stage 'Inspect live Foundry project' `
        -FilePath 'az' `
        -Arguments @(
            'resource', 'show', '--ids', $values['AZURE_AI_PROJECT_ID'],
            '--api-version', '2025-04-01-preview',
            '--output', 'none', '--only-show-errors'
        ) `
        -AllowFailure `
        -Quiet
    if ($project.ExitCode -ne 0) {
        return $false
    }
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        $connectionName = $values['AZURE_AI_PROJECT_ACR_CONNECTION_NAME']
        if ([string]::IsNullOrWhiteSpace($connectionName)) {
            return $false
        }
        $connection = Invoke-CheckedCommand `
            -Stage 'Inspect live Foundry ACR connection' `
            -FilePath 'az' `
            -Arguments @(
                'resource', 'show',
                '--ids', "$($values['AZURE_AI_PROJECT_ID'])/connections/$connectionName",
                '--api-version', '2025-04-01-preview',
                '--output', 'none', '--only-show-errors'
            ) `
            -AllowFailure `
            -Quiet
        if ($connection.ExitCode -ne 0) {
            return $false
        }
    }
    foreach ($validator in @(
        'validate-infrastructure.ps1',
        'validate-rbac.ps1',
        'validate-cmk.ps1',
        'validate-network.ps1'
    )) {
        $validation = Invoke-CheckedCommand `
            -Stage "Check resume health with $validator" `
            -FilePath 'pwsh' `
            -Arguments @('-NoProfile', '-File', (Join-Path $ValidatorDirectory $validator)) `
            -WorkingDirectory $ProjectDirectory `
            -AllowFailure `
            -Quiet
        if ($validation.ExitCode -ne 0) {
            return $false
        }
    }
    if ($DeploymentMode -eq 'ExistingPrivateAcr') {
        $acrValidation = Invoke-CheckedCommand `
            -Stage 'Check resume health for Foundry ACR connection' `
            -FilePath 'pwsh' `
            -Arguments @(
                '-NoProfile', '-File',
                (Join-Path $ValidatorDirectory 'validate-existing-acr.ps1'),
                '-ValidateConnection'
            ) `
            -WorkingDirectory $ProjectDirectory `
            -AllowFailure `
            -Quiet
        if ($acrValidation.ExitCode -ne 0) {
            return $false
        }
    }
    return $true
}

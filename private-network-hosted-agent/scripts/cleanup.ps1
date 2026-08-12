[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$')]
    [string]$EnvironmentName,
    [switch]$Force,
    [switch]$RemoveLocalEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot
$capabilityHostApiVersion = '2025-04-01-preview'
$agentSubnetName = 'snet-agent'
$pollIntervalSeconds = 15
$accountAbsenceConfirmationCount = 3
$capabilityHostTimeout = [TimeSpan]::FromMinutes(30)
$accountTimeout = [TimeSpan]::FromMinutes(30)
$salTimeout = [TimeSpan]::FromMinutes(30)
$resourceGroupTimeout = [TimeSpan]::FromHours(1)
$explicitStageConfirmation = $PSBoundParameters.ContainsKey('Confirm') -and
    [bool]$PSBoundParameters['Confirm']
if (-not $explicitStageConfirmation) {
    $ConfirmPreference = 'None'
}

function Invoke-CleanupCommand {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$WorkingDirectory = $repositoryRoot,
        [switch]$AllowFailure
    )

    Push-Location $WorkingDirectory
    try {
        $global:LASTEXITCODE = 0
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $result = [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Stage failed with exit code $exitCode. $($output -join ' ')"
    }
    return $result
}

function Test-NotFoundResult {
    param([Parameter(Mandatory)]$Result)
    return $Result.ExitCode -ne 0 -and
        (($Result.Output -join ' ') -match
            '(?i)(^|\D)404(\D|$)|ResourceNotFound|could not be found|not found')
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowNotFound
    )

    $result = Invoke-CleanupCommand `
        -Stage $Stage `
        -FilePath 'az' `
        -Arguments ($Arguments + @('--output', 'json', '--only-show-errors')) `
        -AllowFailure
    if ($result.ExitCode -ne 0) {
        if ($AllowNotFound -and (Test-NotFoundResult -Result $result)) {
            return $null
        }
        throw "$Stage failed with exit code $($result.ExitCode). $($result.Output -join ' ')"
    }
    $json = ($result.Output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }
    return $json | ConvertFrom-Json
}

function Invoke-AzMutation {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowNotFound,
        [switch]$AllowConflict
    )

    $result = Invoke-CleanupCommand `
        -Stage $Stage `
        -FilePath 'az' `
        -Arguments ($Arguments + @('--only-show-errors')) `
        -AllowFailure
    if ($result.ExitCode -eq 0) {
        return $true
    }
    if ($AllowNotFound -and (Test-NotFoundResult -Result $result)) {
        return $false
    }
    if ($AllowConflict -and
        (($result.Output -join ' ') -match '(?i)RequestConflict|Conflict')) {
        return $false
    }
    throw "$Stage failed with exit code $($result.ExitCode). $($result.Output -join ' ')"
}

function Get-AzdEnvironmentNames {
    param([Parameter(Mandatory)][string]$ProjectDirectory)

    $result = Invoke-CleanupCommand `
        -Stage "List azd environments in '$ProjectDirectory'" `
        -FilePath 'azd' `
        -Arguments @('env', 'list', '--output', 'json') `
        -WorkingDirectory $ProjectDirectory
    $environments = @($result.Output -join "`n" | ConvertFrom-Json)
    return @($environments | ForEach-Object { [string]$_.Name })
}

function Resolve-CleanupEnvironment {
    param([Parameter(Mandatory)][string]$Name)

    $candidates = @(
        [pscustomobject]@{
            Mode = 'Source'
            Directory = $repositoryRoot
        },
        [pscustomobject]@{
            Mode = 'ExistingPrivateAcr'
            Directory = Join-Path $repositoryRoot 'scenarios/existing-private-acr'
        }
    )
    $matches = @($candidates | Where-Object {
        $Name -in @(Get-AzdEnvironmentNames -ProjectDirectory $_.Directory)
    })
    if ($matches.Count -eq 0) {
        throw "azd environment '$Name' was not found in the Source or Existing Private ACR project."
    }
    if ($matches.Count -gt 1) {
        throw "azd environment '$Name' exists in both project directories. Cleanup refuses the ambiguous target."
    }
    return $matches[0]
}

function Get-CleanupEnvironmentValues {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$Name
    )

    $result = Invoke-CleanupCommand `
        -Stage "Read azd environment '$Name'" `
        -FilePath 'azd' `
        -Arguments @('env', 'get-values', '-e', $Name, '--output', 'json') `
        -WorkingDirectory $ProjectDirectory
    return $result.Output -join "`n" | ConvertFrom-Json -AsHashtable
}

function Set-AzdCleanupProgress {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][hashtable]$Values
    )
    Invoke-CleanupCommand `
        -Stage "Persist cleanup progress '$Key'" `
        -FilePath 'azd' `
        -Arguments @('env', 'set', $Key, $Value, '-e', $Name) `
        -WorkingDirectory $ProjectDirectory | Out-Null
    $Values[$Key] = $Value
}

function Assert-RequiredEnvironmentValues {
    param([Parameter(Mandatory)][hashtable]$Values)

    $required = @(
        'AZURE_SUBSCRIPTION_ID',
        'AZURE_RESOURCE_GROUP',
        'AZURE_AI_ACCOUNT_NAME',
        'AZURE_AI_ACCOUNT_ID',
        'AZURE_AI_PROJECT_NAME',
        'AZURE_AI_PROJECT_ID',
        'AZURE_LOCATION',
        'AZURE_VNET_ID',
        'CONNECTIVITY_MODE'
    )
    $missing = @($required | Where-Object {
        -not $Values.ContainsKey($_) -or
        [string]::IsNullOrWhiteSpace([string]$Values[$_])
    })
    if ($missing.Count -gt 0) {
        throw "azd environment '$EnvironmentName' is missing required cleanup values: $($missing -join ', ')."
    }
}

function Assert-CanonicalResourceId {
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not $Actual.TrimEnd('/').Equals(
            $Expected.TrimEnd('/'),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label does not match the dedicated environment boundary."
    }
}

function Assert-OwnedResourceRecord {
    param(
        [Parameter(Mandatory)]$Resource,
        [Parameter(Mandatory)][string]$ExpectedId,
        [Parameter(Mandatory)][string]$Label
    )
    $idProperty = $Resource.PSObject.Properties['id']
    $tagsProperty = $Resource.PSObject.Properties['tags']
    if ($null -eq $idProperty -or $null -eq $tagsProperty) {
        throw "$Label is missing its ARM ID or ownership tags."
    }
    Assert-CanonicalResourceId `
        -Actual ([string]$idProperty.Value) `
        -Expected $ExpectedId `
        -Label $Label
    if ($tagsProperty.Value.'solution-template' -ne
            'foundry-private-hosted-agent' -or
        $tagsProperty.Value.'azd-env-name' -ne $EnvironmentName) {
        throw "$Label does not have the exact template ownership metadata."
    }
}

function Get-ArmCollectionValues {
    param($Response)
    if ($null -eq $Response) {
        return @()
    }
    $valueProperty = $Response.PSObject.Properties['value']
    if ($null -eq $valueProperty) {
        return @()
    }
    return @($valueProperty.Value)
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][TimeSpan]$Timeout,
        [Parameter(Mandatory)][scriptblock]$Condition
    )

    $deadline = [DateTimeOffset]::UtcNow.Add($Timeout)
    do {
        if (& $Condition) {
            return
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Timed out waiting for $Description. Rerun cleanup with the same environment after Azure finishes the asynchronous operation."
        }
        Write-Host "[WAITING] $Description"
        Start-Sleep -Seconds $pollIntervalSeconds
    } while ($true)
}

function Get-ResourceGroupResourceKeys {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName
    )

    $resources = @(Invoke-AzJson `
        -Stage "List resources in '$ResourceGroupName'" `
        -Arguments @(
            'resource', 'list',
            '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroupName
        ) `
        -AllowNotFound)
    return @($resources | ForEach-Object {
        "$([string]$_.type)/$([string]$_.name)"
    } | Sort-Object)
}

function Wait-ForResourceGroupDeletion {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$InitialResourceKeys
    )

    $startedAt = [DateTimeOffset]::UtcNow
    $deadline = $startedAt.Add($resourceGroupTimeout)
    $previousResourceKeys = @($InitialResourceKeys)
    do {
        $exists = Invoke-CleanupCommand `
            -Stage "Check resource group '$ResourceGroupName'" `
            -FilePath 'az' `
            -Arguments @(
                'group', 'exists',
                '--subscription', $SubscriptionId,
                '--name', $ResourceGroupName,
                '--output', 'tsv',
                '--only-show-errors'
            )
        if (($exists.Output -join '').Trim() -eq 'false') {
            return
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Timed out waiting for resource group '$ResourceGroupName' deletion. Rerun cleanup with the same environment after Azure finishes the asynchronous operation."
        }

        $currentResourceKeys = @(Get-ResourceGroupResourceKeys `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName)
        $deletedResourceKeys = @($previousResourceKeys | Where-Object {
            $currentResourceKeys -notcontains $_
        })
        if ($deletedResourceKeys.Count -gt 0) {
            Write-Host "[PROGRESS] Deleted $($deletedResourceKeys.Count) resource(s) since the previous check:"
            foreach ($resourceKey in $deletedResourceKeys) {
                Write-Host "  - $resourceKey"
            }
            Write-Host "[REMAINING] $($currentResourceKeys.Count) resource(s):"
            foreach ($resourceKey in $currentResourceKeys) {
                Write-Host "  - $resourceKey"
            }
        }

        $elapsed = [DateTimeOffset]::UtcNow - $startedAt
        Write-Host (
            "[WAITING] resource group '$ResourceGroupName' deletion; " +
            "$($currentResourceKeys.Count) resource(s) remain; " +
            "elapsed $([Math]::Floor($elapsed.TotalSeconds))s"
        )
        $previousResourceKeys = $currentResourceKeys
        Start-Sleep -Seconds $pollIntervalSeconds
    } while ($true)
}

function Get-CapabilityHosts {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AccountName,
        [string]$ProjectName = ''
    )

    $scopeUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AccountName"
    $scopeLabel = "account '$AccountName'"
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $scopeUrl += "/projects/$([Uri]::EscapeDataString($ProjectName))"
        $scopeLabel = "project '$ProjectName'"
    }
    $response = Invoke-AzJson `
        -Stage "List Capability Hosts for $scopeLabel" `
        -Arguments @(
            'rest', '--method', 'get',
            '--url', "$scopeUrl/capabilityHosts?api-version=$capabilityHostApiVersion"
        ) `
        -AllowNotFound
    return @(Get-ArmCollectionValues -Response $response)
}

function Remove-CapabilityHosts {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AccountName,
        [string]$ProjectName = ''
    )

    $scopeUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AccountName"
    $scopeLabel = "account '$AccountName'"
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $scopeUrl += "/projects/$([Uri]::EscapeDataString($ProjectName))"
        $scopeLabel = "project '$ProjectName'"
    }
    $hostScope = @{
        SubscriptionId = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        AccountName = $AccountName
        ProjectName = $ProjectName
    }

    foreach ($hostRecord in @(Get-CapabilityHosts @hostScope)) {
        $hostName = [string]$hostRecord.name
        Invoke-AzMutation `
            -Stage "Delete Capability Host '$hostName' from $scopeLabel" `
            -Arguments @(
                'rest', '--method', 'delete',
                '--url', "$scopeUrl/capabilityHosts/$([Uri]::EscapeDataString($hostName))?api-version=$capabilityHostApiVersion"
            ) `
            -AllowNotFound | Out-Null
    }
    Wait-Until `
        -Description "Capability Hosts for $scopeLabel to disappear" `
        -Timeout $capabilityHostTimeout `
        -Condition {
            @(Get-CapabilityHosts @hostScope).Count -eq 0
        }
}

function Get-OwnedFoundryProjectNames {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$AccountName,
        [Parameter(Mandatory)][string]$AccountId
    )

    $projectPrefix = "$($AccountId.TrimEnd('/'))/projects/"
    $response = Invoke-AzJson `
        -Stage "List Foundry projects for '$AccountName'" `
        -Arguments @(
            'rest', '--method', 'get',
            '--url', "https://management.azure.com$AccountId/projects?api-version=$capabilityHostApiVersion"
        ) `
        -AllowNotFound
    $projects = @(Get-ArmCollectionValues -Response $response)

    foreach ($project in $projects) {
        $idProperty = $project.PSObject.Properties['id']
        if ($null -eq $idProperty) {
            throw 'Foundry project is missing its ARM ID.'
        }

        $projectId = [string]$idProperty.Value
        if (-not $projectId.StartsWith(
                $projectPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Foundry project does not match the dedicated environment boundary.'
        }

        $projectName = $projectId.Substring($projectPrefix.Length)
        if ([string]::IsNullOrWhiteSpace($projectName) -or $projectName.Contains('/')) {
            throw 'Foundry project ARM ID does not contain a canonical project name.'
        }

        Assert-OwnedResourceRecord `
            -Resource $project `
            -ExpectedId "$projectPrefix$projectName" `
            -Label "Foundry project '$projectName'"

        $projectName
    }
}

function Remove-FoundryProject {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AccountName,
        [string]$ProjectName
    )
    $encodedProjectName = [Uri]::EscapeDataString($ProjectName)
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AccountName/projects/${encodedProjectName}?api-version=$capabilityHostApiVersion"
    Invoke-AzMutation `
        -Stage "Delete Foundry project '$ProjectName'" `
        -Arguments @('rest', '--method', 'delete', '--url', $url) `
        -AllowNotFound | Out-Null
    Wait-Until `
        -Description "Foundry project '$ProjectName' to disappear" `
        -Timeout $accountTimeout `
        -Condition {
            $project = Invoke-AzJson `
                -Stage "Read Foundry project '$ProjectName'" `
                -Arguments @('rest', '--method', 'get', '--url', $url) `
                -AllowNotFound
            return $null -eq $project
        }
}

function Get-FoundryAccount {
        param(
            [string]$SubscriptionId,
            [string]$ResourceGroupName,
            [string]$AccountName
        )
        return Invoke-AzJson `
            -Stage "Read Foundry account '$AccountName'" `
            -Arguments @(
                'cognitiveservices', 'account', 'show',
                '--subscription', $SubscriptionId,
                '--resource-group', $ResourceGroupName,
                '--name', $AccountName
            ) `
            -AllowNotFound
}

function Get-DeletedFoundryAccount {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AccountName,
        [string]$Location
    )
    $account = Invoke-AzJson `
        -Stage "Read soft-deleted Foundry account '$AccountName'" `
        -Arguments @(
            'cognitiveservices', 'account', 'show-deleted',
            '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroupName,
            '--location', $Location,
            '--name', $AccountName
        ) `
        -AllowNotFound
    if ($null -eq $account) {
        return $null
    }
    if ([string]$account.name -ine $AccountName -or
        [string]$account.location -ine $Location -or
        ($null -ne $account.PSObject.Properties['resourceGroup'] -and
            -not [string]::IsNullOrWhiteSpace([string]$account.resourceGroup) -and
            [string]$account.resourceGroup -ine $ResourceGroupName)) {
        throw "Soft-deleted Foundry account '$AccountName' does not match the dedicated environment boundary."
    }
    return $account
}

function Remove-AndPurgeFoundryAccount {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AccountName,
        [string]$Location,
        [string]$ProjectDirectory,
        [string]$EnvironmentName,
        [hashtable]$EnvironmentValues
    )

    $accountScope = @{
        SubscriptionId = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        AccountName = $AccountName
    }
    $deletedAccountScope = $accountScope.Clone()
    $deletedAccountScope['Location'] = $Location
    $progressScope = @{
        ProjectDirectory = $ProjectDirectory
        Name = $EnvironmentName
        Values = $EnvironmentValues
    }
    $account = Get-FoundryAccount @accountScope
    $incarnation = [string]$EnvironmentValues[
        'FPHA_CLEANUP_ACCOUNT_INCARNATION'
    ]
    if ($null -ne $account) {
        $systemDataProperty = $account.PSObject.Properties['systemData']
        $createdAtProperty = if ($null -ne $systemDataProperty -and
            $null -ne $systemDataProperty.Value) {
            $systemDataProperty.Value.PSObject.Properties['createdAt']
        }
        else {
            $null
        }
        if ($null -eq $createdAtProperty -or
            [string]::IsNullOrWhiteSpace([string]$createdAtProperty.Value)) {
            throw "Foundry account '$AccountName' is missing systemData.createdAt; cleanup cannot bind progress to this account incarnation."
        }
        $currentIncarnation = "$AccountName@$([string]$createdAtProperty.Value)"
        if ($incarnation -ne $currentIncarnation) {
            Set-AzdCleanupProgress @progressScope `
                -Key 'FPHA_CLEANUP_ACCOUNT_INCARNATION' `
                -Value $currentIncarnation
            $incarnation = $currentIncarnation
        }
    }
    if ([string]::IsNullOrWhiteSpace($incarnation)) {
        throw "Foundry account '$AccountName' is absent without an account-incarnation cleanup marker. Cleanup cannot prove purge progress."
    }
    $purgeRequested = [string]$EnvironmentValues[
        'FPHA_CLEANUP_ACCOUNT_PURGE_REQUESTED'
    ] -eq $incarnation
    if ($null -ne $account -and $purgeRequested) {
        throw "Foundry account '$AccountName' exists after cleanup recorded a purge. Refusing to delete a potentially recreated account."
    }
    if ($null -ne $account) {
        Invoke-AzMutation `
            -Stage "Delete Foundry account '$AccountName'" `
            -Arguments @(
                'cognitiveservices', 'account', 'delete',
                '--subscription', $SubscriptionId,
                '--resource-group', $ResourceGroupName,
                '--name', $AccountName
            ) `
            -AllowNotFound | Out-Null
        Wait-Until `
            -Description "Foundry account '$AccountName' to leave the active resource list" `
            -Timeout $accountTimeout `
            -Condition {
                $null -eq (Get-FoundryAccount @accountScope)
            }
    }

    $deadline = [DateTimeOffset]::UtcNow.Add($accountTimeout)
    $startedAt = [DateTimeOffset]::UtcNow
    $absenceObservations = 0
    do {
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Timed out verifying Azure state for Foundry account '$AccountName'. Cleanup will not continue while an active or soft-deleted account may remain; rerun with the same environment."
        }
        $elapsed = [DateTimeOffset]::UtcNow - $startedAt
        $activeAccount = Get-FoundryAccount @accountScope
        if ($null -ne $activeAccount) {
            $absenceObservations = 0
            $createdAt = [string]$activeAccount.systemData.createdAt
            if ([string]::IsNullOrWhiteSpace($createdAt) -or
                "$AccountName@$createdAt" -ne $incarnation) {
                throw "Foundry account '$AccountName' was recreated while cleanup was in progress."
            }
            Write-Host (
                "[WAITING] Active Foundry account '$AccountName' still exists " +
                "(elapsed $([Math]::Floor($elapsed.TotalSeconds))s)"
            )
            Start-Sleep -Seconds $pollIntervalSeconds
            continue
        }
        $deletedAccount = Get-DeletedFoundryAccount @deletedAccountScope
        if ($null -ne $deletedAccount) {
            $absenceObservations = 0
            if (-not $purgeRequested) {
                $purgeAccepted = Invoke-AzMutation `
                    -Stage "Purge Foundry account '$AccountName'" `
                    -Arguments @(
                        'cognitiveservices', 'account', 'purge',
                        '--subscription', $SubscriptionId,
                        '--resource-group', $ResourceGroupName,
                        '--location', $Location,
                        '--name', $AccountName
                    ) `
                    -AllowNotFound `
                    -AllowConflict
                if ($purgeAccepted) {
                    Set-AzdCleanupProgress @progressScope `
                        -Key 'FPHA_CLEANUP_ACCOUNT_PURGE_REQUESTED' `
                        -Value $incarnation
                    $purgeRequested = $true
                }
            }
            Write-Host (
                "[WAITING] Soft-deleted Foundry account '$AccountName' still exists; " +
                "purge requested=$purgeRequested " +
                "(elapsed $([Math]::Floor($elapsed.TotalSeconds))s)"
            )
        }
        else {
            $absenceObservations++
            if ($absenceObservations -ge $accountAbsenceConfirmationCount) {
                Write-Host "[STATE] Foundry account '$AccountName' is absent from active and soft-deleted Azure resources."
                return
            }
            Write-Host (
                "[VERIFYING] Foundry account '$AccountName' is absent from active and " +
                "soft-deleted resources ($absenceObservations/" +
                "$accountAbsenceConfirmationCount observations; " +
                "elapsed $([Math]::Floor($elapsed.TotalSeconds))s)"
            )
        }
        Start-Sleep -Seconds $pollIntervalSeconds
    } while ($true)
}

function Get-RemotePeering {
    param(
        [string]$RemoteSubscriptionId,
        [string]$RemoteResourceGroupName,
        [string]$RemoteVnetName,
        [string]$LocalVnetName
    )
    return Invoke-AzJson `
        -Stage "Read reciprocal peering 'to-$LocalVnetName'" `
        -Arguments @(
            'network', 'vnet', 'peering', 'show',
            '--subscription', $RemoteSubscriptionId,
            '--resource-group', $RemoteResourceGroupName,
            '--vnet-name', $RemoteVnetName,
            '--name', "to-$LocalVnetName"
        ) `
        -AllowNotFound
}

function Assert-RemotePeeringTargetsLocalVnet {
    param(
        [Parameter(Mandatory)]$Peering,
        [Parameter(Mandatory)][string]$LocalVnetId
    )
    $remoteVnetProperty = $Peering.PSObject.Properties['remoteVirtualNetwork']
    $remoteIdProperty = if ($null -ne $remoteVnetProperty) {
        $remoteVnetProperty.Value.PSObject.Properties['id']
    }
    else {
        $null
    }
    if ($null -eq $remoteIdProperty) {
        throw 'The reciprocal peering is missing its remote virtual network ID.'
    }
    Assert-CanonicalResourceId `
        -Actual ([string]$remoteIdProperty.Value) `
        -Expected $LocalVnetId `
        -Label 'Reciprocal remote-VNet peering'
}

function Remove-RemotePeering {
    param(
        [string]$RemoteSubscriptionId,
        [string]$RemoteResourceGroupName,
        [string]$RemoteVnetName,
        [string]$LocalVnetName,
        [string]$LocalVnetId
    )
    $peering = Get-RemotePeering `
        -RemoteSubscriptionId $RemoteSubscriptionId `
        -RemoteResourceGroupName $RemoteResourceGroupName `
        -RemoteVnetName $RemoteVnetName `
        -LocalVnetName $LocalVnetName
    if ($null -eq $peering) {
        return
    }
    Assert-RemotePeeringTargetsLocalVnet `
        -Peering $peering `
        -LocalVnetId $LocalVnetId
    Invoke-AzMutation `
        -Stage "Delete reciprocal peering '$RemoteVnetName/to-$LocalVnetName'" `
        -Arguments @(
            'network', 'vnet', 'peering', 'delete',
            '--subscription', $RemoteSubscriptionId,
            '--resource-group', $RemoteResourceGroupName,
            '--vnet-name', $RemoteVnetName,
            '--name', "to-$LocalVnetName"
        ) `
        -AllowNotFound | Out-Null
}

function Get-AgentSubnet {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$VnetName
    )
    return Invoke-AzJson `
        -Stage "Read Agent subnet '$agentSubnetName'" `
        -Arguments @(
            'network', 'vnet', 'subnet', 'show',
            '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroupName,
            '--vnet-name', $VnetName,
            '--name', $agentSubnetName
        ) `
        -AllowNotFound
}

function Wait-ForAgentSubnetSalRemoval {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$VnetName
    )
    Wait-Until `
        -Description "'legionservicelink' to disappear from '$agentSubnetName' (30 minute safety limit)" `
        -Timeout $salTimeout `
        -Condition {
            $subnet = Get-AgentSubnet `
                -SubscriptionId $SubscriptionId `
                -ResourceGroupName $ResourceGroupName `
                -VnetName $VnetName
            if ($null -eq $subnet) {
                return $true
            }
            $salProperty = $subnet.PSObject.Properties['serviceAssociationLinks']
            return $null -eq $salProperty -or @($salProperty.Value).Count -eq 0
        }
}

function Remove-AgentSubnetAssociations {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$VnetName
    )
    if ($null -eq (Get-AgentSubnet @PSBoundParameters)) {
        return
    }
    $baseArguments = @(
        'network', 'vnet', 'subnet', 'update',
        '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName,
        '--vnet-name', $VnetName,
        '--name', $agentSubnetName
    )
    Invoke-AzMutation `
        -Stage 'Detach Agent subnet NSG' `
        -Arguments ($baseArguments + @('--nsg', 'null')) | Out-Null
    Invoke-AzMutation `
        -Stage 'Detach Agent subnet route table' `
        -Arguments ($baseArguments + @('--route-table', 'null')) | Out-Null
    Invoke-AzMutation `
        -Stage 'Remove Agent subnet delegation' `
        -Arguments ($baseArguments + @('--remove', 'delegations')) | Out-Null
}

$environment = Resolve-CleanupEnvironment -Name $EnvironmentName
$values = Get-CleanupEnvironmentValues `
    -ProjectDirectory $environment.Directory `
    -Name $EnvironmentName
Assert-RequiredEnvironmentValues -Values $values

$subscriptionId = [string]$values['AZURE_SUBSCRIPTION_ID']
$resourceGroupName = [string]$values['AZURE_RESOURCE_GROUP']
$accountName = [string]$values['AZURE_AI_ACCOUNT_NAME']
$accountId = [string]$values['AZURE_AI_ACCOUNT_ID']
$projectName = [string]$values['AZURE_AI_PROJECT_NAME']
$projectId = [string]$values['AZURE_AI_PROJECT_ID']
$location = [string]$values['AZURE_LOCATION']
$vnetId = [string]$values['AZURE_VNET_ID']
$connectivityMode = [string]$values['CONNECTIVITY_MODE']
$expectedResourceGroupName = "rg-$EnvironmentName"

if ($connectivityMode -notin @('pointToSite', 'siteToSite', 'vnetPeering')) {
    throw "CONNECTIVITY_MODE '$connectivityMode' is unsupported."
}
if ($resourceGroupName -cne $expectedResourceGroupName) {
    throw "AZURE_RESOURCE_GROUP must be the environment-derived name '$expectedResourceGroupName'."
}
if ([string]$values['FPHA_DEPLOYMENT_MODE'] -ne $environment.Mode) {
    throw "FPHA_DEPLOYMENT_MODE does not match the unique azd project directory."
}

$resourceGroupId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
$expectedAccountId = "$resourceGroupId/providers/Microsoft.CognitiveServices/accounts/$accountName"
$expectedProjectId = "$expectedAccountId/projects/$projectName"
Assert-CanonicalResourceId -Actual $accountId -Expected $expectedAccountId -Label 'AZURE_AI_ACCOUNT_ID'
Assert-CanonicalResourceId -Actual $projectId -Expected $expectedProjectId -Label 'AZURE_AI_PROJECT_ID'

$vnetPattern = '^(?i)/subscriptions/(?<subscription>[^/]+)/resourceGroups/(?<resourceGroup>[^/]+)/providers/Microsoft\.Network/virtualNetworks/(?<name>[^/]+)$'
if ($vnetId -notmatch $vnetPattern -or
    $Matches.subscription -ine $subscriptionId -or
    $Matches.resourceGroup -ine $resourceGroupName) {
    throw 'AZURE_VNET_ID must identify the template VNet inside the dedicated environment resource group.'
}
$vnetName = $Matches.name
$accountScope = @{
    SubscriptionId = $subscriptionId
    ResourceGroupName = $resourceGroupName
    AccountName = $accountName
}
$deletedAccountScope = $accountScope.Clone()
$deletedAccountScope['Location'] = $location
$accountCleanupScope = $deletedAccountScope.Clone()
$accountCleanupScope['ProjectDirectory'] = $environment.Directory
$accountCleanupScope['EnvironmentName'] = $EnvironmentName
$accountCleanupScope['EnvironmentValues'] = $values
$projectLookupScope = $accountScope.Clone()
$projectLookupScope['AccountId'] = $accountId
$vnetScope = @{
    SubscriptionId = $subscriptionId
    ResourceGroupName = $resourceGroupName
    VnetName = $vnetName
}
$resourceGroupScope = @{
    SubscriptionId = $subscriptionId
    ResourceGroupName = $resourceGroupName
}
$remotePeering = $null
$remoteSubscriptionId = ''
$remoteResourceGroupName = ''
$remoteVnetName = ''
if ($connectivityMode -eq 'vnetPeering') {
    $remoteVnetId = [string]$values['REMOTE_VNET_RESOURCE_ID']
    if ([string]::IsNullOrWhiteSpace($remoteVnetId) -or
        $remoteVnetId -notmatch $vnetPattern) {
        throw 'REMOTE_VNET_RESOURCE_ID must identify the customer VNet for vnetPeering cleanup.'
    }
    $remoteSubscriptionId = $Matches.subscription
    $remoteResourceGroupName = $Matches.resourceGroup
    $remoteVnetName = $Matches.name
    $remotePeering = Get-RemotePeering `
        -RemoteSubscriptionId $remoteSubscriptionId `
        -RemoteResourceGroupName $remoteResourceGroupName `
        -RemoteVnetName $remoteVnetName `
        -LocalVnetName $vnetName
    if ($null -ne $remotePeering) {
        Assert-RemotePeeringTargetsLocalVnet `
            -Peering $remotePeering `
            -LocalVnetId $vnetId
    }
}

if ($values.ContainsKey('AZURE_CONTAINER_REGISTRY_RESOURCE_ID') -and
    -not [string]::IsNullOrWhiteSpace([string]$values['AZURE_CONTAINER_REGISTRY_RESOURCE_ID'])) {
    $acrId = [string]$values['AZURE_CONTAINER_REGISTRY_RESOURCE_ID']
    if ($acrId -match '(?i)^/subscriptions/[^/]+/resourceGroups/(?<acrResourceGroup>[^/]+)/' -and
        $Matches.acrResourceGroup -ieq $resourceGroupName) {
        throw 'The external ACR must not be inside the dedicated template resource group.'
    }
}

Invoke-AzJson `
    -Stage "Select Azure subscription '$subscriptionId'" `
    -Arguments @('account', 'show', '--subscription', $subscriptionId) | Out-Null
$group = Invoke-AzJson `
    -Stage "Read resource group '$resourceGroupName'" `
    -Arguments @(
        'group', 'show',
        '--subscription', $subscriptionId,
        '--name', $resourceGroupName
    ) `
    -AllowNotFound

if ($null -eq $group) {
    Write-Host "[RESUME] Azure resource group '$resourceGroupName' is already absent."
    $deletedAccount = Get-DeletedFoundryAccount @deletedAccountScope
    $hasResidualCleanup = $null -ne $deletedAccount -or
        $null -ne $remotePeering
    if ($hasResidualCleanup -and
        -not $WhatIfPreference -and
        -not $Force) {
        $confirmation = Read-Host "Type the former resource group name '$resourceGroupName' to confirm residual cleanup"
        if ($confirmation -cne $resourceGroupName) {
            throw 'Resource group confirmation did not match. Residual cleanup was not performed.'
        }
    }
    if ($null -ne $deletedAccount) {
        $completePurge = $PSCmdlet.ShouldProcess(
            $accountName,
            'Verify and complete Foundry account purge')
        if ($completePurge) {
            Remove-AndPurgeFoundryAccount @accountCleanupScope
        }
        elseif (-not $WhatIfPreference) {
            throw 'Residual cleanup stopped before Foundry account purge verification.'
        }
    }
    if ($null -ne $remotePeering) {
        $removePeering = $PSCmdlet.ShouldProcess(
                "$remoteVnetName/to-$vnetName",
                'Delete template-created reciprocal VNet peering')
        if ($removePeering) {
            Remove-RemotePeering `
                -RemoteSubscriptionId $remoteSubscriptionId `
                -RemoteResourceGroupName $remoteResourceGroupName `
                -RemoteVnetName $remoteVnetName `
                -LocalVnetName $vnetName `
                -LocalVnetId $vnetId
        }
        elseif (-not $WhatIfPreference) {
            throw 'Residual cleanup stopped before reciprocal VNet peering deletion.'
        }
    }
    $localEnvironmentStatus = 'Retained'
    if ($RemoveLocalEnvironment) {
        if ($PSCmdlet.ShouldProcess(
                "$($environment.Directory) :: $EnvironmentName",
                'Delete local azd environment')) {
            Invoke-CleanupCommand `
                -Stage "Delete local azd environment '$EnvironmentName'" `
                -FilePath 'azd' `
                -Arguments @('env', 'remove', $EnvironmentName, '--force') `
                -WorkingDirectory $environment.Directory | Out-Null
            $localEnvironmentStatus = 'Deleted'
        }
        elseif ($WhatIfPreference) {
            $localEnvironmentStatus = 'Planned'
        }
    }
    if (-not $WhatIfPreference) {
        if ($hasResidualCleanup) {
            Write-Host "[COMPLETE] Azure resource group '$resourceGroupName' is absent and residual cleanup is complete."
        }
        else {
            Write-Host "[COMPLETE] Azure resource group '$resourceGroupName' is already absent; no soft-deleted Foundry account or reciprocal VNet peering remains."
        }
    }
    [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        ProjectDirectory = $environment.Directory
        SubscriptionId = $subscriptionId
        ResourceGroupName = $resourceGroupName
        AzureResourceGroupStatus = 'Absent'
        LocalEnvironmentStatus = $localEnvironmentStatus
    }
    return
}

if ($group.tags.'resource-group-ownership' -ne 'template-created' -or
    $group.tags.'solution-template' -ne 'foundry-private-hosted-agent' -or
    $group.tags.'azd-env-name' -ne $EnvironmentName) {
    throw "Resource group '$resourceGroupName' does not have the exact template ownership metadata."
}

$liveAccount = Get-FoundryAccount @accountScope
if ($null -ne $liveAccount) {
    Assert-OwnedResourceRecord `
        -Resource $liveAccount `
        -ExpectedId $accountId `
        -Label "Foundry account '$accountName'"
}

$liveVnet = Invoke-AzJson `
    -Stage "Read solution VNet '$vnetName'" `
    -Arguments @(
        'network', 'vnet', 'show',
        '--subscription', $subscriptionId,
        '--resource-group', $resourceGroupName,
        '--name', $vnetName
    ) `
    -AllowNotFound
if ($null -ne $liveVnet) {
    Assert-OwnedResourceRecord `
        -Resource $liveVnet `
        -ExpectedId $vnetId `
        -Label "Solution VNet '$vnetName'"
}

$projects = @(Get-OwnedFoundryProjectNames @projectLookupScope)

Write-Host '[PLAN] Foundry private environment cleanup'
Write-Host "[PLAN] Environment: $EnvironmentName"
Write-Host "[PLAN] Deployment mode: $($environment.Mode)"
Write-Host "[PLAN] Subscription: $subscriptionId"
Write-Host "[PLAN] Dedicated resource group: $resourceGroupName"
Write-Host "[PLAN] Foundry account/project: $accountName / $projectName"
Write-Host "[PLAN] Solution VNet: $vnetName"
if ($null -ne $remotePeering) {
    Write-Host "[PLAN] Template-created reciprocal peering: $remoteVnetName/to-$vnetName"
}
Write-Host '[PLAN] Order: project Capability Hosts, account Capability Hosts, projects, account purge, SAL, reciprocal peering, subnet associations, resource group.'

if ($WhatIfPreference) {
    $PSCmdlet.ShouldProcess($resourceGroupName, 'Run ordered Foundry cleanup') | Out-Null
    if ($RemoveLocalEnvironment) {
        $PSCmdlet.ShouldProcess(
            "$($environment.Directory) :: $EnvironmentName",
            'Delete local azd environment after Azure cleanup') | Out-Null
    }
    return
}

if (-not $Force) {
    $confirmation = Read-Host "Type the full resource group name '$resourceGroupName' to confirm permanent cleanup"
    if ($confirmation -cne $resourceGroupName) {
        throw 'Resource group confirmation did not match. No resources were deleted.'
    }
}

if (-not $PSCmdlet.ShouldProcess($accountName, 'Delete all project Capability Hosts')) {
    throw 'Cleanup stopped before project Capability Host deletion.'
}
$projects = @(Get-OwnedFoundryProjectNames @projectLookupScope)
foreach ($project in $projects) {
    Remove-CapabilityHosts @accountScope -ProjectName $project
}

if (-not $PSCmdlet.ShouldProcess($accountName, 'Delete account Capability Hosts')) {
    throw 'Cleanup stopped before account Capability Host deletion.'
}
Remove-CapabilityHosts @accountScope

if (-not $PSCmdlet.ShouldProcess($accountName, 'Delete all Foundry projects')) {
    throw 'Cleanup stopped before Foundry project deletion.'
}
foreach ($project in $projects) {
    Remove-FoundryProject @accountScope -ProjectName $project
}

if (-not $PSCmdlet.ShouldProcess($accountName, 'Delete and purge Foundry account')) {
    throw 'Cleanup stopped before Foundry account deletion.'
}
Remove-AndPurgeFoundryAccount @accountCleanupScope

Wait-ForAgentSubnetSalRemoval @vnetScope

if ($null -ne $remotePeering) {
    if (-not $PSCmdlet.ShouldProcess(
            "$remoteVnetName/to-$vnetName",
            'Delete template-created reciprocal VNet peering')) {
        throw 'Cleanup stopped before reciprocal VNet peering deletion.'
    }
    Remove-RemotePeering `
        -RemoteSubscriptionId $remoteSubscriptionId `
        -RemoteResourceGroupName $remoteResourceGroupName `
        -RemoteVnetName $remoteVnetName `
        -LocalVnetName $vnetName `
        -LocalVnetId $vnetId
}

if (-not $PSCmdlet.ShouldProcess($agentSubnetName, 'Remove NSG, route table, and delegation')) {
    throw 'Cleanup stopped before Agent subnet association removal.'
}
Remove-AgentSubnetAssociations @vnetScope

if (-not $PSCmdlet.ShouldProcess($resourceGroupName, 'Delete dedicated resource group')) {
    throw 'Cleanup stopped before resource group deletion.'
}
$initialResourceKeys = @(Get-ResourceGroupResourceKeys @resourceGroupScope)
Write-Host "[STATE] Resource group '$resourceGroupName' contains $($initialResourceKeys.Count) resource(s) before deletion."
Invoke-AzMutation `
    -Stage "Delete resource group '$resourceGroupName'" `
    -Arguments @(
        'group', 'delete',
        '--subscription', $subscriptionId,
        '--name', $resourceGroupName,
        '--yes',
        '--no-wait'
    ) `
    -AllowNotFound | Out-Null
Wait-ForResourceGroupDeletion @resourceGroupScope `
    -InitialResourceKeys $initialResourceKeys

$localEnvironmentStatus = 'Retained'
if ($RemoveLocalEnvironment) {
    if (-not $PSCmdlet.ShouldProcess(
            "$($environment.Directory) :: $EnvironmentName",
            'Delete local azd environment')) {
        throw 'Azure cleanup completed, but local azd environment deletion was declined.'
    }
    Invoke-CleanupCommand `
        -Stage "Delete local azd environment '$EnvironmentName'" `
        -FilePath 'azd' `
        -Arguments @('env', 'remove', $EnvironmentName, '--force') `
        -WorkingDirectory $environment.Directory | Out-Null
    $localEnvironmentStatus = 'Deleted'
}

Write-Host "[COMPLETE] Azure resource group '$resourceGroupName' was deleted."
[pscustomobject]@{
    EnvironmentName = $EnvironmentName
    ProjectDirectory = $environment.Directory
    SubscriptionId = $subscriptionId
    ResourceGroupName = $resourceGroupName
    AzureResourceGroupStatus = 'Deleted'
    LocalEnvironmentStatus = $localEnvironmentStatus
}

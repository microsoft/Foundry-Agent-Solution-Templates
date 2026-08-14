Set-StrictMode -Version Latest

function Get-DiagnosticPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Protect-ArmDiagnosticText {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }
    $safe = $Value -replace '[\r\n]+', ' '
    $safe = $safe -replace '(?i)\bBearer\s+\S+', 'Bearer <redacted>'
    $safe = $safe -replace '\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '<redacted-jwt>'
    $sensitiveNames = @(
        'access[_-]?token',
        'refresh[_-]?token',
        'id[_-]?token',
        'sas[_-]?token',
        'token',
        'sas',
        'client[_-]?secret',
        'client[_-]?assertion',
        'password',
        'secret',
        'claims',
        's2s[_-]?shared[_-]?key',
        'shared[_-]?key',
        'sharedaccesskey',
        'sharedaccesssignature',
        'connection[_-]?string',
        'api[_-]?key',
        'account[_-]?key',
        'storage[_-]?key',
        'primary[_-]?key',
        'secondary[_-]?key',
        'private[_-]?key'
    ) -join '|'
    $safe = $safe -replace "(?i)(`"(?:$sensitiveNames)`"\s*:\s*)`"(?:\\.|[^`"])*`"", '$1"<redacted>"'
    $safe = $safe -replace "(?i)\b($sensitiveNames)\b\s*[:=]\s*[^\s,;]+", '$1=<redacted>'
    $safe = $safe -replace '(?i)([?&](?:sig|signature)=)[^&\s]+', '$1<redacted>'
    if ($safe.Length -gt 2048) {
        return "$($safe.Substring(0, 2048))..."
    }
    return $safe
}

function ConvertFrom-ArmCliJson {
    param([string[]]$Output)

    $lines = @($Output)
    if ($lines.Count -eq 0) {
        throw 'Azure CLI returned no JSON diagnostic payload.'
    }
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $candidate = ($lines[$index..($lines.Count - 1)] -join "`n").Trim()
        if ($candidate -notmatch '^[\[{]') {
            continue
        }
        try {
            return $candidate | ConvertFrom-Json
        }
        catch {
            continue
        }
    }
    throw 'Azure CLI returned no parseable JSON diagnostic payload.'
}

function New-ArmDeploymentReference {
    param(
        [ValidateSet('subscription', 'resourceGroup')]
        [string]$Scope,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Name,
        [string]$Id = ''
    )

    return [pscustomobject]@{
        scope = $Scope
        subscriptionId = $SubscriptionId
        resourceGroupName = $ResourceGroupName
        name = $Name
        id = $Id
    }
}

function ConvertTo-ArmDeploymentReference {
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [string]$FallbackSubscriptionId = ''
    )

    $pattern = '(?i)^/subscriptions/(?<subscription>[^/]+)(?:/resourceGroups/(?<resourceGroup>[^/]+))?/providers/Microsoft\.Resources/deployments/(?<name>[^/]+)$'
    $match = [regex]::Match($ResourceId, $pattern)
    if (-not $match.Success) {
        return $null
    }
    $resourceGroupName = $match.Groups['resourceGroup'].Value
    $scope = if ([string]::IsNullOrWhiteSpace($resourceGroupName)) {
        'subscription'
    }
    else {
        'resourceGroup'
    }
    $matchedSubscriptionId = $match.Groups['subscription'].Value
    $subscriptionId = if ([string]::IsNullOrWhiteSpace($matchedSubscriptionId)) {
        $FallbackSubscriptionId
    }
    else {
        $matchedSubscriptionId
    }
    return New-ArmDeploymentReference `
        -Scope $scope `
        -SubscriptionId $subscriptionId `
        -ResourceGroupName $resourceGroupName `
        -Name $match.Groups['name'].Value `
        -Id $ResourceId
}

function Get-AzdDeploymentReferences {
    param(
        [string[]]$Output,
        [Parameter(Mandatory)][string]$SubscriptionId
    )

    $text = ($Output -join "`n") -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    try {
        $decodedText = [Uri]::UnescapeDataString($text)
    }
    catch {
        $decodedText = $text
    }
    $references = [Collections.Generic.List[object]]::new()
    $idPattern = '(?i)/subscriptions/[^/\s"''?]+(?:/resourceGroups/[^/\s"''?]+)?/providers/Microsoft\.Resources/deployments/[^/\s"''?]+'
    foreach ($candidateText in @($text, $decodedText)) {
        foreach ($match in [regex]::Matches($candidateText, $idPattern)) {
            $reference = ConvertTo-ArmDeploymentReference `
                -ResourceId $match.Value `
                -FallbackSubscriptionId $SubscriptionId
            if ($null -ne $reference) {
                $references.Add($reference)
            }
        }
    }

    $namePatterns = @(
        '(?im)\b(?:deployment\s+name|deploymentName)["'']?\s*[:=]\s*["'']?(?<name>[A-Za-z0-9._()\-]+)',
        '(?im)\b(?:template\s+)?deployment\s+["''](?<name>[A-Za-z0-9._()\-]+)["'']'
    )
    foreach ($namePattern in $namePatterns) {
        foreach ($match in [regex]::Matches($text, $namePattern)) {
            $references.Add((New-ArmDeploymentReference `
                -Scope subscription `
                -SubscriptionId $SubscriptionId `
                -ResourceGroupName '' `
                -Name $match.Groups['name'].Value))
        }
    }

    $seen = @{}
    return @($references | Where-Object {
        $key = "$($_.scope)|$($_.resourceGroupName)|$($_.name)".ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            return $false
        }
        $seen[$key] = $true
        return $true
    })
}

function Get-ArmDeploymentOperations {
    param([Parameter(Mandatory)][object]$Reference)

    $arguments = @('deployment', 'operation')
    if ($Reference.scope -eq 'resourceGroup') {
        $arguments += @(
            'group', 'list',
            '--resource-group', $Reference.resourceGroupName
        )
    }
    else {
        $arguments += @('sub', 'list')
    }
    $arguments += @(
        '--name', $Reference.name,
        '--subscription', $Reference.subscriptionId,
        '--output', 'json',
        '--only-show-errors'
    )
    $result = Invoke-CheckedCommand `
        -Stage "Read ARM deployment operations for $($Reference.name)" `
        -FilePath 'az' `
        -Arguments $arguments `
        -Quiet `
        -AllowFailure
    if ($result.ExitCode -ne 0) {
        throw "Azure CLI exited with code $($result.ExitCode)."
    }
    return @(ConvertFrom-ArmCliJson -Output $result.Output)
}

function ConvertTo-ArmErrorLeaves {
    param(
        [object]$ErrorObject,
        [string]$DefaultCode = 'DeploymentFailed',
        [string]$DefaultMessage = '',
        [string]$DefaultTarget = ''
    )

    if ($null -eq $ErrorObject) {
        return @([pscustomobject]@{
            code = $DefaultCode
            message = $DefaultMessage
            target = $DefaultTarget
        })
    }
    if ($ErrorObject -is [string]) {
        try {
            $parsed = $ErrorObject | ConvertFrom-Json
            return @(ConvertTo-ArmErrorLeaves `
                -ErrorObject $parsed `
                -DefaultCode $DefaultCode `
                -DefaultMessage $DefaultMessage `
                -DefaultTarget $DefaultTarget)
        }
        catch {
            return @([pscustomobject]@{
                code = $DefaultCode
                message = $ErrorObject
                target = $DefaultTarget
            })
        }
    }

    $nestedError = Get-DiagnosticPropertyValue -InputObject $ErrorObject -Name 'error'
    if ($null -ne $nestedError) {
        return @(ConvertTo-ArmErrorLeaves `
            -ErrorObject $nestedError `
            -DefaultCode $DefaultCode `
            -DefaultMessage $DefaultMessage `
            -DefaultTarget $DefaultTarget)
    }
    $code = Get-DiagnosticPropertyValue -InputObject $ErrorObject -Name 'code'
    $message = Get-DiagnosticPropertyValue -InputObject $ErrorObject -Name 'message'
    $target = Get-DiagnosticPropertyValue -InputObject $ErrorObject -Name 'target'
    $details = @(Get-DiagnosticPropertyValue -InputObject $ErrorObject -Name 'details')
    if ($details.Count -gt 0 -and $null -ne $details[0]) {
        return @($details | ForEach-Object {
            ConvertTo-ArmErrorLeaves `
                -ErrorObject $_ `
                -DefaultCode $(if ($code) { [string]$code } else { $DefaultCode }) `
                -DefaultMessage $(if ($message) { [string]$message } else { $DefaultMessage }) `
                -DefaultTarget $(if ($target) { [string]$target } else { $DefaultTarget })
        })
    }
    return @([pscustomobject]@{
        code = if ($code) { [string]$code } else { $DefaultCode }
        message = if ($message) { [string]$message } else { $DefaultMessage }
        target = if ($target) { [string]$target } else { $DefaultTarget }
    })
}

function Get-OperationCorrelationId {
    param([object]$Operation)

    $properties = Get-DiagnosticPropertyValue -InputObject $Operation -Name 'properties'
    foreach ($candidate in @(
        (Get-DiagnosticPropertyValue -InputObject $properties -Name 'correlationId'),
        (Get-DiagnosticPropertyValue -InputObject $Operation -Name 'correlationId')
    )) {
        $parsed = [guid]::Empty
        if ($candidate -and [guid]::TryParse([string]$candidate, [ref]$parsed)) {
            return $parsed.ToString()
        }
    }
    return ''
}

function ConvertTo-DiagnosticUtcTimestamp {
    param([object]$Value)

    if ($null -eq $Value -or
        [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [DateTime]::UtcNow.ToString('o')
    }
    if ($Value -is [DateTime]) {
        return ([DateTime]$Value).ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        )
    }
    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref]$parsed
    )) {
        return $parsed.ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        )
    }
    return Protect-ArmDiagnosticText ([string]$Value)
}

function Get-ActivityLogCorrelationId {
    param(
        [string]$SubscriptionId,
        [string]$ResourceId
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        $ResourceId -notmatch '(?i)^/subscriptions/') {
        return ''
    }
    $result = Invoke-CheckedCommand `
        -Stage 'Look up failed resource activity correlation' `
        -FilePath 'az' `
        -Arguments @(
            'monitor', 'activity-log', 'list',
            '--subscription', $SubscriptionId,
            '--resource-id', $ResourceId,
            '--status', 'Failed',
            '--offset', '2h',
            '--query', '[?correlationId != null] | [0].correlationId',
            '--output', 'tsv',
            '--only-show-errors'
        ) `
        -Quiet `
        -AllowFailure
    if ($result.ExitCode -ne 0) {
        Write-Warning "[DIAGNOSTIC] Activity log correlation lookup failed for '$ResourceId'."
        return ''
    }
    $candidate = ($result.Output -join '').Trim()
    $parsed = [guid]::Empty
    if ([guid]::TryParse($candidate, [ref]$parsed)) {
        return $parsed.ToString()
    }
    return ''
}

function Expand-ArmDeploymentFailures {
    param(
        [Parameter(Mandatory)][object]$Reference,
        [Collections.Generic.HashSet[string]]$Visited
    )

    if ($null -eq $Visited) {
        $Visited = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
    }
    $key = "$($Reference.scope)|$($Reference.resourceGroupName)|$($Reference.name)"
    if (-not $Visited.Add($key)) {
        return @()
    }
    $operations = @(Get-ArmDeploymentOperations -Reference $Reference)
    $failures = [Collections.Generic.List[object]]::new()
    foreach ($operation in $operations) {
        $properties = Get-DiagnosticPropertyValue -InputObject $operation -Name 'properties'
        $state = [string](Get-DiagnosticPropertyValue `
            -InputObject $properties `
            -Name 'provisioningState')
        if ($state -ne 'Failed') {
            continue
        }
        $targetResource = Get-DiagnosticPropertyValue `
            -InputObject $properties `
            -Name 'targetResource'
        $resourceId = [string](Get-DiagnosticPropertyValue `
            -InputObject $targetResource `
            -Name 'id')
        $resourceType = [string](Get-DiagnosticPropertyValue `
            -InputObject $targetResource `
            -Name 'resourceType')
        $resourceName = [string](Get-DiagnosticPropertyValue `
            -InputObject $targetResource `
            -Name 'resourceName')
        if ($resourceType -eq 'Microsoft.Resources/deployments' -or
            $resourceId -match '(?i)/providers/Microsoft\.Resources/deployments/') {
            $nestedReference = ConvertTo-ArmDeploymentReference `
                -ResourceId $resourceId `
                -FallbackSubscriptionId $Reference.subscriptionId
            if ($null -eq $nestedReference -and
                -not [string]::IsNullOrWhiteSpace($resourceName)) {
                $nestedReference = New-ArmDeploymentReference `
                    -Scope $Reference.scope `
                    -SubscriptionId $Reference.subscriptionId `
                    -ResourceGroupName $Reference.resourceGroupName `
                    -Name $resourceName
            }
            if ($null -ne $nestedReference) {
                try {
                    $nestedFailures = @(Expand-ArmDeploymentFailures `
                        -Reference $nestedReference `
                        -Visited $Visited)
                    if ($nestedFailures.Count -gt 0) {
                        foreach ($failure in $nestedFailures) {
                            $failures.Add($failure)
                        }
                        continue
                    }
                }
                catch {
                    Write-Warning (
                        "[DIAGNOSTIC] Unable to query nested deployment '{0}': {1}" -f
                        $nestedReference.name,
                        (Protect-ArmDiagnosticText $_.Exception.Message)
                    )
                }
            }
        }

        $statusMessage = Get-DiagnosticPropertyValue `
            -InputObject $properties `
            -Name 'statusMessage'
        $errorLeaves = @(ConvertTo-ArmErrorLeaves `
            -ErrorObject $statusMessage `
            -DefaultMessage 'ARM reported a failed deployment operation.' `
            -DefaultTarget $resourceName)
        $correlationId = Get-OperationCorrelationId -Operation $operation
        if ([string]::IsNullOrWhiteSpace($correlationId)) {
            $correlationId = Get-ActivityLogCorrelationId `
                -SubscriptionId $Reference.subscriptionId `
                -ResourceId $resourceId
        }
        foreach ($errorLeaf in $errorLeaves) {
            $timestamp = ConvertTo-DiagnosticUtcTimestamp (Get-DiagnosticPropertyValue `
                -InputObject $properties `
                -Name 'timestamp')
            $failures.Add([pscustomobject]@{
                resource = $resourceName
                resourceType = $resourceType
                resourceId = $resourceId
                scope = if ($Reference.scope -eq 'resourceGroup') {
                    "resourceGroup:$($Reference.resourceGroupName)"
                }
                else {
                    'subscription'
                }
                code = [string]$errorLeaf.code
                message = Protect-ArmDiagnosticText ([string]$errorLeaf.message)
                target = Protect-ArmDiagnosticText ([string]$errorLeaf.target)
                correlationId = $correlationId
                timestampUtc = $timestamp
            })
        }
    }
    return @($failures)
}

function Get-ArmResourceProvisioningState {
    param([string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        $ResourceId -notmatch '(?i)^/subscriptions/') {
        return ''
    }
    $result = Invoke-CheckedCommand `
        -Stage 'Read failed ARM resource provisioning state' `
        -FilePath 'az' `
        -Arguments @(
            'resource', 'show',
            '--ids', $ResourceId,
            '--query', 'properties.provisioningState',
            '--output', 'tsv',
            '--only-show-errors'
        ) `
        -Quiet `
        -AllowFailure
    if ($result.ExitCode -ne 0) {
        Write-Warning (
            "[DIAGNOSTIC] Could not read terminal provisioning state for '{0}'; leaf diagnostics continue." -f
            (Protect-ArmDiagnosticText $ResourceId)
        )
        return ''
    }
    return ($result.Output -join '').Trim()
}

function Invoke-AzdProvisionFailureDiagnostics {
    param(
        [string[]]$ProvisionOutput,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName
    )

    Write-Host '[DIAGNOSTIC] Expanding failed ARM deployment operations.'
    try {
        $references = @(Get-AzdDeploymentReferences `
            -Output $ProvisionOutput `
            -SubscriptionId $SubscriptionId)
        if ($references.Count -eq 0) {
            Write-Warning '[DIAGNOSTIC] No deployment ARM ID or deployment name was found in azd output; the original provision failure is preserved.'
            return [pscustomobject]@{
                succeeded = $false
                failures = @()
            }
        }

        $failures = [Collections.Generic.List[object]]::new()
        $visited = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($reference in $references) {
            try {
                foreach ($failure in @(Expand-ArmDeploymentFailures `
                    -Reference $reference `
                    -Visited $visited)) {
                    $failures.Add($failure)
                }
            }

            catch {
                Write-Warning (
                    "[DIAGNOSTIC] Unable to query deployment '{0}': {1}" -f
                    $reference.name,
                    (Protect-ArmDiagnosticText $_.Exception.Message)
                )
            }
        }

        if ($failures.Count -eq 0) {
            Write-Warning '[DIAGNOSTIC] ARM operation queries returned no leaf failure details; the original provision failure is preserved.'
            return [pscustomobject]@{
                succeeded = $false
                failures = @()
            }
        }
        $resourceStates = @{}
        foreach ($failure in $failures) {
            $resourceId = [string](Get-DiagnosticPropertyValue `
                -InputObject $failure `
                -Name 'resourceId')
            $stateKey = $resourceId.ToLowerInvariant()
            if (-not $resourceStates.ContainsKey($stateKey)) {
                $resourceStates[$stateKey] = Get-ArmResourceProvisioningState `
                    -ResourceId $resourceId
            }
            $failure | Add-Member `
                -NotePropertyName provisioningState `
                -NotePropertyValue $resourceStates[$stateKey] `
                -Force
            $timestamp = Protect-ArmDiagnosticText ([string]$failure.timestampUtc)
            Write-Host (
                "[ARM FAILURE] resource='{0}' id='{1}' type='{2}' scope='{3}' state='{4}' utc='{5}' code='{6}' target='{7}' message='{8}'" -f
                (Protect-ArmDiagnosticText ([string]$failure.resource)),
                (Protect-ArmDiagnosticText $resourceId),
                (Protect-ArmDiagnosticText ([string]$failure.resourceType)),
                (Protect-ArmDiagnosticText ([string]$failure.scope)),
                (Protect-ArmDiagnosticText ([string]$failure.provisioningState)),
                $timestamp,
                (Protect-ArmDiagnosticText ([string]$failure.code)),
                (Protect-ArmDiagnosticText ([string]$failure.target)),
                (Protect-ArmDiagnosticText ([string]$failure.message))
            )
            if (-not [string]::IsNullOrWhiteSpace($failure.correlationId)) {
                Write-Host "[ARM CORRELATION] $($failure.correlationId)"
            }
            $guidance = Get-ArmFailureGuidance -Failure $failure
            Write-Host "[NEXT STEP][$($guidance.category)] $($guidance.action)"
        }
        return [pscustomobject]@{
            succeeded = $true
            failures = @($failures)
        }
    }
    catch {
        Write-Warning (
            "[DIAGNOSTIC] ARM failure diagnostics could not complete: {0}. The original provision failure is preserved." -f
            (Protect-ArmDiagnosticText $_.Exception.Message)
        )
        return [pscustomobject]@{
            succeeded = $false
            failures = @()
        }
    }
}

function Get-ArmFailureGuidance {
    param([Parameter(Mandatory)][object]$Failure)

    $code = [string](Get-DiagnosticPropertyValue -InputObject $Failure -Name 'code')
    $message = [string](Get-DiagnosticPropertyValue -InputObject $Failure -Name 'message')
    $state = [string](Get-DiagnosticPropertyValue `
        -InputObject $Failure `
        -Name 'provisioningState')
    $combined = "$code $message"
    if ($combined -match '(?i)authorization|forbidden|permission|roleassignment|abac') {
        return [pscustomobject]@{
            category = 'Authorization'
            action = 'Do not rerun until access is corrected. Verify the deploying principal, scope, RBAC role, deny assignments, and ABAC conditions; do not broaden template permissions.'
        }
    }
    if ($combined -match '(?i)quota|capacity|insufficient') {
        return [pscustomobject]@{
            category = 'QuotaOrCapacity'
            action = 'Do not rerun unchanged. Check regional quota and capacity for the resource type, request quota or select an approved supported region, then rerun.'
        }
    }
    if ($combined -match '(?i)requestdisallowedbypolicy|policyviolation|azure\s+policy|denyassignment') {
        return [pscustomobject]@{
            category = 'Policy'
            action = 'Do not rerun unchanged. Review the Azure Policy assignment and compliance reason at this scope; ask the policy owner for approved remediation or an exemption.'
        }
    }
    if ($combined -match '(?i)alreadyexists|conflict|soft.?deleted|name.*(unavailable|invalid)') {
        return [pscustomobject]@{
            category = 'Conflict'
            action = 'Do not rerun until reviewed. Inspect existing, soft-deleted, and Failed resources with the same name; confirm ownership and state before resolving the conflict.'
        }
    }
    if ($combined -match '(?i)invalidtemplate|invalidparameter|badrequest|validation|malformed') {
        return [pscustomobject]@{
            category = 'InvalidConfiguration'
            action = 'Do not rerun unchanged. Correct the template parameter, API contract, or resource property, then rerun the same deployment.'
        }
    }
    if ($code -match '(?i)internalservererror|serviceunavailable|gatewaytimeout|timeout|temporar|accountprovisioningstateinvalid|^5\d\d$' -or
        $message -match '(?i)service unavailable|gateway timeout|timed? out|temporar') {
        return [pscustomobject]@{
            category = 'ServiceOrTransient'
            action = 'A single later rerun is reasonable after checking whether the resource is already present or Failed. If the same 5xx/timeout repeats, stop and contact Azure Support with the printed evidence.'
        }
    }
    if ($state -eq 'Failed') {
        return [pscustomobject]@{
            category = 'TerminalFailedState'
            action = 'Do not rerun blindly. Review the existing Failed resource, dependencies, ownership, and customer troubleshooting guidance before any operator-approved remediation.'
        }
    }
    return [pscustomobject]@{
        category = 'Unknown'
        action = 'Rerun safety is unknown. Inspect existing, soft-deleted, and Failed resources, Portal deployment operations, and Activity Log; review docs/troubleshooting.md, then contact Azure Support if unresolved.'
    }
}

function Write-AzdProvisionFailureGuidance {
    param(
        [object[]]$Failures,
        [string]$SubscriptionId,
        [string]$ResourceGroupName
    )

    Write-Host '[DIAGNOSTIC] No Azure resource was modified directly. No resource-level repair was performed, and provision will not be retried further.'
    Write-Host (
        "[PORTAL] Resource-group scope: Azure Portal > Resource group '{0}' > Deployments > failed deployment > Deployment details > Operation details." -f
        (Protect-ArmDiagnosticText $ResourceGroupName)
    )
    Write-Host (
        "[PORTAL] Subscription scope: Azure Portal > Subscriptions > '{0}' > Deployments > failed deployment > Operation details." -f
        (Protect-ArmDiagnosticText $SubscriptionId)
    )
    Write-Host '[PORTAL] Azure Portal > Monitor > Activity log; filter by subscription, leaf resource ID, Failed status, and the printed UTC time.'
    Write-Host (
        "[SUPPORT] If the guidance does not resolve the failure, provide Azure Support subscription '{0}' and the printed resource ID, UTC time, correlation ID, and error code." -f
        (Protect-ArmDiagnosticText $SubscriptionId)
    )
    Write-Host '[GUIDANCE] Review category-specific actions and customer troubleshooting: docs/troubleshooting.md#arm-deployment-failure-categories.'
}

function Test-RetryableProvisionFailure {
    param([Parameter(Mandatory)][object]$Diagnostics)

    $failures = @($Diagnostics.failures)
    if ($failures.Count -eq 0) {
        return $false
    }
    foreach ($failure in $failures) {
        $resourceType = [string](Get-DiagnosticPropertyValue `
            -InputObject $failure `
            -Name 'resourceType')
        $state = [string](Get-DiagnosticPropertyValue `
            -InputObject $failure `
            -Name 'provisioningState')
        $code = [string](Get-DiagnosticPropertyValue `
            -InputObject $failure `
            -Name 'code')
        $guidance = Get-ArmFailureGuidance -Failure $failure
        $isFirewallTransient = $resourceType -ieq 'Microsoft.Network/azureFirewalls' -and
            $state -ieq 'Failed' -and
            $guidance.category -eq 'ServiceOrTransient'
        $isFoundryPrivateEndpointRace = $resourceType -ieq 'Microsoft.Network/privateEndpoints' -and
            $code -ieq 'AccountProvisioningStateInvalid'
        if (-not $isFirewallTransient -and -not $isFoundryPrivateEndpointRace) {
            return $false
        }
    }
    return $true
}

function Invoke-AzdProgressAzJson {
    param([string[]]$Arguments)

    $output = @(& az @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        return $null
    }
    try {
        return ($output -join "`n") | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-AzdProvisionResourceDescription {
    param(
        [string]$ResourceType,
        [string]$ResourceName
    )

    $label = switch -Regex ($ResourceType) {
        '(?i)^Microsoft\.Network/azureFirewalls$' {
            'Azure Firewall'
            break
        }
        '(?i)^Microsoft\.Network/virtualNetworkGateways$' {
            'VPN Gateway'
            break
        }
        '(?i)^Microsoft\.CognitiveServices/accounts/projects$' {
            'Foundry project'
            break
        }
        '(?i)^Microsoft\.CognitiveServices/accounts$' {
            'Foundry account'
            break
        }
        '(?i)^Microsoft\.Search/searchServices$' {
            'Azure AI Search'
            break
        }
        '(?i)^Microsoft\.Network/privateEndpoints$' {
            'Private Endpoint'
            break
        }
        '(?i)^Microsoft\.Network/dnsResolvers' {
            'Private DNS Resolver'
            break
        }
        '(?i)^Microsoft\.KeyVault/vaults$' {
            'Key Vault'
            break
        }
        '(?i)^Microsoft\.Network/virtualNetworks$' {
            'Virtual Network'
            break
        }
        default {
            $ResourceType
        }
    }
    return [pscustomobject]@{
        label = $label
        name = $ResourceName
    }
}

function Test-FirewallCreationRequired {
    param(
        [object[]]$Firewalls,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    $matchingFirewalls = @($Firewalls | Where-Object {
        $tagsProperty = $_.PSObject.Properties['tags']
        if ($null -eq $tagsProperty -or $null -eq $tagsProperty.Value) {
            return $false
        }
        $environmentTag = $tagsProperty.Value.PSObject.Properties[
            'azd-env-name'
        ]
        return $null -ne $environmentTag -and
            [string]$environmentTag.Value -ceq $EnvironmentName
    })
    if ($matchingFirewalls.Count -gt 1) {
        throw "Multiple template Firewalls are tagged for azd environment '$EnvironmentName'. Refusing ambiguous reconciliation."
    }
    if ($matchingFirewalls.Count -eq 0) {
        return $true
    }

    $propertiesProperty = $matchingFirewalls[0].PSObject.Properties[
        'properties'
    ]
    $policyProperty = if ($null -ne $propertiesProperty -and
        $null -ne $propertiesProperty.Value) {
        $propertiesProperty.Value.PSObject.Properties['firewallPolicy']
    }
    else {
        $matchingFirewalls[0].PSObject.Properties['firewallPolicy']
    }
    if ($null -eq $policyProperty -or $null -eq $policyProperty.Value) {
        return $true
    }
    $policyIdProperty = $policyProperty.Value.PSObject.Properties['id']
    return $null -eq $policyIdProperty -or
        [string]::IsNullOrWhiteSpace([string]$policyIdProperty.Value)
}

function Set-AzdFirewallCreationMode {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    $groupExistsOutput = @(& az group exists `
        --subscription $SubscriptionId `
        --name $ResourceGroupName `
        --output tsv `
        --only-show-errors 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect resource group '$ResourceGroupName'. Provision was not started."
    }
    $groupExists = ($groupExistsOutput -join '').Trim() -ieq 'true'
    $firewalls = @()
    if ($groupExists) {
        $encodedResourceGroup = [Uri]::EscapeDataString($ResourceGroupName)
        $firewallCollectionUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$encodedResourceGroup/providers/Microsoft.Network/azureFirewalls?api-version=2024-05-01"
        $output = @(& az rest `
            --method get `
            --url $firewallCollectionUrl `
            --output json `
            --only-show-errors 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect Azure Firewall state in resource group '$ResourceGroupName'. Provision was not started."
        }
        try {
            $response = ($output -join "`n") | ConvertFrom-Json
            $valueProperty = $response.PSObject.Properties['value']
            if ($null -eq $valueProperty) {
                throw 'The Firewall collection response did not contain value.'
            }
            $firewalls = @($valueProperty.Value)
        }
        catch {
            throw "Azure returned invalid Firewall state for resource group '$ResourceGroupName'. Provision was not started."
        }
    }
    $creationRequired = Test-FirewallCreationRequired `
        -Firewalls $firewalls `
        -EnvironmentName $EnvironmentName
    $creationValue = $creationRequired.ToString().ToLowerInvariant()
    Invoke-CheckedCommand `
        -Stage 'Configure idempotent Firewall deployment stage' `
        -FilePath 'azd' `
        -Arguments @(
            'env', 'set', 'FPHA_FIREWALL_CREATION_REQUIRED',
            $creationValue, '-e', $EnvironmentName
        ) `
        -WorkingDirectory $ProjectDirectory `
        -Quiet | Out-Null
    if ($creationRequired) {
        Write-Host '[PLAN] Firewall has no attached policy yet; the initial no-policy creation stage will run.'
    }
    else {
        Write-Host '[RESUME] Firewall policy is already attached; skipping the initial no-policy PUT to preserve connectivity.'
    }
}

function Get-AzdProvisionProgressSnapshot {
    param([Parameter(Mandatory)][object]$Context)

    $deployments = @(Invoke-AzdProgressAzJson -Arguments @(
        'deployment', 'group', 'list',
        '--subscription', $Context.SubscriptionId,
        '--resource-group', $Context.ResourceGroupName,
        '--output', 'json',
        '--only-show-errors'
    ))
    if ($deployments.Count -eq 0 -or $null -eq $deployments[0]) {
        return @()
    }
    $runningDeployments = @($deployments |
        Where-Object { $_.properties.provisioningState -eq 'Running' } |
        Sort-Object { [DateTime]$_.properties.timestamp } -Descending)
    foreach ($deployment in $runningDeployments) {
        $operations = @(Invoke-AzdProgressAzJson -Arguments @(
            'deployment', 'operation', 'group', 'list',
            '--subscription', $Context.SubscriptionId,
            '--resource-group', $Context.ResourceGroupName,
            '--name', $deployment.name,
            '--output', 'json',
            '--only-show-errors'
        ))
        $runningResources = @($operations |
            Where-Object {
                $_.properties.provisioningState -eq 'Running' -and
                $_.properties.targetResource.resourceType -ne
                    'Microsoft.Resources/deployments'
            } |
            ForEach-Object {
                [pscustomobject]@{
                    resourceType = [string]$_.properties.targetResource.resourceType
                    resourceName = [string]$_.properties.targetResource.resourceName
                }
            })
        if ($runningResources.Count -gt 0) {
            return @($runningResources)
        }
    }
    return @()
}

function Write-AzdProvisionProgress {
    param([Parameter(Mandatory)][object]$Context)

    $now = [DateTime]::UtcNow
    $resources = @(Get-AzdProvisionProgressSnapshot -Context $Context)
    if ($resources.Count -eq 0) {
        if (($now - $Context.LastHeartbeatUtc).TotalSeconds -ge 90) {
            Write-Host '[WAITING] ARM is coordinating nested deployments; waiting for the next active resource.'
            $Context.LastHeartbeatUtc = $now
        }
        return
    }

    $descriptions = @($resources | ForEach-Object {
        Get-AzdProvisionResourceDescription `
            -ResourceType $_.resourceType `
            -ResourceName $_.resourceName
    })
    $signature = ($descriptions | ForEach-Object {
        "$($_.label)|$($_.name)"
    }) -join ';'
    $summary = ($descriptions | ForEach-Object {
        "$($_.label) '$($_.name)'"
    }) -join ', '
    if ($signature -ne $Context.LastSignature) {
        Write-Host "[PROGRESS] Provisioning $summary."
        $Context.LastSignature = $signature
        $Context.LastHeartbeatUtc = $now
        return
    }
    if (($now - $Context.LastHeartbeatUtc).TotalSeconds -ge 90) {
        Write-Host "[WAITING] Waiting for $summary; ARM status is Running."
        $Context.LastHeartbeatUtc = $now
    }
}

function Invoke-AzdProvisionCommand {
    param(
        [string]$Stage,
        [string]$ProjectDirectory,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName,
        [switch]$AllowFailure
    )

    Set-AzdFirewallCreationMode `
        -ProjectDirectory $ProjectDirectory `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -EnvironmentName $EnvironmentName
    $script:AzdProvisionProgressContext = [pscustomobject]@{
        SubscriptionId = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        LastHeartbeatUtc = [DateTime]::UtcNow.AddSeconds(-90)
        LastSignature = ''
        InitialProgressDelaySeconds = 15
        ProgressPollIntervalSeconds = 45
    }
    try {
        return Invoke-CheckedCommand `
            -Stage $Stage `
            -FilePath 'azd' `
            -Arguments @(
                'provision', '-e', $EnvironmentName, '--no-prompt'
            ) `
            -WorkingDirectory $ProjectDirectory `
            -AllowFailure:$AllowFailure
    }
    finally {
        Remove-Variable AzdProvisionProgressContext `
            -Scope Script `
            -ErrorAction SilentlyContinue
    }
}

function Invoke-ProvisionWithArmDiagnostics {
    param(
        [string]$ProjectDirectory,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName
    )

    $provisionResult = Invoke-AzdProvisionCommand `
        -Stage 'Provision infrastructure' `
        -ProjectDirectory $ProjectDirectory `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -EnvironmentName $EnvironmentName `
        -AllowFailure
    if ($provisionResult.ExitCode -eq 0) {
        return $provisionResult
    }

    $diagnostics = Invoke-AzdProvisionFailureDiagnostics `
        -ProvisionOutput $provisionResult.Output `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -EnvironmentName $EnvironmentName
    if (Test-RetryableProvisionFailure -Diagnostics $diagnostics) {
        Write-Host '[RETRY] Azure reported a recognized transient provisioning race. Retrying the unchanged idempotent provision once; no resource-level repair will be performed.'
        $retryResult = Invoke-AzdProvisionCommand `
            -Stage 'Provision infrastructure retry (1/1)' `
            -ProjectDirectory $ProjectDirectory `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -EnvironmentName $EnvironmentName `
            -AllowFailure
        if ($retryResult.ExitCode -eq 0) {
            return $retryResult
        }
        $diagnostics = Invoke-AzdProvisionFailureDiagnostics `
            -ProvisionOutput $retryResult.Output `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -EnvironmentName $EnvironmentName
        $provisionResult = $retryResult
    }
    Write-AzdProvisionFailureGuidance `
        -Failures @($diagnostics.failures) `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName
    $exception = [Exception]::new(
        "Stage 'Provision infrastructure' failed with exit code $($provisionResult.ExitCode). Command: $($provisionResult.Command)"
    )
    $exception.Data['NativeExitCode'] = [int]$provisionResult.ExitCode
    $exception.Data['NativeCommand'] = [string]$provisionResult.Command
    throw $exception
}

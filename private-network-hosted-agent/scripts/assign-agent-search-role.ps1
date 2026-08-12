param(
    [string]$AgentPrincipalId = '',
    [string]$AgentServiceName = '',
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName

function Get-NestedPropertyValue {
    param(
        [object]$InputObject,
        [string[]]$Path
    )

    $value = $InputObject
    foreach ($name in $Path) {
        if ($null -eq $value) {
            return $null
        }
        $property = $value.PSObject.Properties[$name]
        if ($null -eq $property) {
            return $null
        }
        $value = $property.Value
    }
    return $value
}

$searchId = Require-Value $values 'AZURE_SEARCH_SERVICE_ID'
$agentName = if ($AgentServiceName) {
    $AgentServiceName
} elseif ($values.ContainsKey('AGENT_PRIVATE_SEARCH_AGENT_NAME')) {
    $values['AGENT_PRIVATE_SEARCH_AGENT_NAME']
} else {
    'private-search-agent'
}

$principalCandidates = @(
if ($AgentPrincipalId) {
    $AgentPrincipalId
} else {
    $agentArguments = @('ai', 'agent', 'show', $agentName, '--output', 'json')
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $agentArguments += @('-e', $EnvironmentName)
    }
    $agentJson = azd @agentArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the deployed agent identity from azd.'
    }
    $agent = $agentJson | ConvertFrom-Json
    @(
        @('instance_identity', 'principal_id'),
        @('identity', 'principalId'),
        @('identity', 'principal_id'),
        @('agent_identity', 'principal_id'),
        @('agentIdentity', 'principalId')
    ) | ForEach-Object {
        Get-NestedPropertyValue -InputObject $agent -Path $_
    } | Where-Object { $_ } | Select-Object -Unique
}
)

if ($principalCandidates.Count -eq 0) {
    $matches = @(az ad sp list --display-name "$agentName-AgentIdentity" |
        ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve '$agentName-AgentIdentity' in Microsoft Entra ID."
    }
    if ($matches.Count -ne 1) {
        throw "Expected one '$agentName-AgentIdentity' service principal; found $($matches.Count)."
    }
    $principalCandidates = @($matches[0].id)
}
if ($principalCandidates.Count -ne 1) {
    throw "Agent identity discovery is ambiguous: $($principalCandidates -join ', ')"
}

$principalId = $principalCandidates[0]
$existing = az role assignment list `
    --assignee-object-id $principalId `
    --scope $searchId `
    --role 'Search Index Data Reader' `
    --query '[0].id' -o tsv
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect Search role assignments for '$principalId'."
}
if (-not $existing) {
    az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role 'Search Index Data Reader' `
        --scope $searchId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assign Search Index Data Reader to '$principalId'."
    }
}

Write-Host "[OK] Agent identity $principalId has query-only Search access."

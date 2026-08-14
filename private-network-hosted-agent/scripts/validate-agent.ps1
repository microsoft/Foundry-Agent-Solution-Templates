param(
    [switch]$DeleteSession,
    [string]$AgentServiceName = '',
    [string]$AgentVersion = '',
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"

$showArguments = @('ai', 'agent', 'show')
if ($AgentServiceName) {
    $showArguments += $AgentServiceName
}
$showArguments += @('--output', 'json')
if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
    $showArguments += @('-e', $EnvironmentName)
}
$agent = azd @showArguments | ConvertFrom-Json
if ($agent.status -notin @('active', 'deployed')) {
    throw "Hosted Agent status is '$($agent.status)'."
}
if ($AgentVersion) {
    $versionProperty = $agent.PSObject.Properties['version']
    $activeVersion = if ($null -ne $versionProperty) {
        [string]$versionProperty.Value
    }
    else {
        ''
    }
    if ($activeVersion -ne $AgentVersion) {
        throw "Hosted Agent is active at version '$activeVersion', not expected version '$AgentVersion'."
    }
}

$invokeArguments = @('ai', 'agent', 'invoke')
if ($AgentServiceName) {
    $invokeArguments += $AgentServiceName
}
if ($AgentVersion) {
    $invokeArguments += @('--version', $AgentVersion)
}
$invokeArguments += @(
    '--new-session',
    '--new-conversation',
    'What does the network baseline say about public fallback?'
)
if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
    $invokeArguments += @('-e', $EnvironmentName)
}
$response = azd @invokeArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Hosted Agent invocation failed.'
}
$responseText = $response -join "`n"
if ($responseText -notmatch '(?i)network|public|fallback' -or
    $responseText -notmatch '(?i)https://') {
    throw 'Hosted Agent response did not include the expected grounded answer and citation.'
}

if ($DeleteSession) {
    $sessionListArguments = @('ai', 'agent', 'sessions', 'list', '--output', 'json')
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $sessionListArguments += @('-e', $EnvironmentName)
    }
    $sessions = @(azd @sessionListArguments | ConvertFrom-Json)
    foreach ($session in $sessions) {
        $deleteArguments = @(
            'ai', 'agent', 'sessions', 'delete', $session.id, '--no-prompt'
        )
        if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
            $deleteArguments += @('-e', $EnvironmentName)
        }
        azd @deleteArguments
    }
}
Write-Host '[OK] Hosted Agent is active and returned a grounded answer with a citation.'

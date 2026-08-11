# Complete validation runner.
# Purpose: Execute every independent validation case and group the JSON results.
# Validates: All control-plane, success-path, policy-failure, and guardrail cases.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$groups = [ordered]@{
    ControlPlane = [ordered]@{
        InfrastructureTopology = 'cases/control-plane/infrastructure-topology.ps1'
        GuardrailBindings = 'cases/control-plane/guardrail-bindings.ps1'
    }
    SuccessPaths = [ordered]@{
        ModelChain = 'cases/success/model-chain.ps1'
        ToolChain = 'cases/success/tool-chain.ps1'
    }
    PolicyFailures = [ordered]@{
        AgentAuthentication = 'cases/policy-failures/agent-authentication.ps1'
        ModelTokenQuota = 'cases/policy-failures/model-token-quota.ps1'
        ToolContentSafety = 'cases/policy-failures/tool-content-safety.ps1'
    }
    GuardrailFailures = [ordered]@{
        UserInput = 'cases/guardrail-failures/user-input.ps1'
        ToolOutput = 'cases/guardrail-failures/tool-output.ps1'
    }
}
$results = [ordered]@{
    AgentGateway = (& azd env get-value APIM_AGENT_GATEWAY_URL | Out-String).Trim()
    Groups = [ordered]@{}
}
foreach ($group in $groups.GetEnumerator()) {
    $cases = [ordered]@{}
    foreach ($case in $group.Value.GetEnumerator()) {
        $script = Join-Path $PSScriptRoot $case.Value
        $cases[$case.Key] = Invoke-ValidationScript "$($group.Key).$($case.Key)" $script
    }
    $results.Groups[$group.Key] = [pscustomobject]@{
        Cases = $cases
        Status = 'Passed'
    }
}

[pscustomobject] $results | ConvertTo-Json -Depth 20

# Guardrail binding validation case.
# Purpose: Verify the active hosted agent and default toolbox use the expected RAI policy.
# Validates: Agent rai_config and toolbox policies.rai_config bindings.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$guardrailPolicyId = Get-AzdValue 'GUARDRAIL_POLICY_ID'
$foundryHeaders = Get-FoundryHeaders
$agent = Invoke-RestMethod `
    -Headers $foundryHeaders `
    -Uri "$($context.ProjectEndpoint)/agents/agent?api-version=v1"
$toolboxHeaders = Get-FoundryHeaders -ToolboxPreview
$toolbox = Invoke-RestMethod `
    -Headers $toolboxHeaders `
    -Uri "$($context.ProjectEndpoint)/toolboxes/tools?api-version=v1"
$toolboxVersion = Invoke-RestMethod `
    -Headers $toolboxHeaders `
    -Uri "$($context.ProjectEndpoint)/toolboxes/tools/versions/$($toolbox.default_version)?api-version=v1"

if ($agent.versions.latest.definition.rai_config.rai_policy_name -ne $guardrailPolicyId) {
    throw 'The hosted agent guardrail binding is invalid.'
}
$toolboxPolicy = $toolboxVersion.PSObject.Properties['policies']
if ($null -ne $toolboxPolicy -and $toolboxPolicy.Value.rai_config.rai_policy_name -ne $guardrailPolicyId) {
    throw 'The toolbox guardrail binding is invalid.'
}

[pscustomobject]@{
    AgentVersion = $agent.versions.latest.version
    ToolboxVersion = $toolbox.default_version
    Policy = $guardrailPolicyId
    AgentPolicyBinding = 'Passed'
    ToolboxPolicyBinding = if ($null -eq $toolboxPolicy) { 'Not exposed by API; validated by PostToolCall case' } else { 'Passed' }
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

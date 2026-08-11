# Microsoft Learn tool-chain success validation case.
# Purpose: Prove one real MCP function call succeeds through APIM and the guarded toolbox.
# Validates: Connection/tool configuration, completed function call, matching non-error output, and final marker.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$foundryHeaders = Get-FoundryHeaders
$connections = Invoke-RestMethod -Headers $foundryHeaders -Uri "$($context.ProjectEndpoint)/connections?api-version=v1"
$connection = @($connections.value | Where-Object { $_.name -eq 'mcp' })[0]
$toolboxHeaders = Get-FoundryHeaders -ToolboxPreview
$toolbox = Invoke-RestMethod -Headers $toolboxHeaders -Uri "$($context.ProjectEndpoint)/toolboxes/tools?api-version=v1"
$toolboxVersion = Invoke-RestMethod -Headers $toolboxHeaders -Uri "$($context.ProjectEndpoint)/toolboxes/tools/versions/$($toolbox.default_version)?api-version=v1"
$tool = @($toolboxVersion.tools | Where-Object { $_.type -eq 'mcp' -and $_.name -eq 'mcp' })[0]
if ($null -eq $connection -or $connection.type -ne 'RemoteTool' -or $connection.credentials.type -ne 'None') {
    throw 'The Learn MCP connection is invalid.'
}
if ($null -eq $tool -or $tool.require_approval -ne 'always') {
    throw 'The Learn MCP toolbox tool is invalid.'
}

$response = Invoke-AgentGateway 'Use the Microsoft Learn tool to search for the exact string APIM_VALIDATION_NO_RESULTS_7F3A9C. Then reply with exactly TOOL_CALL_COMPLETED.'
Assert-AgentGatewayResponse $response
$agentResponse = $response.Content | ConvertFrom-Json
$functionCalls = @($agentResponse.output | Where-Object {
    $_.type -eq 'function_call' -and
    $_.name -like 'mcp___*' -and
    $_.status -eq 'completed'
})
$successfulOutputs = @($agentResponse.output | Where-Object {
    $_.type -eq 'function_call_output' -and
    $_.status -eq 'completed' -and
    $_.output -notmatch '^Error:' -and
    $_.call_id -in $functionCalls.call_id
})
if ([int] $response.StatusCode -ne 200 -or
    $agentResponse.status -ne 'completed' -or
    $functionCalls.Count -lt 1 -or
    $successfulOutputs.Count -lt 1 -or
    $response.Content -notmatch 'TOOL_CALL_COMPLETED') {
    throw 'The APIM tool chain failed.'
}

[pscustomobject]@{
    Connection = $connection.name
    ToolboxVersion = $toolbox.default_version
    CompletedToolCalls = $functionCalls.Count
    SuccessfulToolOutputs = $successfulOutputs.Count
    ToolNames = @($functionCalls.name)
    AgentGateway = $context.AgentGatewayEndpoint
    ToolChain = 'Passed'
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

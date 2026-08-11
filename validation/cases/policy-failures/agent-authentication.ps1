# Agent authentication policy failure validation case.
# Purpose: Verify APIM rejects hosted-agent requests without a Foundry bearer token.
# Validates: validate-azure-ad-token enforcement returns HTTP 401.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$response = Invoke-AgentGateway 'Reply with exactly UNEXPECTED.' -WithoutAuthentication
if ([int] $response.StatusCode -ne 401) {
    throw 'Agent authentication policy did not reject the missing bearer token.'
}

[pscustomobject]@{
    Scenario = 'Missing Foundry bearer token'
    Expected = 'HTTP 401'
    Actual = "HTTP $([int] $response.StatusCode)"
    AgentGateway = $context.AgentGatewayEndpoint
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

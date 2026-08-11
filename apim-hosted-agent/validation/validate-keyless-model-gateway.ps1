# Passwordless model gateway validation.
# Purpose: Prove the hosted agent uses Entra authentication to APIM without a subscription key.
# Validates: API topology, identity binding, negative authentication, and remote model invocation.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$context = Get-ValidationContext
$headers = Get-ArmHeaders
$base = "https://management.azure.com$($context.ApimId)"
$api = Invoke-RestMethod -Headers $headers -Uri "$base/apis/$($context.AccountName)-keyless?api-version=2024-05-01"
if ($api.properties.subscriptionRequired) {
    throw 'The keyless model API unexpectedly requires an APIM subscription.'
}

$foundryHeaders = Get-FoundryHeaders
$agentResource = Invoke-RestMethod `
    -Headers $foundryHeaders `
    -Uri "$($context.ProjectEndpoint)/agents/agent?api-version=v1"
$agent = $agentResource.versions.latest
$agentPrincipalId = [string] $agent.instance_identity.principal_id
$environmentNames = @($agent.definition.environment_variables.PSObject.Properties.Name)
if ('AGENT_APIM_SUBSCRIPTION_KEY' -in $environmentNames) {
    throw 'The hosted agent contains an APIM subscription key.'
}

$expectedEndpoint = Get-AzdValue 'APIM_KEYLESS_FOUNDRY_PROJECT_ENDPOINT'
$configuredEndpoint = [string] $agent.definition.environment_variables.AGENT_APIM_PROJECT_ENDPOINT
if ($configuredEndpoint -ne $expectedEndpoint) {
    throw 'The hosted agent is not configured with the keyless APIM endpoint.'
}

$principalValue = Invoke-RestMethod `
    -Headers $headers `
    -Uri "$base/namedValues/foundry-agent-principal-id?api-version=2024-05-01"
if ([string] $principalValue.properties.value -ne $agentPrincipalId) {
    throw 'APIM is not bound to the hosted-agent managed identity.'
}

$body = @{
    model = [string] $agent.definition.environment_variables.AGENT_MODEL_DEPLOYMENT
    input = 'Reply with exactly UNEXPECTED.'
    store = $false
} | ConvertTo-Json -Compress
$modelUri = "${expectedEndpoint}/openai/v1/responses"
$missingTokenResponse = Invoke-WebRequest `
    -Method Post `
    -Uri $modelUri `
    -ContentType 'application/json' `
    -Body $body `
    -SkipHttpErrorCheck
if ([int] $missingTokenResponse.StatusCode -ne 401) {
    throw 'The keyless model API did not reject a missing bearer token.'
}

$wrongPrincipalResponse = Invoke-WebRequest `
    -Method Post `
    -Uri $modelUri `
    -Headers (Get-FoundryHeaders) `
    -ContentType 'application/json' `
    -Body $body `
    -SkipHttpErrorCheck
if ([int] $wrongPrincipalResponse.StatusCode -ne 401) {
    throw 'The keyless model API did not reject an unapproved Foundry principal.'
}

$response = Invoke-AgentGateway 'Reply with exactly KEYLESS_MODEL_GATEWAY_OK. Do not use tools.'
Assert-AgentGatewayResponse $response
if ([int] $response.StatusCode -ne 200 -or $response.Content -notmatch 'KEYLESS_MODEL_GATEWAY_OK') {
    throw 'The hosted agent could not invoke the keyless APIM model gateway.'
}

[pscustomobject]@{
    Api = $api.name
    Endpoint = $expectedEndpoint
    AgentPrincipalId = $agentPrincipalId
    SubscriptionKeyPresent = $false
    MissingTokenStatus = [int] $missingTokenResponse.StatusCode
    WrongPrincipalStatus = [int] $wrongPrincipalResponse.StatusCode
    RemoteInvocation = 'Passed'
    Status = 'Passed'
} | ConvertTo-Json -Depth 5
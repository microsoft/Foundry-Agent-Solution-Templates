# Model chain success validation case.
# Purpose: Prove a normal request traverses APIM, the hosted agent, and the APIM model gateway.
# Validates: Runtime environment names, model token policies, APIM response marker, and model response.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$headers = Get-ArmHeaders
$base = "https://management.azure.com$($context.ApimId)"
$apiPolicy = Get-PolicyXml "$base/apis/$($context.AccountName)-keyless/policies/policy?api-version=2024-05-01" $headers
$productName = Get-AzdValue 'APIM_FOUNDRY_PRODUCT_NAME'
$product = Invoke-RestMethod -Headers $headers -Uri "$base/products/${productName}?api-version=2024-05-01"
$foundryHeaders = Get-FoundryHeaders
$agentResource = Invoke-RestMethod `
    -Headers $foundryHeaders `
    -Uri "$($context.ProjectEndpoint)/agents/agent?api-version=v1"
$agent = $agentResource.versions.latest
$environmentNames = @($agent.definition.environment_variables.PSObject.Properties.Name)
$requiredEnvironmentNames = @(
    'AGENT_APIM_PROJECT_ENDPOINT'
    'AGENT_MODEL_DEPLOYMENT'
    'AGENT_TOOLBOX_ENDPOINT'
)
$missingEnvironmentNames = @($requiredEnvironmentNames | Where-Object { $_ -notin $environmentNames })
$reservedEnvironmentNames = @($environmentNames | Where-Object { $_ -match '^(AZURE_|FOUNDRY_)' })
if ($missingEnvironmentNames.Count -gt 0) { throw "The hosted agent is missing environment variables: $($missingEnvironmentNames -join ', ')." }
if ($reservedEnvironmentNames.Count -gt 0) { throw "The hosted agent contains reserved environment variables: $($reservedEnvironmentNames -join ', ')." }
if ('AGENT_APIM_SUBSCRIPTION_KEY' -in $environmentNames) { throw 'The hosted agent still contains an APIM subscription key.' }
$expectedEndpoint = Get-AzdValue 'APIM_KEYLESS_FOUNDRY_PROJECT_ENDPOINT'
if ([string] $agent.definition.environment_variables.AGENT_APIM_PROJECT_ENDPOINT -ne $expectedEndpoint) { throw 'The hosted agent does not use the keyless APIM model endpoint.' }
$model = [string] $agent.definition.environment_variables.AGENT_MODEL_DEPLOYMENT
if ($apiPolicy -notmatch '<llm-token-limit') { throw 'The model API token policy is missing.' }
if ($apiPolicy -notmatch [regex]::Escape('tokenlimit-{{foundry-model-deployment-name}}') -or
    $apiPolicy -notmatch [regex]::Escape('tokenquota-{{foundry-model-deployment-name}}')) {
    throw 'The model token variables are missing from the merged API policy.'
}

$response = Invoke-AgentGateway 'Reply with exactly APIM_MODEL_CHAIN_OK. Do not use tools.'
Assert-AgentGatewayResponse $response
if ([int] $response.StatusCode -ne 200 -or $response.Content -notmatch 'APIM_MODEL_CHAIN_OK') {
    throw 'The APIM model chain failed.'
}

[pscustomobject]@{
    Model = $model
    Product = $product.name
    AgentGateway = $context.AgentGatewayEndpoint
    ModelChain = 'Passed'
    SubscriptionKeyPresent = $false
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

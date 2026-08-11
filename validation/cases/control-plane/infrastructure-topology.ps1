# Infrastructure topology validation case.
# Purpose: Verify the Bicep-created Foundry, APIM, model, agent, and MCP topology.
# Validates: APIs, backends, operations, policies, role assignments, and canonical resource links.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$headers = Get-ArmHeaders
$base = "https://management.azure.com$($context.ApimId)"
$apim = Invoke-RestMethod -Headers $headers -Uri "${base}?api-version=2024-05-01"
$api = Invoke-RestMethod -Headers $headers -Uri "$base/apis/$($context.AccountName)?api-version=2024-05-01"
$keylessApi = Invoke-RestMethod -Headers $headers -Uri "$base/apis/$($context.AccountName)-keyless?api-version=2024-05-01"
$backend = Invoke-RestMethod -Headers $headers -Uri "$base/backends/$($context.AccountName)?api-version=2024-05-01"
$operations = Invoke-RestMethod -Headers $headers -Uri "$base/apis/$($context.AccountName)/operations?api-version=2024-05-01"
$keylessOperations = Invoke-RestMethod -Headers $headers -Uri "$base/apis/$($context.AccountName)-keyless/operations?api-version=2024-05-01"
$legacyPolicyPresent = Test-ApimPolicyExists "$base/apis/$($context.AccountName)/policies/policy?api-version=2024-05-01" $headers
$keylessPolicy = Get-PolicyXml "$base/apis/$($context.AccountName)-keyless/policies/policy?api-version=2024-05-01" $headers
$productName = Get-AzdValue 'APIM_FOUNDRY_PRODUCT_NAME'
$product = Invoke-RestMethod -Headers $headers -Uri "$base/products/${productName}?api-version=2024-05-01"
$productApis = Invoke-RestMethod -Headers $headers -Uri "$base/products/${productName}/apis?api-version=2024-05-01"
$subscriptions = Invoke-RestMethod -Headers $headers -Uri "$base/subscriptions?api-version=2024-05-01"
$productSubscriptions = @($subscriptions.value | Where-Object { $_.properties.scope -eq $product.id })
$agentApi = Invoke-RestMethod -Headers $headers -Uri "$base/apis/foundry-hosted-agent?api-version=2024-05-01"
$agentOperations = Invoke-RestMethod -Headers $headers -Uri "$base/apis/foundry-hosted-agent/operations?api-version=2024-05-01"
$agentPolicy = Get-PolicyXml "$base/apis/foundry-hosted-agent/policies/policy?api-version=2024-05-01" $headers
$mcpApiName = "tool-$($context.ProjectName)-mcp"
$mcpApi = Invoke-RestMethod -Headers $headers -Uri "$base/apis/${mcpApiName}?api-version=2024-10-01-preview"
$mcpPolicy = Get-PolicyXml "$base/apis/${mcpApiName}/policies/policy?api-version=2024-10-01-preview" $headers
$contentSafetyBackend = Invoke-RestMethod -Headers $headers -Uri "$base/backends/foundry-content-safety?api-version=2024-05-01"
$accountLinks = Invoke-RestMethod -Headers $headers -Uri "https://management.azure.com$($context.AccountId)/providers/Microsoft.Resources/links?api-version=2016-09-01"
$apimLinks = Invoke-RestMethod -Headers $headers -Uri "$base/providers/Microsoft.Resources/links?api-version=2016-09-01"
$projectLinks = Invoke-RestMethod -Headers $headers -Uri "https://management.azure.com$($context.ProjectId)/providers/Microsoft.Resources/links?api-version=2016-09-01"
$accountRoleAssignments = Invoke-RestMethod -Headers $headers -Uri "https://management.azure.com$($context.AccountId)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
$productId = "$($context.ApimId)/products/$productName"
$cognitiveServicesUserRoleDefinitionId = "/subscriptions/$($context.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/a97b65f3-24c7-4388-baec-2e87135dc908"

function Assert-CanonicalResourceLink([object] $response, [string] $sourceId, [string] $targetId, [string] $description) {
    $pairLinks = @($response.value | Where-Object {
        $_.properties.sourceId.TrimEnd('/') -ieq $sourceId -and
        $_.properties.targetId.TrimEnd('/') -ieq $targetId
    })
    $canonicalLinks = @($pairLinks | Where-Object {
        $_.properties.sourceId.TrimEnd('/') -ceq $sourceId -and
        $_.properties.targetId.TrimEnd('/') -ceq $targetId
    })
    if ($canonicalLinks.Count -ne 1 -or $pairLinks.Count -ne 1) {
        throw "$description must have exactly one case-sensitive canonical resource link."
    }
}

if (-not $api.properties.subscriptionRequired) { throw 'The portal-compatible Foundry API must require a subscription.' }
if ($legacyPolicyPresent) { throw 'The legacy model API policy must not be present.' }
if ($keylessApi.properties.subscriptionRequired) { throw 'The hosted-agent model API must not require an APIM subscription.' }
if ($backend.properties.credentials.managedIdentity.resource -ne 'https://ai.azure.com/') { throw 'The Foundry backend managed-identity audience is invalid.' }
if (@($operations.value).Count -ne 8) { throw 'The portal-compatible Foundry API must have eight wildcard operations.' }
if (@($keylessOperations.value).Count -ne 8) { throw 'The hosted-agent model API must have eight wildcard operations.' }
if ($keylessPolicy -notmatch '<validate-azure-ad-token' -or $keylessPolicy -notmatch '<llm-token-limit') { throw 'The hosted-agent model policy is invalid.' }
if (@($productApis.value | Where-Object { $_.name -eq $context.AccountName }).Count -ne 1) { throw 'The project product is not associated with the portal-compatible Foundry API.' }
if ($productSubscriptions.Count -ne 0) { throw 'The project APIM product must not have a subscription.' }
if (@($accountRoleAssignments.value | Where-Object {
    $_.properties.principalId -eq $apim.identity.principalId -and
    $_.properties.roleDefinitionId -eq $cognitiveServicesUserRoleDefinitionId
}).Count -ne 1) { throw 'The APIM Cognitive Services User assignment is missing from the Foundry account.' }
Assert-CanonicalResourceLink $accountLinks $context.AccountId $context.ApimId 'Account-to-APIM association'
Assert-CanonicalResourceLink $apimLinks $context.ApimId $context.AccountId 'APIM-to-account association'
Assert-CanonicalResourceLink $projectLinks $context.ProjectId $productId 'Project-to-product association'
if ($agentApi.properties.path -ne 'agent' -or $agentApi.properties.subscriptionRequired) { throw 'The hosted-agent APIM ingress API is invalid.' }
if (@($agentOperations.value | Where-Object { $_.properties.method -eq 'POST' -and $_.properties.urlTemplate -eq '/responses' }).Count -ne 1) { throw 'The hosted-agent responses operation is missing.' }
if ($agentPolicy -notmatch '<validate-azure-ad-token' -or $agentPolicy -notmatch '<set-query-parameter name="api-version"') { throw 'The hosted-agent ingress policy is invalid.' }
if ($mcpApi.properties.type -ne 'mcp' -or $mcpApi.properties.backendId -ne 'mcp') { throw 'The MCP API is invalid.' }
if ($mcpPolicy -notmatch '<llm-content-safety' -or $mcpPolicy -notmatch '<rate-limit-by-key') { throw 'The MCP governance policy is missing.' }
if ($contentSafetyBackend.properties.credentials.managedIdentity.resource -ne 'https://cognitiveservices.azure.com') { throw 'The Content Safety backend managed identity is invalid.' }

[pscustomobject]@{
    Api = $api.name
    ModelApi = $keylessApi.name
    Backend = $backend.name
    Product = $product.name
    SubscriptionPresent = $false
    LegacyPolicyPresent = $legacyPolicyPresent
    Operations = @($operations.value).Count
    ResourceLinks = 3
    ProjectProductAssociationPresent = $true
    ApimCognitiveServicesAccess = 'Passed'
    AgentGateway = $context.AgentGatewayEndpoint
    McpGovernance = 'Passed'
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

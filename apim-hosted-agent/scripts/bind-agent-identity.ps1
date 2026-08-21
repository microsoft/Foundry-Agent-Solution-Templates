Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment value $name."
    }
    return ($value | Out-String).Trim()
}

$agent = (& azd ai agent show agent --output json | Out-String) | ConvertFrom-Json
$principalId = [string] $agent.instance_identity.principal_id
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
    throw 'Unable to resolve the hosted-agent managed identity.'
}

$subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
$resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$accountName = Get-AzdValue 'AZURE_AI_ACCOUNT_NAME'
$apimName = Get-AzdValue 'APIM_NAME'
$foundryUserRoleDefinitionId = "/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
$foundryAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
$namedValueId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/namedValues/foundry-agent-principal-id"

$foundryUserAssignments = @(& az role assignment list `
    --assignee-object-id $principalId `
    --scope $foundryAccountId `
    --fill-principal-name false `
    --query "[?roleDefinitionId=='$foundryUserRoleDefinitionId']" `
    --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the hosted-agent Foundry User assignment.'
}
if ($foundryUserAssignments.Count -eq 0) {
    & az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role $foundryUserRoleDefinitionId `
        --scope $foundryAccountId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to grant Foundry User to the hosted-agent identity.'
    }
}

& az resource update `
    --ids $namedValueId `
    --api-version 2024-05-01 `
    --set "properties.value=$principalId" `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to authorize the hosted-agent identity on the direct APIM Responses route.'
}

Write-Host "Foundry User assigned to hosted-agent principal $principalId."
Write-Host "Direct APIM Responses route bound to hosted-agent principal $principalId."

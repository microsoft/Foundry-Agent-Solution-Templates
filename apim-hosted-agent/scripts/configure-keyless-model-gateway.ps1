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
$apimName = Get-AzdValue 'APIM_NAME'
$namedValueId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/namedValues/foundry-agent-principal-id"

& az resource update `
    --ids $namedValueId `
    --api-version 2024-05-01 `
    --set "properties.value=$principalId" `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to bind the hosted-agent identity to the keyless APIM model gateway.'
}

Write-Host "Keyless APIM model gateway bound to hosted-agent principal $principalId."
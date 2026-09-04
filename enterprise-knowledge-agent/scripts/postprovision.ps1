Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-AzdEnvironmentValue {
  param(
    [Parameter(Mandatory)] [string] $Name,
    [string] $Default = '',
    [switch] $Required
  )

  $output = & azd env get-value $Name 2>$null
  $succeeded = $LASTEXITCODE -eq 0
  $value = if ($succeeded) { ($output | Out-String).Trim() } else { '' }

  if ($value) { return $value }
  if ($Required) { throw "Required azd environment value $Name is missing." }
  return $Default
}

$accountName = Get-AzdEnvironmentValue -Name AZURE_AI_ACCOUNT_NAME -Required
$foundryResourceGroup = Get-AzdEnvironmentValue -Name AZURE_FOUNDRY_RESOURCE_GROUP
if (-not $foundryResourceGroup) {
  # Compatibility with environments created by older Foundry provider versions.
  $foundryResourceGroup = Get-AzdEnvironmentValue -Name AZURE_RESOURCE_GROUP -Required
}
$searchMode = Get-AzdEnvironmentValue -Name AZURE_SEARCH_MODE -Default 'demo'
if ($searchMode -notin @('demo', 'byo')) {
  throw "AZURE_SEARCH_MODE must be 'demo' or 'byo'."
}
$searchEndpoint = Get-AzdEnvironmentValue -Name AZURE_SEARCH_ENDPOINT -Required
$searchId = Get-AzdEnvironmentValue -Name AZURE_SEARCH_SERVICE_ID -Required
[Environment]::SetEnvironmentVariable('AZURE_SEARCH_ENDPOINT', $searchEndpoint, 'Process')
[Environment]::SetEnvironmentVariable('AZURE_SEARCH_SERVICE_ID', $searchId, 'Process')
& az resource show --ids $searchId --output none
if ($LASTEXITCODE -ne 0) { throw 'Configured Azure AI Search resource is unavailable.' }

if ($searchMode -eq 'demo') {
  $searchPrincipalId = Get-AzdEnvironmentValue -Name AZURE_SEARCH_PRINCIPAL_ID -Required
  $foundryAccountId = "/subscriptions/$((Get-AzdEnvironmentValue -Name AZURE_SUBSCRIPTION_ID -Required))/resourceGroups/$foundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
  $modelRole = 'a97b65f3-24c7-4388-baec-2e87135dc908'
  $assignmentCount = & az role assignment list --assignee-object-id $searchPrincipalId --scope $foundryAccountId --query "[?contains(roleDefinitionId, '$modelRole')] | length(@)" --output tsv
  if ([int]$assignmentCount -eq 0) {
    Write-Host 'Granting the demo Search identity model invocation access...'
    & az role assignment create --assignee-object-id $searchPrincipalId --assignee-principal-type ServicePrincipal --role $modelRole --scope $foundryAccountId --output none
    if ($LASTEXITCODE -ne 0) { throw 'Unable to grant model invocation access to demo Search.' }
  }
} else {
  Write-Host "Using customer-provided Azure AI Search: $searchEndpoint"
}
foreach ($name in @('FOUNDRY_PROJECT_ENDPOINT', 'AZURE_AI_MODEL_DEPLOYMENT_NAME')) {
  $value = Get-AzdEnvironmentValue -Name $name -Required
  [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}
[Environment]::SetEnvironmentVariable('AZURE_ENV_NAME', (Get-AzdEnvironmentValue -Name AZURE_ENV_NAME -Required), 'Process')
Write-Host 'Installing provisioning dependencies...'
python -m pip install --quiet --requirement ./scripts/requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Provisioning dependency installation failed.' }
Write-Host 'Validating optional sources and provisioning Knowledge Sources, Knowledge Base, and Toolbox...'
python ./scripts/provision.py
if ($LASTEXITCODE -ne 0) { throw 'Enterprise knowledge provisioning failed.' }

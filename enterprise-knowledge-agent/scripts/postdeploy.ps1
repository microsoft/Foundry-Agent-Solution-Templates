Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$agent = (& azd ai agent show enterprise-knowledge-agent --output json | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read deployed agent.' }
$principalId = [string]$agent.instance_identity.principal_id
if ([string]::IsNullOrWhiteSpace($principalId)) { throw 'Hosted-agent identity was not returned.' }
$searchId = (& azd env get-value AZURE_SEARCH_SERVICE_ID | Out-String).Trim()
$searchModeOutput = & azd env get-value AZURE_SEARCH_MODE 2>$null
$searchMode = if ($LASTEXITCODE -eq 0) { ($searchModeOutput | Out-String).Trim() } else { 'demo' }
$existing = @(& az role assignment list --assignee-object-id $principalId --scope $searchId --role 'Search Index Data Reader' --output json | ConvertFrom-Json)
if ($existing.Count -eq 0 -and $searchMode -eq 'demo') {
  & az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Search Index Data Reader' --scope $searchId --output none
  if ($LASTEXITCODE -ne 0) { throw 'Unable to grant Search Index Data Reader to hosted agent.' }
}
elseif ($existing.Count -eq 0) {
  throw 'The hosted-agent identity needs Search Index Data Reader on the customer-provided Search service. The template does not change customer-owned RBAC.'
}
Write-Host 'Hosted Agent Search access is ready.'

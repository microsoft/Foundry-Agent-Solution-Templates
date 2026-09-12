Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$endpoint = ''
$endpointOutput = & azd env get-value AZURE_SEARCH_ENDPOINT 2>$null
if ($LASTEXITCODE -eq 0) { $endpoint = ($endpointOutput | Out-String).Trim() }
if ($endpoint) {
  [Environment]::SetEnvironmentVariable('AZURE_SEARCH_ENDPOINT', $endpoint, 'Process')
  [Environment]::SetEnvironmentVariable('AZURE_ENV_NAME', ((& azd env get-value AZURE_ENV_NAME | Out-String).Trim()), 'Process')
  python ./scripts/cleanup.py
  if ($LASTEXITCODE -ne 0) { throw 'Search cleanup failed; stopping teardown to preserve ownership and dependencies.' }
}
$toolboxNameOutput = & azd env get-value TOOLBOX_NAME 2>$null
if ($LASTEXITCODE -eq 0) {
  & azd ai toolbox delete (($toolboxNameOutput | Out-String).Trim()) --force --no-prompt
  if ($LASTEXITCODE -ne 0) { throw 'Toolbox cleanup failed; rerun azd down after resolving the error.' }
}
$connectionNameOutput = & azd env get-value KB_CONNECTION_NAME 2>$null
if ($LASTEXITCODE -eq 0) {
  $deleteOutput = & azd ai connection delete (($connectionNameOutput | Out-String).Trim()) --force --no-prompt 2>&1
  $deleteExitCode = $LASTEXITCODE
  $deleteText = $deleteOutput | Out-String
  if ($deleteExitCode -ne 0 -and $deleteText -notmatch '(?m)^RESPONSE 404:') {
    Write-Host $deleteText
    throw 'Connection cleanup failed; rerun azd down after resolving the error.'
  }
  if ($deleteExitCode -eq 0) { Write-Host $deleteText }
  else { Write-Host 'Template connection is already absent.' }
}

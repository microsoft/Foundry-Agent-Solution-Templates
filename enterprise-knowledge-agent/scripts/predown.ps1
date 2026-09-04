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
}
$toolboxNameOutput = & azd env get-value TOOLBOX_NAME 2>$null
if ($LASTEXITCODE -eq 0) { & azd ai toolbox delete (($toolboxNameOutput | Out-String).Trim()) --force --no-prompt 2>$null }
$connectionNameOutput = & azd env get-value KB_CONNECTION_NAME 2>$null
if ($LASTEXITCODE -eq 0) { & azd ai connection delete (($connectionNameOutput | Out-String).Trim()) --force --no-prompt 2>$null }

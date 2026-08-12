param([string]$EnvironmentName = '')

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName

$endpoint = Require-Value $values 'AZURE_SEARCH_ENDPOINT'
$indexName = Require-Value $values 'AZURE_SEARCH_INDEX_NAME'
$vaultUri = Require-Value $values 'AZURE_KEY_VAULT_URI'
$keyName = Require-Value $values 'AZURE_SEARCH_CMK_KEY_NAME'
$keyVersion = Require-Value $values 'AZURE_SEARCH_CMK_KEY_VERSION'
$corpus = Join-Path (Split-Path $PSScriptRoot) 'demo-data/search-documents.json'

python "$PSScriptRoot/seed_search.py" `
    --endpoint $endpoint `
    --index-name $indexName `
    --vault-uri $vaultUri `
    --key-name $keyName `
    --key-version $keyVersion `
    --corpus $corpus
if ($LASTEXITCODE -ne 0) {
    throw 'Search seeding failed. Run this script only from an approved private path.'
}

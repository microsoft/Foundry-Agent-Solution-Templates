param(
    [switch]$ValidateSearchIndexEncryption,
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName
$resourceGroup = Require-Value $values 'AZURE_RESOURCE_GROUP'
$vaultName = Require-Value $values 'AZURE_KEY_VAULT_NAME'
$vaultUri = Require-Value $values 'AZURE_KEY_VAULT_URI'
$foundryName = Require-Value $values 'AZURE_AI_ACCOUNT_NAME'
$foundryKeyId = Require-Value $values 'AZURE_FOUNDRY_CMK_KEY_ID'
$foundryKeyName = Require-Value $values 'AZURE_FOUNDRY_CMK_KEY_NAME'
$foundryKeyVersion = Require-Value $values 'AZURE_FOUNDRY_CMK_KEY_VERSION'
$searchKeyId = Require-Value $values 'AZURE_SEARCH_CMK_KEY_ID'
if ($foundryKeyId.TrimEnd('/').Equals(
    $searchKeyId.TrimEnd('/'),
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Foundry and Search must use separate customer-managed keys.'
}

$vault = az keyvault show -g $resourceGroup -n $vaultName | ConvertFrom-Json
if (-not $vault.properties.enablePurgeProtection) {
    throw 'Key Vault purge protection is disabled.'
}
if (-not $vault.properties.enableRbacAuthorization) {
    throw 'Key Vault RBAC authorization is disabled.'
}

foreach ($keyId in @($foundryKeyId, $searchKeyId)) {
    $key = az resource show --ids $keyId --api-version 2024-11-01 | ConvertFrom-Json
    if (-not $key -or $key.properties.attributes.enabled -ne $true) {
        throw "CMK '$keyId' is missing or disabled."
    }
}

$encryption = az cognitiveservices account show -g $resourceGroup -n $foundryName `
    --query properties.encryption | ConvertFrom-Json
if ($encryption.keySource -ne 'Microsoft.KeyVault' -or
    $encryption.keyVaultProperties.keyVaultUri.TrimEnd('/') -ne
        $vaultUri.TrimEnd('/') -or
    $encryption.keyVaultProperties.keyName -ne $foundryKeyName -or
    $encryption.keyVaultProperties.keyVersion -ne $foundryKeyVersion) {
    throw 'Foundry CMK configuration does not reference the expected Key Vault key version.'
}

if ($ValidateSearchIndexEncryption) {
    $searchEndpoint = Require-Value $values 'AZURE_SEARCH_ENDPOINT'
    $indexName = Require-Value $values 'AZURE_SEARCH_INDEX_NAME'
    $searchKeyName = Require-Value $values 'AZURE_SEARCH_CMK_KEY_NAME'
    $searchKeyVersion = Require-Value $values 'AZURE_SEARCH_CMK_KEY_VERSION'
    $token = az account get-access-token `
        --resource 'https://search.azure.com' `
        --query accessToken `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to acquire an Azure AI Search data-plane token.'
    }
    $encodedIndexName = [Uri]::EscapeDataString($indexName)
    $index = Invoke-RestMethod `
        -Method Get `
        -Uri "$($searchEndpoint.TrimEnd('/'))/indexes/$encodedIndexName`?api-version=2026-04-01" `
        -Headers @{
            Authorization = "Bearer $token"
            Accept = 'application/json'
        }
    if ($null -eq $index.encryptionKey -or
        $index.encryptionKey.keyVaultUri.TrimEnd('/') -ne
            $vaultUri.TrimEnd('/') -or
        $index.encryptionKey.keyVaultKeyName -ne $searchKeyName -or
        $index.encryptionKey.keyVaultKeyVersion -ne $searchKeyVersion) {
        throw 'Search index encryption does not reference the expected Key Vault key version.'
    }
}
Write-Host '[OK] Key Vault protection and separate live CMK bindings are configured.'

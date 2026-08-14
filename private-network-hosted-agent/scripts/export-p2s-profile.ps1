param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot) 'artifacts/p2s'),
    [string]$AdditionalDnsSuffixesJson = '[]',
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName
$resourceGroup = Require-Value $values 'AZURE_RESOURCE_GROUP'
$gatewayName = Require-Value $values 'AZURE_VPN_GATEWAY_NAME'
$resolverIp = Require-Value $values 'AZURE_DNS_RESOLVER_INBOUND_IP'
$foundryEndpoint = [Uri](Require-Value $values 'FOUNDRY_PROJECT_ENDPOINT')
$searchEndpoint = [Uri](Require-Value $values 'AZURE_SEARCH_ENDPOINT')
$keyVaultUri = [Uri](Require-Value $values 'AZURE_KEY_VAULT_URI')
$mode = Require-Value $values 'CONNECTIVITY_MODE'
if ($mode -ne 'pointToSite') {
    throw "P2S profile export is unavailable for connectivity mode '$mode'."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$url = az network vnet-gateway vpn-client generate `
    --resource-group $resourceGroup `
    --name $gatewayName `
    -o tsv
if (-not $url) {
    throw 'Azure did not return a VPN profile URL.'
}

$zip = Join-Path $OutputDirectory 'vpn-client-profile.zip'
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $OutputDirectory -Force

$azureVpnDirectory = Join-Path $OutputDirectory 'AzureVPN'
$rawProfiles = @(
    'azurevpnconfig.xml',
    'azurevpnconfig_aad.xml'
) |
    ForEach-Object { Get-Item (Join-Path $azureVpnDirectory $_) -ErrorAction SilentlyContinue }
$sourceProfile = $rawProfiles | Select-Object -First 1
if (-not $sourceProfile) {
    throw 'The generated package does not contain an Azure VPN Client XML profile.'
}

$foundryAccountName = $values['AZURE_AI_ACCOUNT_NAME']
$searchServiceName = $values['AZURE_SEARCH_SERVICE_NAME']
$keyVaultName = $values['AZURE_KEY_VAULT_NAME']
$additionalDnsSuffixes = @($AdditionalDnsSuffixesJson | ConvertFrom-Json)
$suffixes = @(
    $foundryEndpoint.Host,
    "$foundryAccountName.privatelink.services.ai.azure.com",
    "$foundryAccountName.cognitiveservices.azure.com",
    "$foundryAccountName.privatelink.cognitiveservices.azure.com",
    "$foundryAccountName.openai.azure.com",
    "$foundryAccountName.privatelink.openai.azure.com",
    $searchEndpoint.Host,
    "$searchServiceName.privatelink.search.windows.net",
    $keyVaultUri.Host,
    "$keyVaultName.privatelink.vaultcore.azure.net"
) + $additionalDnsSuffixes
$suffixes = @($suffixes | ForEach-Object {
    $suffix = $_.Trim().ToLowerInvariant()
    if ($suffix -in @('azurecr.io', 'privatelink.azurecr.io') -or
        $suffix -match '[*/:]') {
        throw "DNS suffix '$suffix' is not an exact resource hostname."
    }
    $suffix
} | Sort-Object -Unique)
$suffixXml = ($suffixes | ForEach-Object {
    "      <dnssuffix>$_</dnssuffix>"
}) -join [Environment]::NewLine
$dnsBlock = @"
  <clientconfig>
    <dnsservers>
      <dnsserver>$resolverIp</dnsserver>
    </dnsservers>
    <dnssuffixes>
$suffixXml
    </dnssuffixes>
  </clientconfig>
"@

# Azure VPN Client uses a strict DataContract serializer. Preserve the gateway
# profile byte structure and replace only these elements; DOM reserialization
# can produce a well-formed file that the client imports as blank fields.
$profileText = Get-Content $sourceProfile.FullName -Raw
$nilClientConfig = [regex]::new(
    '<clientconfig\s+i:nil="true"\s*/>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$existingClientConfig = [regex]::new(
    '<clientconfig(?:\s+[^>]*)?>.*?</clientconfig>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
)
if ($nilClientConfig.IsMatch($profileText)) {
    $profileText = $nilClientConfig.Replace($profileText, $dnsBlock, 1)
}
elseif ($existingClientConfig.IsMatch($profileText)) {
    $profileText = $existingClientConfig.Replace($profileText, $dnsBlock, 1)
}
else {
    throw 'The Azure VPN Client profile does not contain a supported clientconfig.'
}

$namePattern = [regex]::new(
    '<name>([^<]+)</name>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
if (-not $namePattern.IsMatch($profileText)) {
    throw 'The Azure VPN Client profile does not contain a profile name.'
}
$profileText = $namePattern.Replace(
    $profileText,
    '<name>${1}-resource-dns</name>',
    1
)

$scopedProfile = Join-Path $sourceProfile.DirectoryName 'azurevpnconfig-resource-dns.xml'
[System.IO.File]::WriteAllText(
    $scopedProfile,
    $profileText,
    [System.Text.UTF8Encoding]::new($false)
)
Remove-Item -LiteralPath $rawProfiles.FullName -Force

Write-Host "VPN package written to $OutputDirectory."
Write-Host "Import $scopedProfile into Azure VPN Client; remove earlier profiles for this gateway first."

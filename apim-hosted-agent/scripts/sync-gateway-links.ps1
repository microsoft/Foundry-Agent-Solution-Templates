Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bicep emits resource-link IDs with lowercase resourcegroups, but the Foundry portal requires resourceGroups.
function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment value $name."
    }
    return ($value | Out-String).Trim()
}

function Get-LinkName([string] $sourceId, [string] $targetId) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$sourceId|$targetId")
        $hash = $sha256.ComputeHash($bytes)
        return ([System.Convert]::ToHexString($hash)).Substring(0, 16).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-ResourceLinks([hashtable] $headers, [string] $sourceId) {
    $uri = "https://management.azure.com${sourceId}/providers/Microsoft.Resources/links?api-version=2016-09-01"
    return @((Invoke-RestMethod -Headers $headers -Uri $uri).value)
}

function Test-ResourceIdEqual([string] $left, [string] $right, [bool] $caseSensitive) {
    $comparison = if ($caseSensitive) {
        [System.StringComparison]::Ordinal
    }
    else {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    return [string]::Equals($left.TrimEnd('/'), $right.TrimEnd('/'), $comparison)
}

function Repair-ResourceLink(
    [hashtable] $headers,
    [string] $sourceId,
    [string] $targetId
) {
    $linkName = Get-LinkName $sourceId $targetId
    $linkUri = "https://management.azure.com${sourceId}/providers/Microsoft.Resources/links/${linkName}?api-version=2016-09-01"
    $body = @{ properties = @{ targetId = $targetId } } | ConvertTo-Json -Compress
    $link = Invoke-RestMethod `
        -Method Put `
        -Headers $headers `
        -Uri $linkUri `
        -ContentType 'application/json' `
        -Body $body

    if (-not (Test-ResourceIdEqual $link.properties.sourceId $sourceId $true)) {
        throw "ARM did not preserve the canonical source ID for link $linkName. Returned: $($link.properties.sourceId)"
    }
    if (-not (Test-ResourceIdEqual $link.properties.targetId $targetId $true)) {
        throw "ARM did not preserve the canonical target ID for link $linkName. Returned: $($link.properties.targetId)"
    }

    $staleLinks = @(Get-ResourceLinks $headers $sourceId | Where-Object {
        $_.name -ne $linkName -and
        (Test-ResourceIdEqual $_.properties.sourceId $sourceId $false) -and
        (Test-ResourceIdEqual $_.properties.targetId $targetId $false)
    })
    foreach ($staleLink in $staleLinks) {
        Invoke-RestMethod `
            -Method Delete `
            -Headers $headers `
            -Uri "https://management.azure.com$($staleLink.id)?api-version=2016-09-01" | Out-Null
    }

    $canonicalLinks = @()
    foreach ($attempt in 1..10) {
        $canonicalLinks = @(Get-ResourceLinks $headers $sourceId | Where-Object {
            (Test-ResourceIdEqual $_.properties.sourceId $sourceId $true) -and
            (Test-ResourceIdEqual $_.properties.targetId $targetId $true)
        })
        if ($canonicalLinks.Count -eq 1) {
            break
        }
        if ($attempt -lt 10) {
            [System.Threading.Tasks.Task]::Delay(1000).GetAwaiter().GetResult()
        }
    }
    if ($canonicalLinks.Count -ne 1) {
        throw "Expected one canonical resource link from $sourceId to $targetId; found $($canonicalLinks.Count)."
    }
}

$subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
$resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$accountName = Get-AzdValue 'AZURE_AI_ACCOUNT_NAME'
$projectName = Get-AzdValue 'AZURE_AI_PROJECT_NAME'
$apimName = Get-AzdValue 'APIM_NAME'
$productName = Get-AzdValue 'APIM_FOUNDRY_PRODUCT_NAME'
$accountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
$projectId = "$accountId/projects/$projectName"
$apimId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName"
$productId = "$apimId/products/$productName"
$token = & az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire an Azure Resource Manager token.'
}
$headers = @{ Authorization = "Bearer $token" }

Repair-ResourceLink $headers $accountId $apimId
Repair-ResourceLink $headers $apimId $accountId
Repair-ResourceLink $headers $projectId $productId

Write-Host 'Foundry AI Gateway resource links are synchronized.'

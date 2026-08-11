# Shared validation helpers.
# Purpose: Provide authentication, APIM invocation, policy, and runner utilities.
# Validates: Nothing by itself; individual test-case scripts perform assertions.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment value $name."
    }
    return ($value | Out-String).Trim()
}

function Get-ArmHeaders {
    $token = & az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to acquire an Azure Resource Manager token.'
    }
    return @{ Authorization = "Bearer $token" }
}

function Get-FoundryHeaders([switch] $ToolboxPreview) {
    $token = & az account get-access-token --resource https://ai.azure.com/ --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to acquire a Microsoft Foundry token.'
    }
    $headers = @{ Authorization = "Bearer $token" }
    if ($ToolboxPreview) {
        $headers['Foundry-Features'] = 'Toolboxes=V1Preview'
    }
    return $headers
}

function Invoke-AgentGateway(
    [string] $Prompt,
    [switch] $WithoutAuthentication
) {
    $headers = @{ Accept = 'text/event-stream, application/json' }
    if (-not $WithoutAuthentication) {
        $headers = Get-FoundryHeaders
        $headers.Accept = 'text/event-stream, application/json'
    }
    $body = @{
        input = $Prompt
        store = $false
    } | ConvertTo-Json -Compress
    return Invoke-WebRequest `
        -Method Post `
        -Uri (Get-AzdValue 'APIM_AGENT_GATEWAY_URL') `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -SkipHttpErrorCheck
}

function Assert-AgentGatewayResponse([object] $Response) {
    if ($null -eq $Response.Headers['x-agent-calls-remaining']) {
        throw 'The response does not contain the APIM hosted-agent ingress marker.'
    }
}

function Invoke-ValidationScript(
    [string] $Name,
    [string] $ScriptPath
) {
    try {
        $output = & $ScriptPath | Out-String
        return $output | ConvertFrom-Json
    }
    catch {
        throw "Validation case '$Name' failed in '$ScriptPath': $($_.Exception.Message)"
    }
}

function Set-ApimPolicy(
    [string] $Uri,
    [hashtable] $Headers,
    [string] $Xml
) {
    $body = @{
        properties = @{
            format = 'rawxml'
            value = $Xml
        }
    } | ConvertTo-Json -Depth 8
    Invoke-RestMethod -Method Put -Headers $Headers -Uri $Uri -ContentType 'application/json' -Body $body | Out-Null
}

function Get-PolicyXml([string] $uri, [hashtable] $headers) {
    $raw = (Invoke-WebRequest -Headers $headers -Uri $uri).Content.TrimStart([char] 0xFEFF)
    try {
        $document = $raw | ConvertFrom-Json
        return [System.Net.WebUtility]::HtmlDecode($document.properties.value)
    }
    catch {
        return $raw
    }
}

function Test-ApimPolicyExists([string] $uri, [hashtable] $headers) {
    try {
        Invoke-RestMethod -Headers $headers -Uri $uri | Out-Null
        return $true
    }
    catch {
        if ([int] $_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        throw
    }
}

function Get-ValidationContext {
    $subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
    $resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
    $accountName = Get-AzdValue 'AZURE_AI_ACCOUNT_NAME'
    $projectName = Get-AzdValue 'AZURE_AI_PROJECT_NAME'
    $apimName = Get-AzdValue 'APIM_NAME'
    return [pscustomobject]@{
        SubscriptionId = $subscriptionId
        ResourceGroup = $resourceGroup
        AccountName = $accountName
        ProjectName = $projectName
        ApimName = $apimName
        AccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
        ProjectId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName"
        ApimId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName"
        ProjectEndpoint = "https://$accountName.services.ai.azure.com/api/projects/$projectName"
        AgentGatewayEndpoint = Get-AzdValue 'APIM_AGENT_GATEWAY_URL'
    }
}

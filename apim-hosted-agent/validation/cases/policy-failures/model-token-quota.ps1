# Model token-quota policy failure validation case.
# Purpose: Verify the APIM model policy rejects a request when a validation-specific quota is exhausted.
# Validates: Inner APIM HTTP 403 quota failure is surfaced through the hosted-agent response; policies are restored.

. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'common.ps1')

$context = Get-ValidationContext
$headers = Get-ArmHeaders
$base = "https://management.azure.com$($context.ApimId)"
$modelApiPolicyUri = "$base/apis/$($context.AccountName)-keyless/policies/policy?api-version=2024-05-01"
$originalModelApiPolicy = Get-PolicyXml $modelApiPolicyUri $headers
$quotaPattern = '(<set-variable\s+name="tokenquota-\{\{foundry-model-deployment-name\}\}"\s+value=")[^"]+("\s*/>)'
$limitedModelApiPolicy = [regex]::Replace(
    $originalModelApiPolicy,
    $quotaPattern,
    { param($match) $match.Groups[1].Value + '1|Hourly' + $match.Groups[2].Value }
)
$validationCounter = "validation/$([guid]::NewGuid().ToString('N'))"
$limitedModelApiPolicy = [regex]::Replace(
    $limitedModelApiPolicy,
    '(<set-variable\s+name="counterKey"\s+value='')[^'']+(''\s*/>)',
    { param($match) $match.Groups[1].Value + "@(&quot;$validationCounter&quot;)" + $match.Groups[2].Value }
).Replace('estimate-prompt-tokens="false"', 'estimate-prompt-tokens="true"')
if ($limitedModelApiPolicy -eq $originalModelApiPolicy) {
    throw 'Unable to construct the isolated model token-policy failure case.'
}
try {
    Set-ApimPolicy $modelApiPolicyUri $headers $limitedModelApiPolicy
    $rejected = $false
    foreach ($attempt in 1..20) {
        $response = Invoke-AgentGateway 'Reply with exactly UNEXPECTED_MODEL_SUCCESS.'
        Assert-AgentGatewayResponse $response
        if ([int] $response.StatusCode -eq 200 -and
            $response.Content -match '"status":"failed"' -and
            $response.Content -match 'Token quota is exceeded' -and
            $response.Content -match 'Error code: 403') {
            $rejected = $true
            break
        }
        [System.Threading.Tasks.Task]::Delay(2000).GetAwaiter().GetResult()
    }
    if (-not $rejected) {
        throw 'Model token policy did not reject the isolated one-token quota.'
    }
}
finally {
    Set-ApimPolicy $modelApiPolicyUri $headers $originalModelApiPolicy
}

[pscustomobject]@{
    Scenario = 'Validation-specific one-token quota'
    Expected = 'Inner APIM HTTP 403 quota rejection'
    Actual = 'Hosted-agent response status failed with quota message'
    PoliciesRestored = $true
    AgentGateway = $context.AgentGatewayEndpoint
    Status = 'Passed'
} | ConvertTo-Json -Depth 5

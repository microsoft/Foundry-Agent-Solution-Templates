param([string]$EnvironmentName = '')

. "$PSScriptRoot/common.ps1"
$values = Get-AzdValues -EnvironmentName $EnvironmentName

$checks = @(
    @{
        Scope = (Require-Value $values 'AZURE_SEARCH_SERVICE_ID')
        Principal = (Require-Value $values 'DEPLOYMENT_PRINCIPAL_OBJECT_ID')
        Roles = @('Search Service Contributor', 'Search Index Data Contributor')
    },
    @{
        Scope = (Require-Value $values 'AZURE_FOUNDRY_CMK_KEY_ID')
        Principal = (Require-Value $values 'AZURE_FOUNDRY_CMK_IDENTITY_PRINCIPAL_ID')
        Roles = @('Key Vault Crypto User')
    },
    @{
        Scope = (Require-Value $values 'AZURE_KEY_VAULT_ID')
        Principal = (Require-Value $values 'AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID')
        Roles = @('Key Vault Crypto User')
    },
    @{
        Scope = (Require-Value $values 'AZURE_KEY_VAULT_ID')
        Principal = (Require-Value $values 'AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID')
        Roles = @('Key Vault Crypto User')
    },
    @{
        Scope = (Require-Value $values 'AZURE_SEARCH_CMK_KEY_ID')
        Principal = (Require-Value $values 'AZURE_SEARCH_IDENTITY_PRINCIPAL_ID')
        Roles = @('Key Vault Crypto Service Encryption User')
    }
)

foreach ($check in $checks) {
    $assignments = @(az role assignment list `
        --assignee-object-id $check.Principal `
        --scope $check.Scope `
        --include-inherited | ConvertFrom-Json)
    foreach ($role in $check.Roles) {
        $expectedScope = $check.Scope.TrimEnd('/').ToLowerInvariant()
        $matching = @($assignments | Where-Object {
            $_.roleDefinitionName -eq $role -and
            $_.scope.TrimEnd('/').ToLowerInvariant() -eq $expectedScope
        })
        if ($matching.Count -eq 0) {
            throw "Missing '$role' for '$($check.Principal)' at '$($check.Scope)'."
        }
    }
}
Write-Host '[OK] Static least-privilege role assignments are present.'

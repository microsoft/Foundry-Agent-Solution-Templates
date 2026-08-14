Set-StrictMode -Version Latest

function Test-AzurePermissionPattern {
    param(
        [string]$Pattern,
        [string]$Action
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return $false
    }
    $expression = '^' +
        [Regex]::Escape($Pattern).Replace('\*', '.*') +
        '$'
    return [Regex]::IsMatch(
        $Action,
        $expression,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Test-AzurePermissionsAllowAction {
    param(
        [object[]]$Permissions,
        [string]$Action
    )

    foreach ($permission in @($Permissions)) {
        $allowed = @($permission.actions | Where-Object {
            Test-AzurePermissionPattern -Pattern $_ -Action $Action
        }).Count -gt 0
        if (-not $allowed) {
            continue
        }
        $denied = @($permission.notActions | Where-Object {
            Test-AzurePermissionPattern -Pattern $_ -Action $Action
        }).Count -gt 0
        if (-not $denied) {
            return $true
        }
    }
    return $false
}

function Get-AzureEffectivePermissions {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [bool]$ResourceGroupExists
    )

    $scope = "/subscriptions/$SubscriptionId"
    $scopeUrl = $scope
    if ($ResourceGroupExists) {
        $scope = "$scope/resourceGroups/$ResourceGroupName"
        $encodedResourceGroupName = [Uri]::EscapeDataString($ResourceGroupName)
        $scopeUrl = "$scopeUrl/resourceGroups/$encodedResourceGroupName"
    }
    $permissions = @()
    $url = "https://management.azure.com$scopeUrl/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
    do {
        $result = Invoke-CheckedCommand `
            -Stage 'Check deployment RBAC permissions' `
            -FilePath 'az' `
            -Arguments @(
                'rest',
                '--method', 'get',
                '--url', $url,
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Quiet
        $response = $result.Output -join "`n" | ConvertFrom-Json
        $permissions += @($response.value)
        $nextLinkProperty = $response.PSObject.Properties['nextLink']
        $url = if ($null -ne $nextLinkProperty) {
            [string]$nextLinkProperty.Value
        }
        else {
            ''
        }
    } while (-not [string]::IsNullOrWhiteSpace($url))
    return [pscustomobject]@{
        Scope = $scope
        Permissions = $permissions
    }
}

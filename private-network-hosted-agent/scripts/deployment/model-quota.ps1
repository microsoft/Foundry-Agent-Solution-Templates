Set-StrictMode -Version Latest

function Get-ModelQuotaPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Test-CanonicalFoundryAccountId {
    param(
        [string]$ResourceId,
        [string]$SubscriptionId,
        [string]$ResourceGroupName
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        $ResourceId -ne $ResourceId.Trim()) {
        return $false
    }
    $pattern = '^/subscriptions/{0}/resourceGroups/{1}/providers/' +
        'Microsoft\.CognitiveServices/accounts/[^/]+$'
    return $ResourceId -match ($pattern -f
        [regex]::Escape($SubscriptionId),
        [regex]::Escape($ResourceGroupName))
}

function Test-OwnedFoundryAccount {
    param(
        [object]$Account,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName,
        [string]$Location,
        [string]$ExpectedResourceId = ''
    )

    $resourceId = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Account `
        -Name 'id')
    if (-not (Test-CanonicalFoundryAccountId `
            -ResourceId $resourceId `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName)) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedResourceId) -and
        -not [string]::Equals(
            $resourceId,
            $ExpectedResourceId,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }
    $resourceType = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Account `
        -Name 'type')
    $kind = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Account `
        -Name 'kind')
    $accountLocation = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Account `
        -Name 'location')
    if (-not [string]::Equals(
            $resourceType,
            'Microsoft.CognitiveServices/accounts',
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        -not [string]::Equals(
            $kind,
            'AIServices',
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        -not [string]::Equals(
            ($accountLocation -replace '\s', ''),
            ($Location -replace '\s', ''),
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }

    $tags = Get-ModelQuotaPropertyValue -InputObject $Account -Name 'tags'
    if ($null -eq $tags) {
        return $false
    }
    $solutionTag = [string](Get-ModelQuotaPropertyValue `
        -InputObject $tags `
        -Name 'solution-template')
    $environmentTag = [string](Get-ModelQuotaPropertyValue `
        -InputObject $tags `
        -Name 'azd-env-name')
    $serviceTag = [string](Get-ModelQuotaPropertyValue `
        -InputObject $tags `
        -Name 'azd-service-name')
    return $solutionTag -ceq 'foundry-private-hosted-agent' -and
        $environmentTag -ceq $EnvironmentName -and
        $serviceTag -ceq 'private-search-agent'
}

function Test-CanonicalFoundryProjectId {
    param(
        [string]$ResourceId,
        [string]$AccountId
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        $ResourceId -ne $ResourceId.Trim()) {
        return $false
    }
    return $ResourceId -match (
        '^{0}/projects/[^/]+$' -f [regex]::Escape($AccountId)
    )
}

function Test-OwnedFoundryProject {
    param(
        [object]$Project,
        [string]$AccountId,
        [string]$EnvironmentName,
        [string]$Location,
        [string]$ExpectedResourceId = ''
    )

    $resourceId = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Project `
        -Name 'id')
    if (-not (Test-CanonicalFoundryProjectId `
            -ResourceId $resourceId `
            -AccountId $AccountId)) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedResourceId) -and
        -not [string]::Equals(
            $resourceId,
            $ExpectedResourceId,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }
    $resourceType = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Project `
        -Name 'type')
    $projectLocation = [string](Get-ModelQuotaPropertyValue `
        -InputObject $Project `
        -Name 'location')
    if (-not [string]::Equals(
            $resourceType,
            'Microsoft.CognitiveServices/accounts/projects',
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        -not [string]::Equals(
            ($projectLocation -replace '\s', ''),
            ($Location -replace '\s', ''),
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }
    $tags = Get-ModelQuotaPropertyValue -InputObject $Project -Name 'tags'
    if ($null -eq $tags) {
        return $false
    }
    return (Get-ModelQuotaPropertyValue `
            -InputObject $tags `
            -Name 'solution-template') -ceq 'foundry-private-hosted-agent' -and
        (Get-ModelQuotaPropertyValue `
            -InputObject $tags `
            -Name 'azd-env-name') -ceq $EnvironmentName -and
        (Get-ModelQuotaPropertyValue `
            -InputObject $tags `
            -Name 'azd-service-name') -ceq 'private-search-agent'
}

function Invoke-ModelQuotaRead {
    param(
        [string]$Stage,
        [string[]]$Arguments
    )

    try {
        $result = Invoke-CheckedCommand `
            -Stage $Stage `
            -FilePath 'az' `
            -Arguments $Arguments `
            -Quiet `
            -AllowFailure
    }
    catch {
        Write-Warning "$Stage failed; existing model capacity will not be credited."
        return $null
    }
    if ($result.ExitCode -ne 0) {
        Write-Warning "$Stage failed; existing model capacity will not be credited."
        return $null
    }
    $json = ($result.Output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }
    try {
        return $json | ConvertFrom-Json
    }
    catch {
        Write-Warning "$Stage returned unreadable data; existing model capacity will not be credited."
        return $null
    }
}

function Get-ExactReusableModelDeploymentCapacity {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$EnvironmentName,
        [string]$Location,
        [string]$ExpectedAccountId = '',
        [string]$ExpectedProjectId = '',
        [string]$DeploymentName = 'gpt-5.1',
        [string]$ModelName = 'gpt-5.1',
        [string]$ModelVersion = '2025-11-13',
        [string]$SkuName = 'Standard'
    )

    if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
        return 0
    }

    $accountId = $ExpectedAccountId
    if (-not [string]::IsNullOrWhiteSpace($accountId)) {
        if (-not (Test-CanonicalFoundryAccountId `
                -ResourceId $accountId `
                -SubscriptionId $SubscriptionId `
                -ResourceGroupName $ResourceGroupName)) {
            Write-Warning 'The cached Foundry account ID is outside the validated deployment scope; existing model capacity will not be credited.'
            return 0
        }
    }
    else {
        $accounts = Invoke-ModelQuotaRead `
            -Stage 'Discover owned Foundry account for quota reuse' `
            -Arguments @(
                'resource', 'list',
                '--subscription', $SubscriptionId,
                '--resource-group', $ResourceGroupName,
                '--resource-type', 'Microsoft.CognitiveServices/accounts',
                '--output', 'json',
                '--only-show-errors'
            )
        if ($null -eq $accounts) {
            return 0
        }
        $ownedAccounts = @($accounts | Where-Object {
            Test-OwnedFoundryAccount `
                -Account $_ `
                -SubscriptionId $SubscriptionId `
                -ResourceGroupName $ResourceGroupName `
                -EnvironmentName $EnvironmentName `
                -Location $Location
        })
        if ($ownedAccounts.Count -ne 1) {
            Write-Warning 'A unique template-owned Foundry account could not be proven; existing model capacity will not be credited.'
            return 0
        }
        $accountId = [string](Get-ModelQuotaPropertyValue `
            -InputObject $ownedAccounts[0] `
            -Name 'id')
    }

    $account = Invoke-ModelQuotaRead `
        -Stage 'Verify owned Foundry account for quota reuse' `
        -Arguments @(
            'resource', 'show',
            '--subscription', $SubscriptionId,
            '--ids', $accountId,
            '--api-version', '2025-04-01-preview',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($null -eq $account -or
        -not (Test-OwnedFoundryAccount `
            -Account $account `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -EnvironmentName $EnvironmentName `
            -Location $Location `
            -ExpectedResourceId $accountId)) {
        Write-Warning 'Foundry account ownership did not match the validated deployment context; existing model capacity will not be credited.'
        return 0
    }
    $properties = Get-ModelQuotaPropertyValue `
        -InputObject $account `
        -Name 'properties'
    if ((Get-ModelQuotaPropertyValue `
            -InputObject $properties `
            -Name 'allowProjectManagement') -ne $true) {
        Write-Warning 'The owned account is not a reusable Foundry account; existing model capacity will not be credited.'
        return 0
    }

    $projectId = $ExpectedProjectId
    if (-not [string]::IsNullOrWhiteSpace($projectId)) {
        if (-not (Test-CanonicalFoundryProjectId `
                -ResourceId $projectId `
                -AccountId $accountId)) {
            Write-Warning 'The cached Foundry project ID is outside the verified account; existing model capacity will not be credited.'
            return 0
        }
    }
    else {
        $projects = Invoke-ModelQuotaRead `
            -Stage 'Discover owned Foundry project for quota reuse' `
            -Arguments @(
                'resource', 'list',
                '--subscription', $SubscriptionId,
                '--resource-group', $ResourceGroupName,
                '--resource-type', 'Microsoft.CognitiveServices/accounts/projects',
                '--output', 'json',
                '--only-show-errors'
            )
        if ($null -eq $projects) {
            return 0
        }
        $ownedProjects = @($projects | Where-Object {
            Test-OwnedFoundryProject `
                -Project $_ `
                -AccountId $accountId `
                -EnvironmentName $EnvironmentName `
                -Location $Location
        })
        if ($ownedProjects.Count -ne 1) {
            Write-Warning 'A unique template-owned Foundry project could not be proven; existing model capacity will not be credited.'
            return 0
        }
        $projectId = [string](Get-ModelQuotaPropertyValue `
            -InputObject $ownedProjects[0] `
            -Name 'id')
    }
    $project = Invoke-ModelQuotaRead `
        -Stage 'Verify owned Foundry project for quota reuse' `
        -Arguments @(
            'resource', 'show',
            '--subscription', $SubscriptionId,
            '--ids', $projectId,
            '--api-version', '2025-04-01-preview',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($null -eq $project -or
        -not (Test-OwnedFoundryProject `
            -Project $project `
            -AccountId $accountId `
            -EnvironmentName $EnvironmentName `
            -Location $Location `
            -ExpectedResourceId $projectId)) {
        Write-Warning 'Foundry project ownership did not match the validated deployment context; existing model capacity will not be credited.'
        return 0
    }

    $deploymentId = "$accountId/deployments/$DeploymentName"
    $deployment = Invoke-ModelQuotaRead `
        -Stage 'Verify existing model deployment for quota reuse' `
        -Arguments @(
            'resource', 'show',
            '--subscription', $SubscriptionId,
            '--ids', $deploymentId,
            '--api-version', '2025-04-01-preview',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($null -eq $deployment) {
        return 0
    }

    $actualDeploymentId = [string](Get-ModelQuotaPropertyValue `
        -InputObject $deployment `
        -Name 'id')
    $actualDeploymentName = [string](Get-ModelQuotaPropertyValue `
        -InputObject $deployment `
        -Name 'name')
    $actualDeploymentType = [string](Get-ModelQuotaPropertyValue `
        -InputObject $deployment `
        -Name 'type')
    $deploymentProperties = Get-ModelQuotaPropertyValue `
        -InputObject $deployment `
        -Name 'properties'
    $model = Get-ModelQuotaPropertyValue `
        -InputObject $deploymentProperties `
        -Name 'model'
    $sku = Get-ModelQuotaPropertyValue -InputObject $deployment -Name 'sku'
    $capacity = Get-ModelQuotaPropertyValue -InputObject $sku -Name 'capacity'
    $capacityValue = 0
    $capacityIsValid = [int]::TryParse(
        [string]$capacity,
        [ref]$capacityValue
    ) -and $capacityValue -gt 0
    $isExactDeployment =
        [string]::Equals(
            $actualDeploymentId,
            $deploymentId,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $actualDeploymentName -ceq $DeploymentName -and
        [string]::Equals(
            $actualDeploymentType,
            'Microsoft.CognitiveServices/accounts/deployments',
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Get-ModelQuotaPropertyValue `
            -InputObject $deploymentProperties `
            -Name 'provisioningState') -ceq 'Succeeded' -and
        (Get-ModelQuotaPropertyValue -InputObject $model -Name 'format') -ceq 'OpenAI' -and
        (Get-ModelQuotaPropertyValue -InputObject $model -Name 'name') -ceq $ModelName -and
        (Get-ModelQuotaPropertyValue -InputObject $model -Name 'version') -ceq $ModelVersion -and
        (Get-ModelQuotaPropertyValue -InputObject $sku -Name 'name') -ceq $SkuName -and
        $capacityIsValid
    if (-not $isExactDeployment) {
        Write-Warning 'The existing model deployment does not exactly match the required reusable contract; its capacity will not be credited.'
        return 0
    }

    Write-Host "[REUSE] Verified $capacityValue K TPM of exact existing model capacity."
    return $capacityValue
}

function Assert-RegionalModelQuota {
    param(
        [object]$Usage,
        [int]$DesiredCapacity,
        [int]$ReusableExistingCapacity,
        [string]$ModelName,
        [string]$Location
    )

    $limit = Get-ModelQuotaPropertyValue -InputObject $Usage -Name 'limit'
    $currentValue = Get-ModelQuotaPropertyValue `
        -InputObject $Usage `
        -Name 'currentValue'
    $limitValue = 0
    $currentValueNumber = 0
    if ($null -eq $Usage -or
        -not [int]::TryParse([string]$limit, [ref]$limitValue) -or
        -not [int]::TryParse([string]$currentValue, [ref]$currentValueNumber)) {
        throw "Regional Standard quota for $ModelName in '$Location' could not be verified."
    }
    $availableCapacity = $limitValue - $currentValueNumber
    $requiredAdditionalCapacity = [Math]::Max(
        $DesiredCapacity - $ReusableExistingCapacity,
        0
    )
    if ($availableCapacity -lt $requiredAdditionalCapacity) {
        throw "Insufficient regional Standard quota for $ModelName in '$Location': $availableCapacity K TPM is available, but $requiredAdditionalCapacity K TPM of additional capacity is required."
    }
    return [pscustomobject]@{
        AvailableCapacity = $availableCapacity
        ReusableExistingCapacity = $ReusableExistingCapacity
        RequiredAdditionalCapacity = $requiredAdditionalCapacity
    }
}

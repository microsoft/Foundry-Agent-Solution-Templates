param(
    [string]$ContainerRegistryResourceId = '',
    [string]$ContainerRegistryEndpoint = '',
    [string]$ContainerImage = '',
    [string]$FoundryProjectId = '',
    [string]$FoundryProjectPrincipalId = '',
    [string]$AgentPrincipalId = '',
    [string]$ConnectionName = '',
    [string]$EnvironmentName = '',
    [switch]$ValidateConnection,
    [switch]$ValidatePullAuthorization,
    [switch]$RequirePrivateDataPlane
)

. "$PSScriptRoot/common.ps1"

function Test-RepositoryCondition {
    param(
        [string]$Condition,
        [string]$Repository
    )

    if ([string]::IsNullOrWhiteSpace($Condition)) {
        return $true
    }
    $attribute = '@Request\[Microsoft\.ContainerRegistry/registries/repositories:name\]'
    if ($Condition -notmatch $attribute) {
        return $false
    }

    foreach ($match in [regex]::Matches(
        $Condition,
        "$attribute\s+StringEqualsIgnoreCase\s+'([^']+)'",
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )) {
        if ($match.Groups[1].Value -ceq $Repository -or
            $match.Groups[1].Value.Equals($Repository, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($match in [regex]::Matches(
        $Condition,
        "$attribute\s+StringStartsWithIgnoreCase\s+'([^']+)'",
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )) {
        if ($Repository.StartsWith(
            $match.Groups[1].Value,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }
    return $false
}

function Get-RoleAssignmentCondition {
    param([object]$Assignment)

    $property = $Assignment.PSObject.Properties['condition']
    if ($null -eq $property) {
        return ''
    }
    return [string]$property.Value
}

function Get-AcrAccessToken {
    param(
        [string]$RegistryName,
        [string]$Endpoint,
        [string]$Repository,
        [string]$SubscriptionId
    )

    $refreshToken = az acr login `
        --name $RegistryName `
        --subscription $SubscriptionId `
        --expose-token `
        --query accessToken `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($refreshToken)) {
        throw "Unable to acquire a data-plane token for '$Endpoint'."
    }

    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "https://$Endpoint/oauth2/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            grant_type = 'refresh_token'
            service = $Endpoint
            scope = "repository:$Repository`:pull"
            refresh_token = $refreshToken
        }
    $accessToken = if ($tokenResponse.access_token) {
        $tokenResponse.access_token
    }
    else {
        $tokenResponse.token
    }
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw "ACR did not issue a repository pull token for '$Repository'."
    }
    return $accessToken
}

function Get-AcrJson {
    param(
        [string]$Uri,
        [string]$AccessToken,
        [string]$Accept = 'application/json'
    )
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{
        Authorization = "Bearer $AccessToken"
        Accept = $Accept
    }
}

Assert-Command 'az'

$missingCoreValues = @(
    @(
        $ContainerRegistryResourceId,
        $ContainerRegistryEndpoint,
        $ContainerImage,
        $FoundryProjectId,
        $ConnectionName
    ) | Where-Object { [string]::IsNullOrWhiteSpace($_) }
)
$missingPullIdentityValues = @(
    @(
        $FoundryProjectPrincipalId,
        $AgentPrincipalId
    ) | Where-Object { [string]::IsNullOrWhiteSpace($_) }
)
$requiresAzdValues = $missingCoreValues.Count -gt 0 -or
    ($ValidatePullAuthorization -and $missingPullIdentityValues.Count -gt 0)
$values = @{}
if ($requiresAzdValues) {
    Assert-Command 'azd'
    $values = Get-AzdValues -EnvironmentName $EnvironmentName
    $skipRoleAssignments = Get-OptionalValue $values 'AZD_AGENT_SKIP_ROLE_ASSIGNMENTS'
    $skipEnabled = $false
    if (-not [bool]::TryParse($skipRoleAssignments, [ref]$skipEnabled) -or -not $skipEnabled) {
        throw 'AZD_AGENT_SKIP_ROLE_ASSIGNMENTS must be true so azd does not modify externally managed IAM.'
    }
}
if ([string]::IsNullOrWhiteSpace($ContainerRegistryResourceId)) {
    $ContainerRegistryResourceId = Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_RESOURCE_ID'
}
if ([string]::IsNullOrWhiteSpace($ContainerRegistryEndpoint)) {
    $ContainerRegistryEndpoint = Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_ENDPOINT'
}
if ([string]::IsNullOrWhiteSpace($ContainerImage)) {
    $ContainerImage = Get-OptionalValue $values 'AZURE_CONTAINER_IMAGE'
}
if ([string]::IsNullOrWhiteSpace($FoundryProjectId)) {
    $FoundryProjectId = Get-OptionalValue $values 'AZURE_AI_PROJECT_ID'
}
if ([string]::IsNullOrWhiteSpace($FoundryProjectPrincipalId)) {
    $FoundryProjectPrincipalId = Get-OptionalValue $values 'AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID'
}
if ([string]::IsNullOrWhiteSpace($AgentPrincipalId)) {
    $AgentPrincipalId = Get-OptionalValue $values 'AZURE_AI_AGENT_PRINCIPAL_ID'
}
if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
    $ConnectionName = Get-OptionalValue $values 'AZURE_AI_PROJECT_ACR_CONNECTION_NAME'
}
if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
    $ConnectionName = Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_CONNECTION_NAME'
}

foreach ($entry in @{
    AZURE_CONTAINER_REGISTRY_RESOURCE_ID = $ContainerRegistryResourceId
    AZURE_CONTAINER_REGISTRY_ENDPOINT = $ContainerRegistryEndpoint
    AZURE_CONTAINER_IMAGE = $ContainerImage
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($entry.Value)) {
        throw "Required ACR value '$($entry.Key)' is missing."
    }
}

$resourceIdPattern = '(?i)^/subscriptions/(?<subscription>[^/]+)/resourceGroups/(?<resourceGroup>[^/]+)/providers/Microsoft\.ContainerRegistry/registries/(?<name>[^/]+)$'
$privateEndpointResourceIdPattern = '(?i)^/subscriptions/(?<subscription>[^/]+)/resourceGroups/[^/]+/providers/Microsoft\.Network/privateEndpoints/[^/]+$'
if ($ContainerRegistryResourceId -notmatch $resourceIdPattern) {
    throw 'AZURE_CONTAINER_REGISTRY_RESOURCE_ID is not a canonical ACR ARM resource ID.'
}
$registrySubscription = $Matches.subscription
$registryResourceGroup = $Matches.resourceGroup
$registryName = $Matches.name

$imagePattern = '^(?<host>[a-z0-9-]+\.azurecr\.io)/(?<repository>[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*)@sha256:(?<digest>[a-f0-9]{64})$'
if ($ContainerImage -notmatch $imagePattern) {
    throw 'AZURE_CONTAINER_IMAGE must be a lowercase ACR image reference pinned by a sha256 digest.'
}
$imageHost = $Matches.host
$repository = $Matches.repository
$digest = "sha256:$($Matches.digest)"
if ($imageHost -cne $ContainerRegistryEndpoint) {
    throw "Image host '$imageHost' does not exactly match ACR endpoint '$ContainerRegistryEndpoint'."
}

$registry = az acr show `
    --name $registryName `
    --resource-group $registryResourceGroup `
    --subscription $registrySubscription `
    --output json `
    --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $registry) {
    throw "Unable to read enterprise ACR '$ContainerRegistryResourceId'."
}
if ($registry.loginServer -cne $ContainerRegistryEndpoint) {
    throw "Supplied endpoint does not match ACR loginServer '$($registry.loginServer)'."
}
if ($registry.sku.name -ne 'Premium') {
    throw "ACR '$registryName' must use Premium SKU."
}
if ($registry.publicNetworkAccess -ne 'Disabled') {
    throw "ACR '$registryName' public network access must be Disabled."
}
if ($registry.adminUserEnabled -ne $false) {
    throw "ACR '$registryName' admin user must be disabled."
}
if ($registry.anonymousPullEnabled -eq $true) {
    throw "ACR '$registryName' anonymous pull must be disabled."
}
$armAuthentication = az acr config authentication-as-arm show `
    --registry $registryName `
    --subscription $registrySubscription `
    --output json `
    --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $armAuthentication.status -ne 'enabled') {
    throw "ACR '$registryName' authentication-as-arm policy must be enabled."
}

$privateEndpointConnections = @(az acr private-endpoint-connection list `
    --registry-name $registryName `
    --resource-group $registryResourceGroup `
    --subscription $registrySubscription `
    --output json `
    --only-show-errors | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect private endpoint connections for '$registryName'."
}
$approvedRegistryConnections = @()
foreach ($connection in @($privateEndpointConnections | Where-Object {
    $_.privateLinkServiceConnectionState.status -eq 'Approved'
})) {
    if (-not $connection.privateEndpoint.id) {
        continue
    }
    $privateEndpointId = [string]$connection.privateEndpoint.id
    $privateEndpointIdMatch = [regex]::Match(
        $privateEndpointId,
        $privateEndpointResourceIdPattern
    )
    if (-not $privateEndpointIdMatch.Success) {
        throw "ACR private endpoint connection returned a non-canonical resource ID '$privateEndpointId'."
    }
    $privateEndpointSubscription = $privateEndpointIdMatch.Groups['subscription'].Value
    $privateEndpoint = az network private-endpoint show `
        --ids $privateEndpointId `
        --subscription $privateEndpointSubscription `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $privateEndpoint) {
        throw "Unable to inspect private endpoint '$privateEndpointId' in subscription '$privateEndpointSubscription'. Ensure the current principal has read access to that subscription."
    }
    $groupIds = @(
        @($privateEndpoint.privateLinkServiceConnections) |
            ForEach-Object { @($_.groupIds) }
    )
    if ('registry' -in $groupIds) {
        $approvedRegistryConnections += $connection
    }
}
if ($approvedRegistryConnections.Count -eq 0) {
    throw "ACR '$registryName' has no approved registry private endpoint connection."
}

if (-not [string]::IsNullOrWhiteSpace($FoundryProjectId)) {
    $project = az resource show `
        --ids $FoundryProjectId `
        --api-version 2025-04-01-preview `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $project.systemData.createdAt) {
        throw "Unable to read the Foundry project creation timestamp for '$FoundryProjectId'."
    }
    $liveProjectPrincipalId = [string]$project.identity.principalId
    if ([string]::IsNullOrWhiteSpace($liveProjectPrincipalId)) {
        throw "Foundry project '$FoundryProjectId' does not expose a managed identity principal."
    }
    if ([string]::IsNullOrWhiteSpace($FoundryProjectPrincipalId)) {
        $FoundryProjectPrincipalId = $liveProjectPrincipalId
    }
    elseif ($FoundryProjectPrincipalId -ne $liveProjectPrincipalId) {
        throw 'AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID does not match the live Foundry project identity.'
    }
    $createdAt = [DateTimeOffset]::Parse($project.systemData.createdAt)
    $privateAcrCutoff = [DateTimeOffset]::Parse('2026-06-25T00:00:00Z')
    if ($createdAt -le $privateAcrCutoff) {
        throw "Foundry project was created at '$createdAt'; fully private ACR requires a project created after June 25, 2026."
    }
}
elseif ($ValidateConnection -or $ValidatePullAuthorization) {
    throw 'AZURE_AI_PROJECT_ID is required for post-provision ACR validation.'
}

if ($ValidateConnection) {
    if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
        throw 'AZURE_AI_PROJECT_ACR_CONNECTION_NAME is required for connection validation.'
    }
    $connectionId = "$($FoundryProjectId.TrimEnd('/'))/connections/$ConnectionName"
    $connection = az resource show `
        --ids $connectionId `
        --api-version 2025-04-01-preview `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $connection) {
        throw "Foundry ACR connection '$ConnectionName' was not found."
    }
    if ($connection.properties.category -ne 'ContainerRegistry' -or
        $connection.properties.authType -ne 'ManagedIdentity' -or
        $connection.properties.target -cne $ContainerRegistryEndpoint -or
        $connection.properties.metadata.ResourceId -cne $ContainerRegistryResourceId) {
        throw "Foundry ACR connection '$ConnectionName' does not match the requested registry."
    }
}

if ($ValidatePullAuthorization) {
    if ([string]::IsNullOrWhiteSpace($FoundryProjectPrincipalId)) {
        throw 'AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID is required for ACR pull-role validation.'
    }
    if ([string]::IsNullOrWhiteSpace($AgentPrincipalId)) {
        throw 'AZURE_AI_AGENT_PRINCIPAL_ID is required for ACR pull-role validation.'
    }
    $roleMode = ([string]$registry.roleAssignmentMode).ToLowerInvariant()
    $isAbacMode = $roleMode -in @('rbac-abac', 'abacrepositorypermissions')
    $isRbacMode = $roleMode -in @('rbac', 'legacyregistrypermissions')
    if (-not $isAbacMode -and -not $isRbacMode) {
        throw "Unsupported ACR roleAssignmentMode '$($registry.roleAssignmentMode)'."
    }
    $requiredRole = if ($isAbacMode) {
        'Container Registry Repository Reader'
    }
    else {
        'AcrPull'
    }
    $missingIdentities = @()
    foreach ($identity in @(
        [pscustomobject]@{
            Label = 'Foundry project'
            PrincipalId = $FoundryProjectPrincipalId
        },
        [pscustomobject]@{
            Label = 'Hosted Agent'
            PrincipalId = $AgentPrincipalId
        }
    )) {
        $assignments = @(az role assignment list `
            --assignee-object-id $identity.PrincipalId `
            --scope $ContainerRegistryResourceId `
            --include-inherited `
            --output json `
            --only-show-errors | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect ACR pull authorization for '$($identity.PrincipalId)'."
        }
        $exactAssignments = @($assignments | Where-Object {
            $_.scope.TrimEnd('/').ToLowerInvariant() -eq $ContainerRegistryResourceId.TrimEnd('/').ToLowerInvariant()
        })
        $matching = @(
            if ($isAbacMode) {
                $exactAssignments | Where-Object {
                    $condition = Get-RoleAssignmentCondition -Assignment $_
                    $_.roleDefinitionName -eq $requiredRole -and
                    (Test-RepositoryCondition -Condition $condition -Repository $repository)
                }
            }
            else {
                $exactAssignments | Where-Object {
                    $_.roleDefinitionName -eq $requiredRole
                }
            }
        )
        if ($matching.Count -eq 0) {
            $missingIdentities += $identity.Label
            Write-Host "[ACTION] Identity: $($identity.Label)"
            Write-Host "[ACTION] Principal: $($identity.PrincipalId)"
            Write-Host "[ACTION] Role: $requiredRole"
            Write-Host "[ACTION] Scope: $ContainerRegistryResourceId"
            Write-Host "[ACTION] Repository: $repository"
        }
    }
    if ($missingIdentities.Count -gt 0) {
        throw "Missing exact-scope ACR pull authorization for: $($missingIdentities -join ', ')."
    }
}

if ($RequirePrivateDataPlane) {
    $addresses = @(
        [Net.Dns]::GetHostAddresses($ContainerRegistryEndpoint) |
            ForEach-Object { $_.IPAddressToString }
    )
    Assert-OnlyPrivateIPv4Addresses `
        -Addresses $addresses `
        -Hostname $ContainerRegistryEndpoint
    foreach ($dataEndpoint in @($registry.dataEndpointHostNames)) {
        $dataAddresses = @(
            [Net.Dns]::GetHostAddresses($dataEndpoint) |
                ForEach-Object { $_.IPAddressToString }
        )
        Assert-OnlyPrivateIPv4Addresses `
            -Addresses $dataAddresses `
            -Hostname $dataEndpoint
    }

    $accessToken = Get-AcrAccessToken `
        -RegistryName $registryName `
        -Endpoint $ContainerRegistryEndpoint `
        -Repository $repository `
        -SubscriptionId $registrySubscription
    $dockerManifestType = 'application/vnd.docker.distribution.manifest.v2+json'
    $dockerManifestListType = 'application/vnd.docker.distribution.manifest.list.v2+json'
    $dockerConfigType = 'application/vnd.docker.container.image.v1+json'
    $dockerLayerType = 'application/vnd.docker.image.rootfs.diff.tar.gzip'
    $accept = @($dockerManifestListType, $dockerManifestType) -join ', '
    $manifest = Get-AcrJson `
        -Uri "https://$ContainerRegistryEndpoint/v2/$repository/manifests/$digest" `
        -AccessToken $accessToken `
        -Accept $accept

    if ($manifest.mediaType -notin @($dockerManifestListType, $dockerManifestType)) {
        throw "Foundry Hosted Agent requires Docker distribution manifest schema 2; media type '$($manifest.mediaType)' is unsupported. OCI v1 manifests can surface only a generic ProvisioningError."
    }
    $isIndex = $manifest.mediaType -eq $dockerManifestListType
    if ($isIndex) {
        $linuxAmd64 = @($manifest.manifests | Where-Object {
            $_.platform.os -eq 'linux' -and $_.platform.architecture -eq 'amd64'
        })
        if ($linuxAmd64.Count -eq 0) {
            throw 'The image index does not contain a linux/amd64 manifest.'
        }
        $manifest = Get-AcrJson `
            -Uri "https://$ContainerRegistryEndpoint/v2/$repository/manifests/$($linuxAmd64[0].digest)" `
            -AccessToken $accessToken `
            -Accept $accept
    }
    if ($manifest.mediaType -ne $dockerManifestType) {
        throw "Selected linux/amd64 image uses unsupported media type '$($manifest.mediaType)' instead of Docker distribution manifest schema 2."
    }
    if (-not $manifest.config.digest -or $manifest.config.mediaType -ne $dockerConfigType) {
        throw "Image config must use Docker schema 2 media type '$dockerConfigType'."
    }
    $unsupportedLayers = @($manifest.layers | Where-Object {
        $_.mediaType -ne $dockerLayerType
    })
    if ($unsupportedLayers.Count -gt 0) {
        throw "Every image layer must use Docker schema 2 media type '$dockerLayerType'."
    }
    $config = Get-AcrJson `
        -Uri "https://$ContainerRegistryEndpoint/v2/$repository/blobs/$($manifest.config.digest)" `
        -AccessToken $accessToken
    if ($config.os -ne 'linux' -or $config.architecture -ne 'amd64') {
        throw "Image platform is '$($config.os)/$($config.architecture)', not linux/amd64."
    }
}

Write-Host "[OK] Existing private ACR validated: $ContainerRegistryEndpoint/$repository@$digest"

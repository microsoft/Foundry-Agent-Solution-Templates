param(
    [switch]$IncludePrivateDataPlane,
    [string]$AgentServiceName = '',
    [string]$AgentVersion = '',
    [string]$DeploymentMode = '',
    [string]$ReportDirectory = '',
    [string]$EnvironmentName = ''
)

. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/validation-report.ps1"

$values = Get-AzdValues -EnvironmentName $EnvironmentName
$resolvedEnvironmentName = Require-Value $values 'AZURE_ENV_NAME'
$resourceGroupName = Require-Value $values 'AZURE_RESOURCE_GROUP'
if ([string]::IsNullOrWhiteSpace($DeploymentMode)) {
    $DeploymentMode = Get-OptionalValue $values 'FPHA_DEPLOYMENT_MODE'
}
if ([string]::IsNullOrWhiteSpace($DeploymentMode)) {
    $DeploymentMode = if ([string]::IsNullOrWhiteSpace(
        (Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_RESOURCE_ID')
    )) {
        'Source'
    }
    else {
        'ExistingPrivateAcr'
    }
}
if ($IncludePrivateDataPlane) {
    $agentDefaults = switch ($DeploymentMode) {
        'Source' {
            [pscustomobject]@{
                Name = 'private-search-agent'
                NameKey = 'AGENT_PRIVATE_SEARCH_AGENT_NAME'
                VersionKey = 'AGENT_PRIVATE_SEARCH_AGENT_VERSION'
            }
        }
        'ExistingPrivateAcr' {
            [pscustomobject]@{
                Name = 'private-search-agent-acr'
                NameKey = 'AGENT_PRIVATE_SEARCH_AGENT_ACR_NAME'
                VersionKey = 'AGENT_PRIVATE_SEARCH_AGENT_ACR_VERSION'
            }
        }
        default {
            throw "Deployment mode '$DeploymentMode' cannot resolve the exact Hosted Agent."
        }
    }
    if ([string]::IsNullOrWhiteSpace($AgentServiceName)) {
        $AgentServiceName = Get-OptionalValue `
            $values `
            $agentDefaults.NameKey `
            $agentDefaults.Name
    }
    if ([string]::IsNullOrWhiteSpace($AgentVersion)) {
        $AgentVersion = Get-OptionalValue $values $agentDefaults.VersionKey
    }
    if ([string]::IsNullOrWhiteSpace($AgentServiceName) -or
        [string]::IsNullOrWhiteSpace($AgentVersion)) {
        throw 'Private data-plane validation requires an exact Hosted Agent name and version.'
    }
}
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $repositoryRoot = Split-Path $PSScriptRoot
    $ReportDirectory = Join-Path `
        $repositoryRoot `
        "artifacts/validation/$resolvedEnvironmentName"
}

function Invoke-ValidationCheck {
    param(
        [Parameter(Mandatory)][pscustomobject]$Check
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "[CHECK] $($Check.Name)"
    try {
        $scriptArguments = [hashtable]$Check.Arguments
        & $Check.ScriptPath @scriptArguments
        $stopwatch.Stop()
        return [pscustomobject]@{
            id = $Check.Id
            name = $Check.Name
            status = 'Passed'
            objective = $Check.Objective
            method = $Check.Method
            checklist = @($Check.Checklist)
            evidence = $Check.Evidence
            durationSeconds = $stopwatch.Elapsed.TotalSeconds
            failure = ''
        }
    }
    catch {
        $stopwatch.Stop()
        Write-Host "[FAILED] $($Check.Name): $($_.Exception.Message)"
        return [pscustomobject]@{
            id = $Check.Id
            name = $Check.Name
            status = 'Failed'
            objective = $Check.Objective
            method = $Check.Method
            checklist = @($Check.Checklist)
            evidence = $Check.Evidence
            durationSeconds = $stopwatch.Elapsed.TotalSeconds
            failure = $_.Exception.Message
        }
    }
}

$networkArguments = @{
    RequirePrivateResolution = [bool]$IncludePrivateDataPlane
    EnvironmentName = $resolvedEnvironmentName
}
$checks = @(
    [pscustomobject]@{
        Id = 'infrastructure'
        Name = 'Infrastructure baseline'
        ScriptPath = "$PSScriptRoot/validate-infrastructure.ps1"
        Arguments = @{
            EnvironmentName = $resolvedEnvironmentName
        }
        Objective = 'Confirm the template-owned Azure resource set is complete, successfully provisioned, and limited to the documented architecture.'
        Method = 'Read the resource-group inventory through Azure Resource Manager, filter by the active azd environment tag, evaluate provisioning state and required resource types, and reject disallowed services.'
        Checklist = @(
            'Resources tagged for the active azd environment were found.',
            'Every tagged resource that exposes provisioningState reports Succeeded.',
            'The VNet and Azure Firewall resources required by the network baseline exist.',
            'The Foundry account and Foundry project resources exist.',
            'Azure AI Search and Azure Key Vault resources exist.',
            'No template-owned ACR, Application Insights, or Log Analytics resource was introduced.'
        )
        Evidence = 'Expected template-owned resource types are ready and disallowed services are absent.'
    },
    [pscustomobject]@{
        Id = 'rbac'
        Name = 'Required exact-scope RBAC'
        ScriptPath = "$PSScriptRoot/validate-rbac.ps1"
        Arguments = @{
            EnvironmentName = $resolvedEnvironmentName
        }
        Objective = 'Confirm each template identity has the required role at the intended narrow resource scope without treating inherited or adopter-managed access as template evidence.'
        Method = 'Enumerate Azure role assignments for each expected principal and require the named role assignment at the exact Search, Key Vault, or key-resource scope.'
        Checklist = @(
            'The deployment principal has Search Service Contributor at the Search service scope.',
            'The deployment principal has Search Index Data Contributor at the Search service scope.',
            'The Foundry CMK identity has Key Vault Crypto User at the Foundry key scope.',
            'The Foundry account identity has Key Vault Crypto User at the vault scope for Hosted Agent creation.',
            'The Foundry project identity has Key Vault Crypto User at the vault scope for Hosted Agent creation.',
            'The Search identity has Key Vault Crypto Service Encryption User at the Search key scope.'
        )
        Evidence = 'Required exact-scope assignments are present, including the Foundry account and project vault roles required for Hosted Agent creation.'
    },
    [pscustomobject]@{
        Id = 'cmk'
        Name = 'Customer-managed keys'
        ScriptPath = "$PSScriptRoot/validate-cmk.ps1"
        Arguments = @{
            ValidateSearchIndexEncryption = [bool]$IncludePrivateDataPlane
            EnvironmentName = $resolvedEnvironmentName
        }
        Objective = 'Confirm Key Vault protections and the live customer-managed key bindings used by Foundry and the private Search index.'
        Method = if ($IncludePrivateDataPlane) {
            'Inspect Key Vault and key resources through ARM, inspect the Foundry encryption configuration, and retrieve the private Search index definition with Microsoft Entra authentication to compare its exact key URI, name, and version.'
        }
        else {
            'Inspect Key Vault and key resources through ARM and compare the Foundry encryption configuration with the expected key URI, name, and version.'
        }
        Checklist = @(
            'Key Vault purge protection is enabled.',
            'Key Vault uses Azure RBAC authorization.',
            'Foundry and Search reference distinct Key Vault key resource IDs.',
            'Both customer-managed keys exist and are enabled.',
            'Foundry references the expected Key Vault URI, key name, and key version.'
        ) + @(
            if ($IncludePrivateDataPlane) {
                'The private Search index references the expected Key Vault URI, key name, and key version.'
            }
        )
        Evidence = if ($IncludePrivateDataPlane) {
            'Key Vault protection is enabled; separate enabled keys exist; Foundry and the private Search index reference their expected key versions.'
        }
        else {
            'Key Vault protection is enabled; separate enabled keys exist and Foundry references its expected key version.'
        }
    },
    [pscustomobject]@{
        Id = 'network'
        Name = 'Private network and fail-closed egress'
        ScriptPath = "$PSScriptRoot/validate-network.ps1"
        Arguments = $networkArguments
        Objective = 'Confirm public fallback is disabled and Agent traffic is constrained to the approved private ingress and firewall-controlled egress paths.'
        Method = if ($IncludePrivateDataPlane) {
            'Inspect public-access settings, private endpoints, subnet NSGs, route tables, Firewall and Firewall Policy through ARM, then resolve configured data-plane hostnames from the connected private execution point.'
        }
        else {
            'Inspect public-access settings, private endpoints, subnet NSGs, route tables, Firewall, and Firewall Policy through Azure Resource Manager.'
        }
        Checklist = @(
            'Foundry, Azure AI Search, and Key Vault public network access is disabled.',
            'Exactly one approved private endpoint exists for each Foundry, Search, and Key Vault target.',
            'The private-endpoint subnet NSG permits only approved HTTPS ingress before denying other inbound traffic.',
            'The Agent subnet default route points to the deployed Azure Firewall and contains no unexpected route.',
            'Azure Firewall Policy uses the expected Standard tier and threat-intelligence baseline without inherited child or base policies.',
            'Firewall collections contain only the documented Entra and Hosted Agent runtime egress rules.',
            'Entra egress is restricted to TCP 443 and the AzureActiveDirectory service tag.',
            'Hosted Agent runtime egress is restricted to HTTPS 443 and the documented runtime FQDN set.'
        ) + @(
            if ($IncludePrivateDataPlane) {
                'Foundry, Search, Key Vault, and configured ACR hostnames resolve exclusively to RFC1918 IPv4 addresses.'
            }
        )
        Evidence = if ($IncludePrivateDataPlane) {
            'Public access is disabled; private endpoints, subnet controls, routes, Firewall policy, allowed egress, and RFC1918 DNS resolution match the template contract.'
        }
        else {
            'Public access is disabled; private endpoints, subnet controls, routes, Firewall policy, and allowed egress match the template contract.'
        }
    }
)

if (-not [string]::IsNullOrWhiteSpace(
    (Get-OptionalValue $values 'AZURE_CONTAINER_REGISTRY_RESOURCE_ID')
)) {
    $acrArguments = @{
        ValidateConnection = $true
        ValidatePullAuthorization = $true
        RequirePrivateDataPlane = [bool]$IncludePrivateDataPlane
        EnvironmentName = $resolvedEnvironmentName
    }
    $checks += [pscustomobject]@{
        Id = 'existing-private-acr'
        Name = 'Existing private ACR dependency'
        ScriptPath = "$PSScriptRoot/validate-existing-acr.ps1"
        Arguments = $acrArguments
        Objective = 'Confirm the adopter-owned ACR dependency satisfies the template connection, isolation, authorization, immutability, and image compatibility contract without changing that registry.'
        Method = 'Read ACR management settings and private endpoint state, inspect the Foundry project connection, evaluate exact-scope pull authorization for both identities, resolve private ACR endpoints, and inspect the configured digest manifest and image configuration through the Registry API.'
        Checklist = @(
            'The supplied ACR resource ID, login server, and image host are canonical and mutually consistent.',
            'The registry uses Premium SKU with public access, admin credentials, and anonymous pull disabled.',
            'ACR authentication-as-ARM is enabled and an approved registry private endpoint exists.',
            'The Foundry project connection targets the exact existing registry resource.',
            'The Foundry project and Hosted Agent identities have the required exact-scope pull authorization for the registry role mode.',
            'The configured image is pinned by a sha256 digest and exists in the selected repository.',
            'The image uses the template-supported Docker schema 2 manifest, config, and gzip layer media types.',
            'The image configuration targets Linux amd64.',
            'The ACR login and data endpoints resolve exclusively to private RFC1918 addresses.'
        )
        Evidence = 'The external registry security settings, Foundry connection, digest-pinned image, and pull authorization match the opt-in contract.'
    }
}
if ($IncludePrivateDataPlane) {
    $checks += [pscustomobject]@{
        Id = 'hosted-agent'
        Name = 'Hosted Agent private acceptance'
        ScriptPath = "$PSScriptRoot/validate-agent.ps1"
        Arguments = @{
            AgentServiceName = $AgentServiceName
            AgentVersion = $AgentVersion
            EnvironmentName = $resolvedEnvironmentName
        }
        Objective = 'Confirm the exact deployed Hosted Agent version is active and can complete a private, Search-grounded request with citation evidence.'
        Method = 'Read live Agent metadata through azd, compare the active version with the expected immutable version, then invoke that exact version in a new session and conversation.'
        Checklist = @(
            'The Hosted Agent reports active or deployed status.',
            'The active Agent version exactly matches the version recorded for this acceptance run.',
            'A new private Agent session and conversation completes successfully.',
            'The response demonstrates expected network/public-fallback grounding.',
            'The response contains an HTTPS citation.'
        )
        Evidence = 'The exact Hosted Agent deployment is active and returned the expected grounded answer with a citation.'
    }
}

$results = @()
$previousFailure = $false
foreach ($check in $checks) {
    if ($previousFailure) {
        $results += [pscustomobject]@{
            id = $check.Id
            name = $check.Name
            status = 'NotRun'
            objective = $check.Objective
            method = $check.Method
            checklist = @($check.Checklist)
            evidence = 'Not run because an earlier validation control failed.'
            durationSeconds = 0
            failure = ''
        }
        continue
    }
    $result = Invoke-ValidationCheck -Check $check
    $results += $result
    if ($result.status -eq 'Failed') {
        $previousFailure = $true
    }
}

$repositoryRoot = Split-Path $PSScriptRoot
$sourceRevision = ''
$sourceTreeState = 'unavailable'
if (Get-Command git -ErrorAction SilentlyContinue) {
    $revisionOutput = & git -C $repositoryRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $sourceRevision = [string]($revisionOutput | Select-Object -First 1)
        $statusOutput = @(
            & git -C $repositoryRoot status --porcelain --untracked-files=all 2>$null
        )
        if ($LASTEXITCODE -eq 0) {
            $sourceTreeState = if ($statusOutput.Count -eq 0) {
                'clean'
            }
            else {
                'dirty'
            }
        }
    }
}
$report = Write-SecurityValidationReport `
    -Results $results `
    -OutputDirectory $ReportDirectory `
    -EnvironmentName $resolvedEnvironmentName `
    -DeploymentMode $DeploymentMode `
    -ResourceGroupName $resourceGroupName `
    -AgentServiceName $AgentServiceName `
    -AgentVersion $AgentVersion `
    -SourceRevision $sourceRevision `
    -SourceTreeState $sourceTreeState `
    -IncludePrivateDataPlane $IncludePrivateDataPlane
Write-Host "[REPORT] Security validation report: $($report.LatestMarkdownPath)"
if ($report.OverallStatus -ne 'passed') {
    throw "Security validation failed. Review '$($report.LatestMarkdownPath)'."
}

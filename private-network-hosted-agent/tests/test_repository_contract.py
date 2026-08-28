import json
from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_only_three_connectivity_modes_are_documented() -> None:
    documentation = (ROOT / "docs/connectivity.md").read_text(encoding="utf-8")
    schema = json.loads(
        (ROOT / "infra-bicep/contract/parameters.schema.json").read_text(
            encoding="utf-8"
        )
    )
    modes = ["pointToSite", "siteToSite", "vnetPeering"]

    assert schema["properties"]["connectivityMode"]["enum"] == modes
    assert all(mode in documentation for mode in modes)


def test_connectivity_examples_use_deployment_script_contract() -> None:
    documentation = (ROOT / "docs/connectivity.md").read_text(encoding="utf-8")
    deploy = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")

    for example_name in (
        "pointToSite.parameters.example.json",
        "siteToSite.parameters.example.json",
        "vnetPeering.parameters.example.json",
    ):
        assert not (ROOT / "connectivity" / example_name).exists()

    for argument in (
        "-ConnectivityMode",
        "-P2sAddressPool",
        "-S2sGatewayIpAddress",
        "-S2sRemoteAddressPrefixes",
        "-S2sEnableBgp",
        "-S2sRemoteAsn",
        "-S2sBgpPeeringAddress",
        "-RemoteVnetResourceId",
    ):
        assert argument in documentation
        assert f"${argument.removeprefix('-')}" in deploy

    assert "remoteVnetAddressPrefixes" not in documentation
    assert "-AsSecureString" in documentation
    assert "Remove-Item Env:S2S_SHARED_KEY" in documentation


def test_terraform_is_scoped_and_dockerfile_is_not_shipped() -> None:
    forbidden = [
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and (
            path.name == "Dockerfile"
            or (
                path.suffix in {".tf", ".tfvars"}
                and ROOT / "infra-terraform" not in path.parents
            )
        )
    ]
    assert forbidden == []


def test_internal_azd_user_agent_tag_is_not_shipped() -> None:
    forbidden_name = "AZURE_DEV_" + "USER_AGENT"
    forbidden_value = "microsoft_" + "foundry_skill"
    source_suffixes = {
        ".bicep",
        ".json",
        ".md",
        ".ps1",
        ".py",
        ".yaml",
        ".yml",
    }
    shipped_files = [
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.suffix in source_suffixes
        and ".git" not in path.parts
    ]

    for path in shipped_files:
        content = path.read_text(encoding="utf-8")
        assert forbidden_name not in content, path
        assert forbidden_value not in content, path


def test_sample_search_data_is_non_sensitive_and_canonical() -> None:
    documents = json.loads(
        (ROOT / "demo-data/search-documents.json").read_text(encoding="utf-8")
    )
    assert len(documents) >= 3
    for document in documents:
        assert set(document) == {"id", "title", "content", "source_url"}
        assert document["source_url"].startswith("https://")


def test_agent_uses_remote_build_and_protocol_two() -> None:
    azure_yaml = (ROOT / "azure.yaml").read_text(encoding="utf-8")
    assert "name: private-network-hosted-agent\n" in azure_yaml
    assert "runtime: python_3_13" in azure_yaml
    assert "dependencyResolution: remote_build" in azure_yaml
    assert "version: 2.0.0" in azure_yaml
    assert "provider: terraform" in azure_yaml
    assert "path: ./infra-terraform" in azure_yaml

    bicep_yaml = (ROOT / "scenarios/bicep/azure.yaml").read_text(
        encoding="utf-8"
    )
    assert "name: private-network-hosted-agent-bicep\n" in bicep_yaml
    assert "provider: bicep" in bicep_yaml
    assert "path: ../../infra-bicep" in bicep_yaml


def test_agent_declares_httpx_runtime_dependency() -> None:
    requirements = (
        ROOT / "agent/search-agent/requirements.txt"
    ).read_text(encoding="utf-8").splitlines()

    assert "httpx==0.28.1" in requirements


def test_existing_private_acr_scenario_uses_prebuilt_digest_image() -> None:
    scenario = (
        ROOT / "scenarios/existing-private-acr/azure.yaml"
    ).read_text(encoding="utf-8")

    assert "name: private-network-hosted-agent-existing-private-acr\n" in scenario
    assert "image: ${AZURE_CONTAINER_IMAGE}" in scenario
    assert "name: private-search-agent-acr" in scenario
    assert "version: 2.0.0" in scenario
    assert "provider: terraform" in scenario
    assert "path: ../../infra-terraform" in scenario
    assert "docker:" in scenario
    assert "remoteBuild: true" in scenario
    for forbidden in (
        "codeConfiguration:",
        "dependencyResolution:",
        "runtime:",
        "path: Dockerfile",
        "context:",
        "FOUNDRY_LOCAL_DEVELOPMENT",
        "\n        project:",
    ):
        assert forbidden not in scenario

    bicep_scenario = (
        ROOT / "scenarios/bicep-existing-private-acr/azure.yaml"
    ).read_text(encoding="utf-8")
    assert (
        "name: private-network-hosted-agent-bicep-existing-private-acr\n"
        in bicep_scenario
    )
    assert "provider: bicep" in bicep_scenario
    assert "path: ../../infra-bicep" in bicep_scenario


def test_p2s_profile_scopes_private_dns() -> None:
    export_script = (ROOT / "scripts/export-p2s-profile.ps1").read_text(
        encoding="utf-8"
    )
    deploy_script = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")
    for value in (
        "FOUNDRY_PROJECT_ENDPOINT",
        "AZURE_SEARCH_ENDPOINT",
        "AZURE_KEY_VAULT_URI",
    ):
        assert value in export_script
    assert "azurevpnconfig-resource-dns.xml" in export_script
    assert "Remove-Item -LiteralPath $rawProfiles.FullName -Force" in export_script
    assert "$infrastructureReady -and" in deploy_script
    assert "Test-Path -LiteralPath $profilePath -PathType Leaf" in deploy_script
    assert "Reusing the existing VPN profile" in deploy_script
    assert "do not re-import it" in deploy_script


def test_existing_private_acr_vpn_handoff_is_explicit() -> None:
    deploy_script = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")
    documentation = (ROOT / "docs/existing-private-acr.md").read_text(
        encoding="utf-8"
    )

    for value in (
        "Azure Public Cloud ACR Private DNS zone",
        "selected registry's Private Endpoint",
        "Use this Foundry VPN profile for validation",
        "separate network and IAM handoffs",
        "registry-authentication ImageError is expected",
        "Existing private ACR IAM handoff required:",
        "Test-ExpectedAcrBootstrapAuthorizationFailure",
        "Test-MissingAcrPullAuthorizationFailure",
        "docs/existing-private-acr.md",
        "Complete the external private network handoff",
        "Create the Agent identity and complete the external RBAC handoff",
        "Foundry project principal:",
        "Hosted Agent principal:",
        "Registry scope:",
        "does not modify enterprise ACR IAM",
    ):
        assert value in deploy_script

    for value in (
        "Complete the external private network handoff",
        "AZURE_VNET_ID",
        "standard zone name is `privatelink.azurecr.io`",
        "dataEndpointHostNames",
        "does not validate the Foundry deployment path",
        "Identify the exact resources",
        "Verify the ACR Private Endpoint and DNS zone group",
        "Link ACR Private DNS to the Foundry solution VNet",
        "Establish approved routing to the ACR Private Endpoint",
        "An ACR VNet can use only one remote VNet gateway",
        "TcpTestSucceeded: True",
        "Start here: preferred unified workflow",
        "Grant both identities access in Azure Portal",
        "Grant both identities access with Azure CLI",
        "--assignee-principal-type ServicePrincipal",
        "Verify propagation before continuing",
        "At the network pause",
        "Both exact-scope pull assignments have propagated",
    ):
        assert value in documentation


def test_preflight_validates_search_region() -> None:
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")
    providers = (
        ROOT / "scripts/deployment/providers.ps1"
    ).read_text(encoding="utf-8")
    assert "'Microsoft.Search'" in providers
    assert "searchServices" in providers
    assert "$providerValidation.searchLocations" in preflight


def test_validate_all_loads_shared_helpers() -> None:
    validation = (ROOT / "scripts/validate-all.ps1").read_text(encoding="utf-8")
    assert '. "$PSScriptRoot/common.ps1"' in validation
    assert '. "$PSScriptRoot/validation-report.ps1"' in validation
    assert "Get-AzdValues" in validation


def test_deployment_publishes_security_validation_report_paths() -> None:
    deploy = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")
    validation = (ROOT / "scripts/validate-all.ps1").read_text(encoding="utf-8")

    assert "'-ReportDirectory', $securityValidationReportDirectory" in deploy
    assert "securityValidationReport = $securityValidationReportPath" in deploy
    assert "securityValidationEvidence" not in deploy
    assert "latest.json" not in deploy
    assert "Write-SecurityValidationReport" in validation
    assert "status = 'NotRun'" in validation
    assert "$scriptArguments = [hashtable]$Check.Arguments" in validation
    assert "RequirePrivateResolution = [bool]$IncludePrivateDataPlane" in validation
    assert "Private data-plane validation requires an exact Hosted Agent" in validation


def test_deployment_runs_one_agent_acceptance_invocation() -> None:
    deploy = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / "scripts/deployment/workflow.ps1").read_text(
        encoding="utf-8"
    )
    validation = (ROOT / "scripts/validate-all.ps1").read_text(encoding="utf-8")
    agent_validation = (ROOT / "scripts/validate-agent.ps1").read_text(
        encoding="utf-8"
    )

    assert "Invoke-AgentAcceptance" not in deploy
    assert "Invoke-AgentAcceptance" not in workflow
    assert validation.count("validate-agent.ps1") == 1
    assert "network|public|fallback" in agent_validation
    assert "https://" in agent_validation
    assert "$activeVersion -ne $AgentVersion" in agent_validation
    assert "FOUNDRY_PROJECT_ENDPOINT" in deploy
    assert "/endpoint/protocols/openai/responses?api-version=v1" in deploy
    assert "azd ai agent invoke --agent-endpoint" in deploy
    assert "azd ai agent invoke -C" not in deploy
    assert "--version '$expectedVersion'" in deploy
    assert "agentEndpoint = $agentEndpoint" in deploy
    assert "invokeCommand = $invokeCommand" in deploy


def test_cmk_validation_requires_distinct_keys() -> None:
    validation = (ROOT / "scripts/validate-cmk.ps1").read_text(encoding="utf-8")
    assert "$foundryKeyId.TrimEnd('/').Equals(" in validation
    assert "Foundry and Search must use separate customer-managed keys." in validation
    assert "if ($ValidateSearchIndexEncryption)" in validation
    assert "https://search.azure.com" in validation
    assert "index.encryptionKey.keyVaultKeyName" in validation
    assert "index.encryptionKey.keyVaultKeyVersion" in validation


def test_network_validation_handles_non_address_dns_records() -> None:
    validation = (ROOT / "scripts/validate-network.ps1").read_text(
        encoding="utf-8"
    )
    assert "PSObject.Properties['IPAddress']" in validation
    assert "Where-Object { $_.IPAddress }" not in validation


def test_firewall_deployment_uses_staged_modules() -> None:
    network = (ROOT / "infra-bicep/modules/network.bicep").read_text(encoding="utf-8")
    firewall_base = (ROOT / "infra-bicep/modules/firewall-base.bicep").read_text(
        encoding="utf-8"
    )
    firewall_create = (ROOT / "infra-bicep/modules/firewall-create.bicep").read_text(
        encoding="utf-8"
    )
    attachment = (
        ROOT / "infra-bicep/modules/firewall-policy-attachment.bicep"
    ).read_text(encoding="utf-8")

    assert "module firewallBase './firewall-base.bicep'" in network
    assert "module firewallCreation './firewall-create.bicep'" in network
    assert "module vnetConfiguration './vnet-configuration.bicep'" in network
    assert (
        "module firewallPolicyAttachment './firewall-policy-attachment.bicep'"
        in network
    )
    vnet_stage = network.split(
        "module vnetConfiguration './vnet-configuration.bicep'", maxsplit=1
    )[1].split(
        "module firewallPolicyAttachment", maxsplit=1
    )[0]
    rules_stage = network.split(
        "resource firewallRules", maxsplit=1
    )[1].split(
        "resource routeTable", maxsplit=1
    )[0]
    attachment_stage = network.split(
        "module firewallPolicyAttachment", maxsplit=1
    )[1].split(
        "resource defaultRoute", maxsplit=1
    )[0]
    assert "dependsOn: [\n    firewallBase\n    firewallCreation\n  ]" in vnet_stage
    assert "dependsOn: [\n    firewallBase\n  ]" in rules_stage
    assert "firewallCreation" not in rules_stage
    assert (
        "dependsOn: [\n    firewallCreation\n    firewallRules\n  ]"
        in attachment_stage
    )
    assert "if (firewallCreationRequired)" in network
    assert "Microsoft.Network/azureFirewalls" not in firewall_base
    assert "@onlyIfNotExists()" not in firewall_create
    assert "firewallPolicy:" not in firewall_base
    assert "firewallPolicy:" in attachment


def test_private_dns_control_plane_and_resolver_can_deploy_in_parallel() -> None:
    solution = (ROOT / "infra-bicep/solution.bicep").read_text(encoding="utf-8")
    zones = (ROOT / "infra-bicep/modules/private-dns.bicep").read_text(encoding="utf-8")
    network = (
        ROOT / "infra-bicep/modules/private-dns-network.bicep"
    ).read_text(encoding="utf-8")

    assert "module privateDns './modules/private-dns.bicep'" in solution
    assert (
        "module privateDnsNetwork './modules/private-dns-network.bicep'"
        in solution
    )
    assert "Microsoft.Network/privateDnsZones@" in zones
    assert "Microsoft.Network/dnsResolvers@" not in zones
    assert "Microsoft.Network/privateDnsZones@" in network
    assert "existing = [for zoneName in zoneNames" in network
    assert "Microsoft.Network/dnsResolvers@" in network
    assert "Microsoft.Network/dnsResolvers/inboundEndpoints@" in network
    assert "privateDns.outputs.foundryZoneIds" in solution
    assert "privateDns.outputs.searchZoneId" in solution
    assert "privateDns.outputs.keyVaultZoneId" in solution
    assert "privateDnsNetwork.outputs.inboundIpAddress" in solution


def test_agent_search_role_uses_instance_identity_safely() -> None:
    assignment = (
        ROOT / "scripts/assign-agent-search-role.ps1"
    ).read_text(encoding="utf-8")
    assert "@('instance_identity', 'principal_id')" in assignment
    assert "PSObject.Properties[$name]" in assignment
    assert "$agent.identity." not in assignment


def test_search_seed_uses_supported_field_options() -> None:
    seed = (ROOT / "scripts/seed_search.py").read_text(encoding="utf-8")
    assert "retrievable=" not in seed
    assert 'name="title"' in seed
    assert 'name="content"' in seed
    assert 'name="source_url"' in seed


def test_existing_acr_validation_is_fail_closed() -> None:
    validation = (
        ROOT / "scripts/validate-existing-acr.ps1"
    ).read_text(encoding="utf-8")

    for required in (
        "Premium",
        "publicNetworkAccess",
        "adminUserEnabled",
        "anonymousPullEnabled",
        "authentication-as-arm show",
        "private-endpoint-connection list",
        "2026-06-25T00:00:00Z",
        "Container Registry Repository Reader",
        "abacrepositorypermissions",
        "legacyregistrypermissions",
        "AZD_AGENT_SKIP_ROLE_ASSIGNMENTS",
        "AcrPull",
        "GetHostAddresses",
        "linux",
        "amd64",
        "application/vnd.docker.distribution.manifest.v2+json",
        "application/vnd.docker.container.image.v1+json",
        "application/vnd.docker.image.rootfs.diff.tar.gzip",
        "OCI v1 manifests",
        "ContainerRegistry",
        "ManagedIdentity",
        "AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID",
        "AZURE_AI_AGENT_PRINCIPAL_ID",
    ):
        assert required in validation
    assert "application/vnd.oci.image.manifest.v1+json" not in validation
    assert "application/vnd.oci.image.index.v1+json" not in validation
    assert "@Request" in validation
    assert "StringEqualsIgnoreCase" in validation
    assert "StringStartsWithIgnoreCase" in validation
    assert "StringNotEqualsIgnoreCase" not in validation
    assert "role assignment create" not in validation
    assert "private-endpoint create" not in validation
    assert "$matching = @(" in validation
    private_endpoint_lookup = validation.split(
        "$privateEndpoint = az network private-endpoint show", maxsplit=1
    )[1].split("if ($LASTEXITCODE", maxsplit=1)[0]
    assert "--subscription $privateEndpointSubscription" in private_endpoint_lookup
    assert "--subscription $registrySubscription" not in private_endpoint_lookup
    assert 'Authorization = "Bearer $AccessToken"' in validation


def test_existing_acr_documentation_has_official_requirements() -> None:
    documentation = (
        ROOT / "docs/existing-private-acr.md"
    ).read_text(encoding="utf-8")

    assert "after June 25, 2026" in documentation
    assert "container-registry-image-tag-version" in documentation
    assert "deploy-hosted-agent-private-azure-container-registry" in documentation
    assert "container-registry-private-endpoints" in documentation
    assert "Container Registry Repository Reader" in documentation
    assert "1.0.0-beta.7" in documentation
    assert "AZD_AGENT_SKIP_ACR" in documentation
    assert "AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID" in documentation
    assert "AZURE_AI_AGENT_PRINCIPAL_ID" in documentation
    assert "per-agent identity" in documentation
    assert "azd deploy private-search-agent-acr --no-prompt" in documentation
    assert "@sha256:" in documentation
    assert "Docker distribution manifest schema 2" in documentation
    assert "does not create or configure the ACR" in documentation


def test_acr_troubleshooting_is_customer_safe() -> None:
    troubleshooting = (
        ROOT / "docs/troubleshooting-existing-private-acr.md"
    ).read_text(encoding="utf-8")
    existing_acr = (ROOT / "docs/existing-private-acr.md").read_text(
        encoding="utf-8"
    )
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    for required in (
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
        "agent_version_failed",
        "exact version",
        "oci-mediatypes=false",
        "AZURE_AI_AGENT_PRINCIPAL_ID",
        "Container Registry Repository Reader",
        "public network access",
    ):
        assert required.lower() in troubleshooting.lower()

    assert "troubleshooting-existing-private-acr.md" in existing_acr
    assert "troubleshooting-existing-private-acr.md" in readme


def test_customer_delivery_documentation_is_complete() -> None:
    required_documents = (
        "docs/solution-overview.md",
        "docs/architecture.md",
        "docs/security.md",
        "docs/configuration.md",
        "docs/customization.md",
        "docs/production-readiness.md",
        "docs/troubleshooting.md",
        "docs/cost.md",
        "docs/operations.md",
        "docs/release-and-upgrade.md",
        "docs/validation.md",
        "SUPPORT.md",
    )
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    support = (ROOT / "SUPPORT.md").read_text(encoding="utf-8")
    security_policy_url = (
        "https://github.com/microsoft/Foundry-Agent-Solution-Templates/"
        "security/policy"
    )

    for relative_path in required_documents:
        assert (ROOT / relative_path).is_file(), relative_path
        assert relative_path in readme, relative_path
    assert security_policy_url in readme
    assert security_policy_url in support


def test_historical_internal_evidence_is_not_retained_or_linked() -> None:
    public_documents = [
        ROOT / "README.md",
        ROOT / "SUPPORT.md",
        *sorted((ROOT / "docs").glob("*.md")),
    ]

    assert not (ROOT / "docs/internal").exists()
    assert not list(ROOT.rglob("DEVELOPMENT-ONLY*"))
    assert not (ROOT / "docs/validation-evidence.md").exists()
    assert not (ROOT / ".azure/deployment-plan.md").exists()

    for path in public_documents:
        content = path.read_text(encoding="utf-8").lower()
        assert "docs/internal" not in content, path
        assert "validation-evidence" not in content, path

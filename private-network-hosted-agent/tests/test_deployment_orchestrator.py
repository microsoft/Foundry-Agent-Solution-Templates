import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[1]
DEPLOY = ROOT / "scripts" / "deploy.ps1"
SUBSCRIPTION = "11111111-1111-1111-1111-111111111111"
ACR_ID = (
    f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-enterprise/"
    "providers/Microsoft.ContainerRegistry/registries/enterpriseacr"
)
ACR_ENDPOINT = "enterpriseacr.azurecr.io"
ACR_IMAGE = f"{ACR_ENDPOINT}/private-search-agent@sha256:" + ("a" * 64)


def run_deploy_contract(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(DEPLOY),
            *arguments,
            "-NoPrompt",
            "-ValidateInputsOnly",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    ("exit_code", "output", "expected"),
    [
        (
            1,
            "[ImageError] Container registry authentication failed. "
            "Verify the workspace managed identity has AcrPull permissions "
            "on the target registry.",
            True,
        ),
        (1, "[ImageError] Unsupported image manifest.", False),
        (1, "Network timeout while creating agent.", False),
        (0, "", False),
    ],
)
def test_expected_acr_bootstrap_failure_is_narrowly_classified(
    exit_code: int, output: str, expected: bool
) -> None:
    escaped_output = output.replace("'", "''")
    result = invoke_workflow_contract(
        "$result = Test-ExpectedAcrBootstrapAuthorizationFailure "
        f"-ExitCode {exit_code} -Output @('{escaped_output}'); "
        "Write-Output $result"
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip().lower() == str(expected).lower()


@pytest.mark.parametrize(
    ("exit_code", "output", "expected"),
    [
        (
            1,
            "Missing exact-scope ACR pull authorization for: "
            "Foundry project, Hosted Agent.",
            True,
        ),
        (1, "ACR private data endpoint resolved publicly.", False),
        (0, "", False),
    ],
)
def test_missing_acr_pull_authorization_is_narrowly_classified(
    exit_code: int, output: str, expected: bool
) -> None:
    escaped_output = output.replace("'", "''")
    result = invoke_workflow_contract(
        "$result = Test-MissingAcrPullAuthorizationFailure "
        f"-ExitCode {exit_code} -Output @('{escaped_output}'); "
        "Write-Output $result"
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip().lower() == str(expected).lower()


def test_source_minimal_contract_generates_dedicated_group() -> None:
    result = run_deploy_contract(
        "-DeploymentMode",
        "Source",
        "-SubscriptionId",
        SUBSCRIPTION,
    )
    assert result.returncode == 0, result.stderr
    contract = json.loads(result.stdout)
    assert contract["deploymentMode"] == "Source"
    assert contract["environmentName"].startswith("fpha-src-")
    assert contract["resourceGroupName"] == f"rg-{contract['environmentName']}"


def test_acr_contract_accepts_complete_digest_coordinates() -> None:
    result = run_deploy_contract(
        "-DeploymentMode",
        "ExistingPrivateAcr",
        "-SubscriptionId",
        SUBSCRIPTION,
        "-ContainerRegistryResourceId",
        ACR_ID,
        "-ContainerRegistryEndpoint",
        ACR_ENDPOINT,
        "-ContainerImage",
        ACR_IMAGE,
    )
    assert result.returncode == 0, result.stderr
    contract = json.loads(result.stdout)
    assert contract["deploymentMode"] == "ExistingPrivateAcr"
    assert contract["projectDirectory"].endswith("existing-private-acr")


def test_acr_contract_rejects_child_resource_id() -> None:
    result = run_deploy_contract(
        "-DeploymentMode",
        "ExistingPrivateAcr",
        "-SubscriptionId",
        SUBSCRIPTION,
        "-ContainerRegistryResourceId",
        f"{ACR_ID}/repositories/private-search-agent",
        "-ContainerRegistryEndpoint",
        ACR_ENDPOINT,
        "-ContainerImage",
        ACR_IMAGE,
    )
    assert result.returncode != 0


def test_acr_contract_accepts_dnl_hash_login_server() -> None:
    dnl_endpoint = "enterpriseacr-abc123.azurecr.io"
    result = run_deploy_contract(
        "-DeploymentMode",
        "ExistingPrivateAcr",
        "-SubscriptionId",
        SUBSCRIPTION,
        "-ContainerRegistryResourceId",
        ACR_ID,
        "-ContainerRegistryEndpoint",
        dnl_endpoint,
        "-ContainerImage",
        f"{dnl_endpoint}/private-search-agent@sha256:" + ("a" * 64),
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize(
    "arguments",
    [
        (
            "-DeploymentMode",
            "ExistingPrivateAcr",
            "-SubscriptionId",
            SUBSCRIPTION,
            "-ContainerRegistryResourceId",
            ACR_ID,
        ),
        (
            "-DeploymentMode",
            "ExistingPrivateAcr",
            "-SubscriptionId",
            SUBSCRIPTION,
            "-ContainerRegistryResourceId",
            ACR_ID,
            "-ContainerRegistryEndpoint",
            ACR_ENDPOINT,
            "-ContainerImage",
            f"{ACR_ENDPOINT}/private-search-agent:latest",
        ),
        (
            "-DeploymentMode",
            "Source",
            "-SubscriptionId",
            SUBSCRIPTION,
            "-ContainerRegistryResourceId",
            ACR_ID,
        ),
        (
            "-DeploymentMode",
            "Source",
            "-SubscriptionId",
            SUBSCRIPTION,
            "-ApproveExistingResourceGroup",
        ),
    ],
)
def test_invalid_or_ambiguous_contracts_fail(arguments: tuple[str, ...]) -> None:
    result = run_deploy_contract(*arguments)
    assert result.returncode != 0


def test_no_prompt_requires_explicit_mode() -> None:
    result = run_deploy_contract("-SubscriptionId", SUBSCRIPTION)
    assert result.returncode != 0
    assert "DeploymentMode is required" in result.stderr


def test_vnet_peering_accepts_canonical_remote_vnet_id() -> None:
    result = run_deploy_contract(
        "-DeploymentMode",
        "Source",
        "-SubscriptionId",
        SUBSCRIPTION,
        "-ConnectivityMode",
        "vnetPeering",
        "-RemoteVnetResourceId",
        (
            f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-network/"
            "providers/Microsoft.Network/virtualNetworks/remote-vnet"
        ),
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize(
    "remote_vnet_resource_id",
    [
        "",
        "remote-vnet",
        (
            f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-network/"
            "providers/Microsoft.Network/virtualNetworks/remote-vnet/"
            "subnets/default"
        ),
    ],
)
def test_vnet_peering_rejects_noncanonical_remote_vnet_id(
    remote_vnet_resource_id: str,
) -> None:
    result = run_deploy_contract(
        "-DeploymentMode",
        "Source",
        "-SubscriptionId",
        SUBSCRIPTION,
        "-ConnectivityMode",
        "vnetPeering",
        "-RemoteVnetResourceId",
        remote_vnet_resource_id,
    )
    assert result.returncode != 0


@pytest.mark.parametrize(
    "s2s_arguments",
    [
        (),
        ("-S2sGatewayIpAddress", "203.0.113.10"),
        (
            "-S2sGatewayIpAddress",
            "203.0.113.10",
            "-S2sRemoteAddressPrefixes",
            "10.60.0.0/16",
            "-S2sEnableBgp",
        ),
    ],
)
def test_s2s_requires_complete_network_coordinates(
    s2s_arguments: tuple[str, ...],
) -> None:
    environment = dict(os.environ, S2S_SHARED_KEY=secrets.token_urlsafe(32))
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(DEPLOY),
            "-DeploymentMode",
            "Source",
            "-SubscriptionId",
            SUBSCRIPTION,
            "-ConnectivityMode",
            "siteToSite",
            *s2s_arguments,
            "-NoPrompt",
            "-ValidateInputsOnly",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    assert result.returncode != 0


def test_private_dns_contract_rejects_mixed_results() -> None:
    escaped_root = str(ROOT).replace("'", "''")
    command = (
        f". '{escaped_root}\\scripts\\common.ps1'; "
        "Assert-OnlyPrivateIPv4Addresses "
        "-Addresses @('10.42.1.4', '8.8.8.8') -Hostname 'mixed.example'"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert "exclusively" in result.stderr


def invoke_preview_contract(
    preview: str, mode: str = "Source"
) -> subprocess.CompletedProcess[str]:
    escaped_root = str(ROOT).replace("'", "''")
    escaped_preview = preview.replace("'", "''")
    command = (
        f". '{escaped_root}\\scripts\\deployment\\commands.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\workflow.ps1'; "
        f"Assert-SafeProvisionPreview -PreviewOutput @('{escaped_preview}') "
        f"-DeploymentMode '{mode}'"
    )
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def invoke_workflow_contract(command: str) -> subprocess.CompletedProcess[str]:
    escaped_root = str(ROOT).replace("'", "''")
    script = (
        f". '{escaped_root}\\scripts\\deployment\\contract.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\commands.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\diagnostics.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\providers.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\workflow.ps1'; "
        f"{command}"
    )
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", script],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


def invoke_model_quota_contract(command: str) -> subprocess.CompletedProcess[str]:
    escaped_root = str(ROOT).replace("'", "''")
    script = (
        f". '{escaped_root}\\scripts\\deployment\\commands.ps1'; "
        f". '{escaped_root}\\scripts\\deployment\\model-quota.ps1'; "
        f"{command}"
    )
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", script],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


def test_existing_environment_binding_cannot_change_resource_group() -> None:
    result = invoke_workflow_contract(
        "function Get-AzdEnvironmentNames { return @('existing') }; "
        "function Get-AzdEnvironmentValues { "
        "return @{ FPHA_DEPLOYMENT_MODE = 'Source'; "
        f"AZURE_SUBSCRIPTION_ID = '{SUBSCRIPTION}'; "
        "AZURE_RESOURCE_GROUP = 'rg-original' } }; "
        "Assert-AzdEnvironmentBinding -ProjectDirectory '.' "
        "-EnvironmentName 'existing' -DeploymentMode 'Source' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-new'"
    )
    assert result.returncode != 0
    assert "already bound" in result.stderr


def test_existing_environment_binding_accepts_exact_contract() -> None:
    result = invoke_workflow_contract(
        "function Get-AzdEnvironmentNames { return @('existing') }; "
        "function Get-AzdEnvironmentValues { "
        "return @{ FPHA_DEPLOYMENT_MODE = 'Source'; "
        f"AZURE_SUBSCRIPTION_ID = '{SUBSCRIPTION}'; "
        "AZURE_RESOURCE_GROUP = 'rg-existing' } }; "
        "Assert-AzdEnvironmentBinding -ProjectDirectory '.' "
        "-EnvironmentName 'existing' -DeploymentMode 'Source' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-existing'"
    )
    assert result.returncode == 0, result.stderr


def test_existing_environment_binding_fails_when_values_are_unreadable() -> None:
    result = invoke_workflow_contract(
        "function Get-AzdEnvironmentNames { return @('existing') }; "
        "function Get-AzdEnvironmentValues { throw 'unreadable' }; "
        "Assert-AzdEnvironmentBinding -ProjectDirectory '.' "
        "-EnvironmentName 'existing' -DeploymentMode 'Source' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-existing'"
    )
    assert result.returncode != 0
    assert "unreadable" in result.stderr


@pytest.mark.parametrize(
    ("mode", "environment_name"),
    [
        ("Source", "fpha-src-existing"),
        ("ExistingPrivateAcr", "fpha-acr-existing"),
    ],
)
def test_reusable_environment_context_reads_values_once(
    tmp_path: Path, mode: str, environment_name: str
) -> None:
    azure_directory = tmp_path / ".azure"
    azure_directory.mkdir()
    (azure_directory / "config.json").write_text(
        json.dumps({"defaultEnvironment": environment_name}),
        encoding="utf-8",
    )
    project_directory = str(tmp_path).replace("'", "''")
    resource_group = f"rg-{environment_name}"
    result = invoke_workflow_contract(
        "$script:listCount = 0; $script:readCount = 0; "
        f"function Get-AzdEnvironmentNames {{ $script:listCount++; "
        f"return @('{environment_name}') }}; "
        "function Get-AzdEnvironmentValues { $script:readCount++; "
        "return @{ "
        f"FPHA_DEPLOYMENT_MODE = '{mode}'; "
        f"AZURE_SUBSCRIPTION_ID = '{SUBSCRIPTION}'; "
        f"AZURE_RESOURCE_GROUP = '{resource_group}'; "
        "AZURE_RESOURCE_GROUP_OWNERSHIP = 'templateCreated'; "
        "FPHA_INFRASTRUCTURE_FINGERPRINT = 'preserved' } }; "
        f"$context = Resolve-AzdEnvironmentContext "
        f"-ProjectDirectory '{project_directory}' -EnvironmentName '' "
        f"-DeploymentMode '{mode}' -SubscriptionId '{SUBSCRIPTION}'; "
        "[pscustomobject]@{ listCount = $script:listCount; "
        "readCount = $script:readCount; name = $context.Name; "
        "resourceGroup = $context.ResourceGroupName; "
        "fingerprint = $context.Values['FPHA_INFRASTRUCTURE_FINGERPRINT']; "
        "bindingValidated = $context.BindingValidated "
        "} | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    context = json.loads(result.stdout)
    assert context == {
        "listCount": 1,
        "readCount": 1,
        "name": environment_name,
        "resourceGroup": resource_group,
        "fingerprint": "preserved",
        "bindingValidated": True,
    }


def test_new_environment_context_does_not_read_values() -> None:
    result = invoke_workflow_contract(
        "$script:listCount = 0; $script:readCount = 0; "
        "function Get-AzdEnvironmentNames { $script:listCount++; return @() }; "
        "function Get-AzdEnvironmentValues { "
        "$script:readCount++; throw 'New environment must not be read.' }; "
        "$context = Resolve-AzdEnvironmentContext -ProjectDirectory '.' "
        "-EnvironmentName 'fpha-src-new' -DeploymentMode 'Source' "
        f"-SubscriptionId '{SUBSCRIPTION}'; "
        "[pscustomobject]@{ listCount = $script:listCount; "
        "readCount = $script:readCount; "
        "resourceGroup = $context.ResourceGroupName; "
        "bindingValidated = $context.BindingValidated "
        "} | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    context = json.loads(result.stdout)
    assert context == {
        "listCount": 1,
        "readCount": 0,
        "resourceGroup": "rg-fpha-src-new",
        "bindingValidated": False,
    }


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("FPHA_DEPLOYMENT_MODE", "ExistingPrivateAcr"),
        ("AZURE_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000"),
        ("AZURE_RESOURCE_GROUP", "rg-other"),
    ],
)
def test_cached_environment_values_remain_fail_closed(
    key: str, value: str
) -> None:
    result = invoke_workflow_contract(
        "function Get-AzdEnvironmentValues { "
        "throw 'Cached values should prevent a second read.' }; "
        "$values = @{ FPHA_DEPLOYMENT_MODE = 'Source'; "
        f"AZURE_SUBSCRIPTION_ID = '{SUBSCRIPTION}'; "
        "AZURE_RESOURCE_GROUP = 'rg-existing' }; "
        f"$values['{key}'] = '{value}'; "
        "Assert-AzdEnvironmentBinding -ProjectDirectory '.' "
        "-EnvironmentName 'existing' -DeploymentMode 'Source' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-existing' "
        "-EnvironmentNames @('existing') -CurrentValues $values"
    )
    assert result.returncode != 0
    assert "already bound" in result.stderr
    assert "second read" not in result.stderr


def test_template_created_group_rejects_mismatched_environment_tag() -> None:
    result = invoke_workflow_contract(
        "function Invoke-CheckedCommand { "
        "return [pscustomobject]@{ Output = @('{"
        '\"tags\":{\"resource-group-ownership\":\"template-created\",'
        '\"solution-template\":\"foundry-private-hosted-agent\",'
        '\"azd-env-name\":\"different-environment\"}}'
        "') } }; "
        "Assert-TemplateResourceGroupOwnership "
        f"-SubscriptionId '{SUBSCRIPTION}' "
        "-ResourceGroupName 'rg-fpha-src-existing' "
        "-EnvironmentName 'fpha-src-existing'"
    )
    assert result.returncode != 0
    assert "without matching template ownership metadata" in result.stderr


@pytest.mark.parametrize(
    (
        "available_capacity",
        "reusable_capacity",
        "expected_additional",
        "succeeds",
    ),
    [
        (10, 0, 10, True),
        (9, 0, 10, False),
        (0, 10, 0, True),
        (6, 4, 6, True),
        (5, 4, 6, False),
        (0, 12, 0, True),
    ],
)
def test_model_quota_requires_only_additional_capacity(
    available_capacity: int,
    reusable_capacity: int,
    expected_additional: int,
    succeeds: bool,
) -> None:
    result = invoke_model_quota_contract(
        "$usage = [pscustomobject]@{ "
        f"limit = 100; currentValue = {100 - available_capacity} "
        "}; "
        "try { "
        "$quota = Assert-RegionalModelQuota -Usage $usage "
        "-DesiredCapacity 10 "
        f"-ReusableExistingCapacity {reusable_capacity} "
        "-ModelName 'gpt-5.1' -Location 'eastus2'; "
        "[pscustomobject]@{ succeeded = $true; "
        "additional = $quota.RequiredAdditionalCapacity "
        "} | ConvertTo-Json -Compress "
        "} catch { "
        f"[pscustomobject]@{{ succeeded = $false; additional = {expected_additional}; "
        "message = $_.Exception.Message } | ConvertTo-Json -Compress "
        "}"
    )
    assert result.returncode == 0, result.stderr
    quota = json.loads(result.stdout)
    assert quota["succeeded"] is succeeds
    assert quota["additional"] == expected_additional
    if not succeeds:
        assert "additional capacity is required" in quota["message"]


def _model_quota_resource_command(
    environment_name: str,
    *,
    capacity: int = 10,
    account_overrides: dict[str, object] | None = None,
    deployment_overrides: dict[str, object] | None = None,
    project_overrides: dict[str, object] | None = None,
    include_cached_account_id: bool = True,
    include_cached_project_id: bool = True,
) -> str:
    account_id = (
        f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-{environment_name}/"
        "providers/Microsoft.CognitiveServices/accounts/aif-owned"
    )
    account: dict[str, object] = {
        "id": account_id,
        "name": "aif-owned",
        "type": "Microsoft.CognitiveServices/accounts",
        "kind": "AIServices",
        "location": "eastus2",
        "tags": {
            "solution-template": "foundry-private-hosted-agent",
            "azd-env-name": environment_name,
            "azd-service-name": "private-search-agent",
        },
        "properties": {"allowProjectManagement": True},
    }
    project_id = f"{account_id}/projects/proj-owned"
    project: dict[str, object] = {
        "id": project_id,
        "name": "proj-owned",
        "type": "Microsoft.CognitiveServices/accounts/projects",
        "location": "eastus2",
        "tags": {
            "solution-template": "foundry-private-hosted-agent",
            "azd-env-name": environment_name,
            "azd-service-name": "private-search-agent",
        },
    }
    deployment: dict[str, object] = {
        "id": f"{account_id}/deployments/gpt-5.1",
        "name": "gpt-5.1",
        "type": "Microsoft.CognitiveServices/accounts/deployments",
        "sku": {"name": "Standard", "capacity": capacity},
        "properties": {
            "provisioningState": "Succeeded",
            "model": {
                "format": "OpenAI",
                "name": "gpt-5.1",
                "version": "2025-11-13",
            },
        },
    }
    if account_overrides:
        account.update(account_overrides)
    if deployment_overrides:
        deployment.update(deployment_overrides)
    if project_overrides:
        project.update(project_overrides)
    account_json = json.dumps(account, separators=(",", ":")).replace("'", "''")
    deployment_json = json.dumps(
        deployment, separators=(",", ":")
    ).replace("'", "''")
    project_json = json.dumps(project, separators=(",", ":")).replace("'", "''")
    account_id_argument = (
        f"-ExpectedAccountId '{account_id}'"
        if include_cached_account_id
        else ""
    )
    project_id_argument = (
        f"-ExpectedProjectId '{project_id}'"
        if include_cached_project_id
        else ""
    )
    account_list_json = json.dumps(
        [account], separators=(",", ":")
    ).replace("'", "''")
    project_list_json = json.dumps(
        [project], separators=(",", ":")
    ).replace("'", "''")
    return (
        "function Invoke-CheckedCommand { "
        "param($Stage, $FilePath, $Arguments, $WorkingDirectory, "
        "[switch]$Quiet, [switch]$AllowFailure); "
        "if ($Arguments[1] -eq 'list' -and "
        "$Arguments -contains 'Microsoft.CognitiveServices/accounts/projects') { "
        f"$json = '{project_list_json}' "
        "} elseif ($Arguments[1] -eq 'list') { "
        f"$json = '{account_list_json}' "
        "} elseif (($Arguments -join ' ') -like '*/deployments/*') { "
        f"$json = '{deployment_json}' "
        "} elseif (($Arguments -join ' ') -like '*/projects/*') { "
        f"$json = '{project_json}' "
        "} else { "
        f"$json = '{account_json}' "
        "}; "
        "return [pscustomobject]@{ ExitCode = 0; Output = @($json) } "
        "}; "
        "$capacity = Get-ExactReusableModelDeploymentCapacity "
        f"-SubscriptionId '{SUBSCRIPTION}' "
        f"-ResourceGroupName 'rg-{environment_name}' "
        f"-EnvironmentName '{environment_name}' -Location 'eastus2' "
        f"{account_id_argument} {project_id_argument}; "
        "Write-Output \"CAPACITY=$capacity\""
    )


@pytest.mark.parametrize(
    "environment_name",
    ["fpha-src-existing", "fpha-acr-existing"],
)
def test_exact_owned_model_capacity_is_reused_for_both_flows(
    environment_name: str,
) -> None:
    result = invoke_model_quota_contract(
        _model_quota_resource_command(environment_name)
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == "CAPACITY=10"


def test_owned_model_capacity_can_be_discovered_when_output_is_missing() -> None:
    result = invoke_model_quota_contract(
        _model_quota_resource_command(
            "fpha-src-existing",
            capacity=7,
            include_cached_account_id=False,
            include_cached_project_id=False,
        )
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == "CAPACITY=7"


@pytest.mark.parametrize(
    ("account_overrides", "project_overrides", "deployment_overrides"),
    [
        ({"name": "other", "id": "/subscriptions/other"}, None, None),
        (
            {
                "tags": {
                    "solution-template": "foundry-private-hosted-agent",
                    "azd-env-name": "other-environment",
                    "azd-service-name": "private-search-agent",
                }
            },
            None,
            None,
        ),
        (
            None,
            {
                "tags": {
                    "solution-template": "foundry-private-hosted-agent",
                    "azd-env-name": "other-environment",
                    "azd-service-name": "private-search-agent",
                }
            },
            None,
        ),
        (None, None, {"name": "other-deployment"}),
        (
            None,
            None,
            {
                "properties": {
                    "provisioningState": "Succeeded",
                    "model": {
                        "format": "OpenAI",
                        "name": "other-model",
                        "version": "2025-11-13",
                    },
                }
            },
        ),
        (
            None,
            None,
            {
                "properties": {
                    "provisioningState": "Succeeded",
                    "model": {
                        "format": "OpenAI",
                        "name": "gpt-5.1",
                        "version": "other-version",
                    },
                }
            },
        ),
        (None, None, {"sku": {"name": "GlobalStandard", "capacity": 10}}),
        (
            None,
            None,
            {
                "properties": {
                    "provisioningState": "Failed",
                    "model": {
                        "format": "OpenAI",
                        "name": "gpt-5.1",
                        "version": "2025-11-13",
                    },
                }
            },
        ),
    ],
)
def test_mismatched_or_failed_model_capacity_is_not_reused(
    account_overrides: dict[str, object] | None,
    project_overrides: dict[str, object] | None,
    deployment_overrides: dict[str, object] | None,
) -> None:
    result = invoke_model_quota_contract(
        _model_quota_resource_command(
            "fpha-src-existing",
            account_overrides=account_overrides,
            project_overrides=project_overrides,
            deployment_overrides=deployment_overrides,
        )
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == "CAPACITY=0"


def test_model_capacity_query_failure_is_fail_closed() -> None:
    result = invoke_model_quota_contract(
        "function Invoke-CheckedCommand { "
        "return [pscustomobject]@{ ExitCode = 1; Output = @() } "
        "}; "
        "$capacity = Get-ExactReusableModelDeploymentCapacity "
        f"-SubscriptionId '{SUBSCRIPTION}' "
        "-ResourceGroupName 'rg-fpha-src-existing' "
        "-EnvironmentName 'fpha-src-existing' -Location 'eastus2' "
        f"-ExpectedAccountId '/subscriptions/{SUBSCRIPTION}/"
        "resourceGroups/rg-fpha-src-existing/providers/"
        "Microsoft.CognitiveServices/accounts/aif-owned'; "
        "Write-Output \"CAPACITY=$capacity\""
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-1] == "CAPACITY=0"


def test_infrastructure_fingerprint_changes_with_deployment_inputs() -> None:
    result = invoke_workflow_contract(
        "$first = Get-InfrastructureFingerprint "
        f"-RepositoryRoot '{str(ROOT).replace("'", "''")}' "
        f"-ProjectDirectory '{str(ROOT).replace("'", "''")}' "
        "-Values @{ FPHA_DEPLOYMENT_MODE = 'Source' }; "
        "$second = Get-InfrastructureFingerprint "
        f"-RepositoryRoot '{str(ROOT).replace("'", "''")}' "
        f"-ProjectDirectory '{str(ROOT).replace("'", "''")}' "
        "-Values @{ FPHA_DEPLOYMENT_MODE = 'ExistingPrivateAcr' }; "
        "if ($first -eq $second) { throw 'Fingerprint did not change.' }"
    )
    assert result.returncode == 0, result.stderr


def test_s2s_shared_key_changes_only_the_one_way_fingerprint_input() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")
    assert "S2S_SHARED_KEY_SHA256 = Get-StringSha256" in deploy
    assert "environmentValues.S2S_SHARED_KEY" not in deploy
    assert "ConvertTo-Json `\n        -InputObject @($S2sRemoteAddressPrefixes)" in deploy
    result = invoke_workflow_contract(
        "$first = Get-StringSha256 -Value 'first-test-key'; "
        "$second = Get-StringSha256 -Value 'second-test-key'; "
        "if ($first -eq $second -or $first.Length -ne 64) { "
        "throw 'Secret digest contract failed.' }"
    )
    assert result.returncode == 0, result.stderr


def test_provider_sets_differ_only_for_existing_private_acr() -> None:
    result = invoke_workflow_contract(
        "$source = @(Get-RequiredProviderNamespaces -DeploymentMode Source); "
        "$acr = @(Get-RequiredProviderNamespaces "
        "-DeploymentMode ExistingPrivateAcr); "
        "$extra = @($acr | Where-Object { $_ -notin $source }); "
        "if ($source -contains 'Microsoft.ContainerRegistry' -or "
        "$extra.Count -ne 1 -or "
        "$extra[0] -ne 'Microsoft.ContainerRegistry') { "
        "throw 'Provider mode contract failed.' }"
    )
    assert result.returncode == 0, result.stderr


def test_provider_snapshot_must_match_mode_and_registered_set() -> None:
    result = invoke_workflow_contract(
        "$providers = @(Get-RequiredProviderNamespaces -DeploymentMode Source); "
        "$validation = [pscustomobject]@{ "
        "requiredProviders = $providers; "
        "providerRegistrations = @($providers | ForEach-Object { "
        "[pscustomobject]@{ namespace = $_; registrationState = 'Registered' } "
        "}); quotaProviderState = 'NotRegistered'; "
        "searchLocations = @('Central US') }; "
        "Assert-AzureProviderValidation "
        "-Validation $validation -DeploymentMode Source"
    )
    assert result.returncode == 0, result.stderr
    assert "[OK] Provider: Microsoft.Search" in result.stdout


def test_quiet_commands_emit_timing_without_sensitive_output() -> None:
    secret = "do-not-print-this-value"
    result = invoke_workflow_contract(
        "Invoke-CheckedCommand -Stage 'Set azd value TEST_VALUE (1/1)' "
        "-FilePath 'pwsh' "
        f"-Arguments @('-NoProfile', '-Command', \"Write-Output '{secret}'\") "
        "-Quiet -RedactArgumentIndexes @(2) | Out-Null"
    )
    assert result.returncode == 0, result.stderr
    assert "[START] Set azd value TEST_VALUE (1/1)" in result.stdout
    assert "[DONE] Set azd value TEST_VALUE (1/1)" in result.stdout
    assert "s)" in result.stdout
    assert secret not in result.stdout
    assert secret not in result.stderr


def test_non_quiet_command_output_is_streamed_once() -> None:
    result = invoke_workflow_contract(
        "$env:FPHA_TEST_OUTPUT = 'visible-child-output-✓'; "
        "Invoke-CheckedCommand -Stage 'Stream child output' "
        "-FilePath 'pwsh' "
        "-Arguments @('-NoProfile', '-Command', "
        "'Write-Output $env:FPHA_TEST_OUTPUT') | Out-Null"
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.count("visible-child-output-✓") == 1
    assert "Γ£ô" not in result.stdout
    assert "[START] Stream child output" in result.stdout
    assert "[DONE] Stream child output" in result.stdout


def test_native_utf8_output_and_encoding_state_are_preserved() -> None:
    result = invoke_workflow_contract(
        "$originalInput = [Console]::InputEncoding; "
        "$originalOutput = [Console]::OutputEncoding; "
        "$originalPowerShellOutput = $OutputEncoding; "
        "$legacy = [Text.Encoding]::GetEncoding(437); "
        "try { "
        "[Console]::InputEncoding = $legacy; "
        "[Console]::OutputEncoding = $legacy; "
        "$OutputEncoding = $legacy; "
        "$child = '[Console]::OutputEncoding = "
        "[Text.UTF8Encoding]::new($false); "
        "[Console]::WriteLine(''{\"mark\":\"✓\"}''); "
        "[Console]::Error.WriteLine(''stderr ✓'')'; "
        "$commandResult = Invoke-CheckedCommand -Stage 'Capture UTF-8' "
        "-FilePath 'pwsh' -Arguments @('-NoProfile', '-Command', $child) "
        "-Quiet; "
        "$payload = $commandResult.Output[0] | ConvertFrom-Json; "
        "if ($payload.mark -ne '✓' -or "
        "$commandResult.Output[1] -ne 'stderr ✓') { "
        "throw 'Native UTF-8 output was corrupted.' }; "
        "if ([Console]::InputEncoding.CodePage -ne $legacy.CodePage -or "
        "[Console]::OutputEncoding.CodePage -ne $legacy.CodePage -or "
        "$OutputEncoding.CodePage -ne $legacy.CodePage) { "
        "throw 'Encoding state was not restored.' }; "
        "try { "
        "Invoke-CheckedCommand -Stage 'Expected native failure' "
        "-FilePath 'fpha-command-that-does-not-exist' -Quiet | Out-Null; "
        "throw 'Expected Invoke-CheckedCommand to fail.' "
        "} catch { "
        "if ($_.Exception.Message -notmatch "
        "\"Stage 'Expected native failure' failed\") { throw } "
        "}; "
        "if ([Console]::InputEncoding.CodePage -ne $legacy.CodePage -or "
        "[Console]::OutputEncoding.CodePage -ne $legacy.CodePage -or "
        "$OutputEncoding.CodePage -ne $legacy.CodePage) { "
        "throw 'Encoding state was not restored after failure.' }; "
        "} finally { "
        "[Console]::InputEncoding = $originalInput; "
        "[Console]::OutputEncoding = $originalOutput; "
        "$OutputEncoding = $originalPowerShellOutput "
        "}"
    )
    assert result.returncode == 0, result.stderr
    assert "Γ£ô" not in result.stdout
    assert "Γ£ô" not in result.stderr


def test_unified_preflight_reuses_provider_snapshot() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")
    providers = (
        ROOT / "scripts/deployment/providers.ps1"
    ).read_text(encoding="utf-8")

    assert "'-ProviderValidationJson'" in deploy
    assert "'-ResourceGroupExists'" in deploy
    assert "-RedactArgumentIndexes @(18)" in deploy
    assert "$ProviderValidationJson | ConvertFrom-Json" in preflight
    assert "$groupExists = $ResourceGroupExists" in preflight
    assert "[REUSE] Required providers and Search regional metadata" in preflight
    assert "az provider show" not in preflight
    assert providers.count("'provider', 'show'") == 1
    assert providers.count("'provider', 'list'") == 1
    assert deploy.count("-Stage 'Validate existing private ACR'") == 0
    assert preflight.count("-Stage 'Validate existing private ACR inputs'") == 1
    assert "'-EnvironmentName', $EnvironmentName" in deploy
    assert (
        "'-ExistingFoundryAccountId', "
        "[string]$currentEnvironmentValues['AZURE_AI_ACCOUNT_ID']"
        in deploy
    )
    assert (
        "'-ExistingFoundryProjectId', "
        "[string]$currentEnvironmentValues['AZURE_AI_PROJECT_ID']"
        in deploy
    )
    assert "$environmentContext.BindingValidated -and $groupExists" in deploy
    assert "$AllowExistingModelCapacityReuse" in preflight
    assert "Get-ExactReusableModelDeploymentCapacity" in preflight
    assert "Assert-RegionalModelQuota" in preflight


def test_deploy_selects_resolved_environment_before_child_scripts() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")

    initialize = deploy.index(
        "$currentEnvironmentValues = Initialize-AzdEnvironment"
    )
    select = deploy.index("-Stage 'Select azd environment'")
    preflight = deploy.index("$preflightArguments = @(")

    assert initialize < select < preflight
    assert (
        "-Arguments @('env', 'select', $EnvironmentName, '--no-prompt')"
        in deploy
    )


def test_deploy_scopes_environment_sensitive_commands_explicitly() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")
    diagnostics = (
        ROOT / "scripts/deployment/diagnostics.ps1"
    ).read_text(encoding="utf-8")
    workflow = (
        ROOT / "scripts/deployment/workflow.ps1"
    ).read_text(encoding="utf-8")
    common = (ROOT / "scripts/common.ps1").read_text(encoding="utf-8")

    assert (
        "'provision', '-e', $EnvironmentName, '--preview', '--no-prompt'"
        in deploy
    )
    assert deploy.count(
        "'deploy', $serviceName, '-e', $EnvironmentName, '--no-prompt'"
    ) == 2
    assert "'provision', '-e', $EnvironmentName, '--no-prompt'" in diagnostics
    assert "-EnvironmentName $EnvironmentName `" in workflow
    assert "$arguments += @('-e', $EnvironmentName)" in common

    for script_name in (
        "assign-agent-search-role.ps1",
        "export-p2s-profile.ps1",
        "seed-search.ps1",
        "validate-all.ps1",
        "validate-cmk.ps1",
        "validate-existing-acr.ps1",
        "validate-infrastructure.ps1",
        "validate-network.ps1",
        "validate-rbac.ps1",
    ):
        script = (ROOT / "scripts" / script_name).read_text(encoding="utf-8")
        assert "Get-AzdValues -EnvironmentName $EnvironmentName" in script


@pytest.mark.parametrize(
    ("permissions", "expected"),
    [
        ([{"actions": ["*"], "notActions": []}], True),
        (
            [
                {
                    "actions": ["Microsoft.Authorization/*"],
                    "notActions": [],
                }
            ],
            True,
        ),
        (
            [
                {
                    "actions": ["*"],
                    "notActions": ["Microsoft.Authorization/*/Write"],
                }
            ],
            False,
        ),
        (
            [
                {
                    "actions": ["Microsoft.Authorization/*/read"],
                    "notActions": [],
                }
            ],
            False,
        ),
    ],
)
def test_effective_permission_matching_honors_wildcards_and_exclusions(
    permissions: list[dict[str, list[str]]],
    expected: bool,
) -> None:
    module = ROOT / "scripts/deployment/permissions.ps1"
    escaped_module = str(module).replace("'", "''")
    command = (
        f". '{escaped_module}'; "
        "$permissions = [Console]::In.ReadToEnd() | ConvertFrom-Json; "
        "$allowed = Test-AzurePermissionsAllowAction "
        "-Permissions @($permissions) "
        "-Action 'Microsoft.Authorization/roleAssignments/write'; "
        "if ($allowed) { exit 0 }; exit 1"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        input=json.dumps(permissions),
        capture_output=True,
        text=True,
        check=False,
    )
    assert (result.returncode == 0) is expected, result.stderr


def test_preflight_requires_role_assignment_write_permission() -> None:
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")
    permissions = (
        ROOT / "scripts/deployment/permissions.ps1"
    ).read_text(encoding="utf-8")

    assert "Get-AzureEffectivePermissions" in preflight
    assert "Microsoft.Authorization/roleAssignments/write" in preflight
    assert "Preview still evaluates ABAC conditions" in preflight
    assert "time-bound grants must remain active" in preflight
    assert "permissions?api-version=2022-04-01" in permissions
    assert "[Uri]::EscapeDataString($ResourceGroupName)" in permissions


def test_effective_permission_lookup_follows_next_link() -> None:
    module = ROOT / "scripts/deployment/permissions.ps1"
    escaped_module = str(module).replace("'", "''")
    command = (
        "$script:requests = 0; "
        "function Invoke-CheckedCommand { "
        "param($Stage, $FilePath, $Arguments, [switch]$Quiet); "
        "$script:requests++; "
        "if ($script:requests -eq 1) { "
        "return [pscustomobject]@{ Output = @("
        "'{\"value\":[{\"actions\":[\"Microsoft.Resources/*\"],"
        "\"notActions\":[]}],\"nextLink\":\"https://next.example\"}'"
        ") } }; "
        "return [pscustomobject]@{ Output = @("
        "'{\"value\":[{\"actions\":["
        "\"Microsoft.Authorization/roleAssignments/write\"],"
        "\"notActions\":[]}]}'"
        ") } "
        "}; "
        f". '{escaped_module}'; "
        "$result = Get-AzureEffectivePermissions "
        "-SubscriptionId 'sub' -ResourceGroupName 'rg' "
        "-ResourceGroupExists $true; "
        "if ($script:requests -ne 2 -or $result.Permissions.Count -ne 2) { "
        "throw 'Permission pagination was not followed.' "
        "}"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_azd_environment_values_are_redacted_and_only_changed_values_are_set() -> None:
    workflow = (
        ROOT / "scripts/deployment/workflow.ps1"
    ).read_text(encoding="utf-8")
    assert "$CurrentValues.ContainsKey($name)" in workflow
    assert "[SKIP] azd value $name is already current." in workflow
    assert "-RedactArgumentIndexes @(3)" in workflow


def test_environment_initialization_returns_merged_cached_values() -> None:
    result = invoke_workflow_contract(
        "$script:setCount = 0; "
        "function Invoke-CheckedCommand { param($Stage, $FilePath, $Arguments, "
        "$WorkingDirectory, [switch]$Quiet, $RedactArgumentIndexes); "
        "if ($Arguments[1] -eq 'set') { $script:setCount++ }; "
        "return [pscustomobject]@{ Output = @(); ExitCode = 0 } }; "
        "$values = Initialize-AzdEnvironment -ProjectDirectory '.' "
        "-EnvironmentName 'existing' "
        f"-SubscriptionId '{SUBSCRIPTION}' -Location 'eastus2' "
        "-Values @{ FPHA_DEPLOYMENT_MODE = 'Source' } "
        "-CurrentValues @{ FPHA_DEPLOYMENT_MODE = 'Source'; "
        "FPHA_INFRASTRUCTURE_FINGERPRINT = 'preserved' } "
        "-EnvironmentNames @('existing'); "
        "[pscustomobject]@{ setCount = $script:setCount; "
        "fingerprint = $values['FPHA_INFRASTRUCTURE_FINGERPRINT']; "
        "mode = $values['FPHA_DEPLOYMENT_MODE'] } | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout.splitlines()[-1]) == {
        "setCount": 0,
        "fingerprint": "preserved",
        "mode": "Source",
    }


def test_deploy_reuses_resolved_environment_values_through_startup() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")
    workflow = (
        ROOT / "scripts/deployment/workflow.ps1"
    ).read_text(encoding="utf-8")

    assert "Resolve-AzdEnvironmentContext" in deploy
    assert "$existingEnvironmentValues = $environmentContext.Values" in deploy
    assert "$currentEnvironmentValues = Initialize-AzdEnvironment" in deploy
    assert (
        "$currentEnvironmentValues['FPHA_INFRASTRUCTURE_FINGERPRINT']"
        in deploy
    )
    startup = deploy.split("Ensure-AzdExtensions", maxsplit=1)[0]
    assert "Get-AzdEnvironmentValues" not in startup
    assert "return $updatedValues" in workflow


def test_azd_deployment_reference_parsing_supports_both_arm_scopes() -> None:
    result = invoke_workflow_contract(
        "$references = @(Get-AzdDeploymentReferences -SubscriptionId "
        f"'{SUBSCRIPTION}' -Output @("
        f"'Deployment name: fpha-src-root', "
        f"'/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-test/"
        "providers/Microsoft.Resources/deployments/network')); "
        "$references | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    references = json.loads(result.stdout)
    assert {(item["scope"], item["name"]) for item in references} == {
        ("subscription", "fpha-src-root"),
        ("resourceGroup", "network"),
    }


def test_azd_deployment_reference_parses_portal_encoded_arm_id() -> None:
    deployment_id = (
        f"/subscriptions/{SUBSCRIPTION}/providers/"
        "Microsoft.Resources/deployments/fpha-src-root"
    )
    encoded_id = deployment_id.replace("/", "%2F")
    result = invoke_workflow_contract(
        "$references = @(Get-AzdDeploymentReferences -SubscriptionId "
        f"'{SUBSCRIPTION}' -Output @("
        f"'https://portal.azure.com/#view/Deployment/id/{encoded_id}')); "
        "$references | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    reference = json.loads(result.stdout)
    assert reference["scope"] == "subscription"
    assert reference["name"] == "fpha-src-root"
    assert reference["id"] == deployment_id


def test_arm_diagnostic_text_redacts_generic_credentials() -> None:
    result = invoke_workflow_contract(
        "$value = 'sharedKey=TopSecret123 "
        "connectionString=AccountKey=abc123 "
        "apiKey:xyz789 SharedAccessSignature=sv%3D1%26sig%3Dsecret "
        "token=generic-token-value sas=sv%3D1%26sig%3Dbare-secret "
        "{\"token\":\"json-token-value\"}'; "
        "Protect-ArmDiagnosticText $value"
    )
    assert result.returncode == 0, result.stderr
    for secret in (
        "TopSecret123",
        "abc123",
        "xyz789",
        "sig%3Dsecret",
        "generic-token-value",
        "bare-secret",
        "json-token-value",
    ):
        assert secret not in result.stdout
    assert result.stdout.count("<redacted>") >= 7


def test_nested_arm_operations_expand_to_sanitized_leaf_failure() -> None:
    root_id = (
        f"/subscriptions/{SUBSCRIPTION}/providers/"
        "Microsoft.Resources/deployments/fpha-src-root"
    )
    nested_id = (
        f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-test/providers/"
        "Microsoft.Resources/deployments/network"
    )
    key_vault_id = (
        f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-test/providers/"
        "Microsoft.KeyVault/vaults/kv-test"
    )
    root_operations = json.dumps(
        [
            {
                "properties": {
                    "provisioningState": "Failed",
                    "targetResource": {
                        "id": nested_id,
                        "resourceType": "Microsoft.Resources/deployments",
                        "resourceName": "network",
                    },
                    "statusMessage": {
                        "error": {
                            "code": "DeploymentFailed",
                            "message": "Nested deployment failed.",
                        }
                    },
                }
            }
        ],
        separators=(",", ":"),
    ).replace("'", "''")
    nested_operations = json.dumps(
        [
            {
                "properties": {
                    "provisioningState": "Failed",
                    "correlationId": "c975c80f-25de-4728-a12c-21808e052eaa",
                    "timestamp": "2026-02-21T12:34:56Z",
                    "targetResource": {
                        "id": key_vault_id,
                        "resourceType": "Microsoft.KeyVault/vaults",
                        "resourceName": "kv-test",
                    },
                    "statusMessage": {
                        "error": {
                            "code": "ResourceDeploymentFailure",
                            "details": [
                                {
                                    "code": "Conflict",
                                    "target": "kv-test",
                                    "message": (
                                        "A soft-deleted vault uses this name; "
                                        "claims: private-claim"
                                    ),
                                }
                            ],
                        }
                    },
                }
            }
        ],
        separators=(",", ":"),
    ).replace("'", "''")
    result = invoke_workflow_contract(
        "function Invoke-CheckedCommand { param($Stage,$FilePath,$Arguments,"
        "[switch]$Quiet,[switch]$AllowFailure); "
        "$nameIndex = [Array]::IndexOf($Arguments, '--name'); "
        "$name = $Arguments[$nameIndex + 1]; "
        f"if ($name -eq 'fpha-src-root') {{ $json = '{root_operations}' }} "
        f"elseif ($name -eq 'network') {{ $json = '{nested_operations}' }} "
        "else { throw \"Unexpected deployment $name\" }; "
        "return [pscustomobject]@{ ExitCode = 0; "
        "Output = @('non-json Azure CLI notice', $json) } }; "
        f"$reference = ConvertTo-ArmDeploymentReference -ResourceId '{root_id}'; "
        "$failures = @(Expand-ArmDeploymentFailures -Reference $reference); "
        "$failures | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    failure = json.loads(result.stdout)
    assert failure["resource"] == "kv-test"
    assert failure["resourceType"] == "Microsoft.KeyVault/vaults"
    assert failure["resourceId"] == key_vault_id
    assert failure["scope"] == "resourceGroup:rg-test"
    assert failure["timestampUtc"] == "2026-02-21T12:34:56Z"
    assert failure["code"] == "Conflict"
    assert failure["target"] == "kv-test"
    assert "soft-deleted vault" in failure["message"]
    assert "private-claim" not in result.stdout
    assert "claims=<redacted>" in failure["message"]
    assert failure["correlationId"] == "c975c80f-25de-4728-a12c-21808e052eaa"


def test_arm_diagnostic_query_failure_preserves_original_failure() -> None:
    result = invoke_workflow_contract(
        "function Invoke-CheckedCommand { "
        "return [pscustomobject]@{ ExitCode = 9; Output = @() } }; "
        "Invoke-AzdProvisionFailureDiagnostics "
        f"-ProvisionOutput @(\"The template deployment 'fpha-src-failed' failed\") "
        f"-SubscriptionId '{SUBSCRIPTION}' "
        "-ResourceGroupName 'rg-test' -EnvironmentName 'fpha-src-test' "
        "| Out-Null; "
        "Write-Output 'original-failure-still-authoritative'"
    )
    assert result.returncode == 0, result.stderr
    assert "Unable to query deployment 'fpha-src-failed'" in result.stdout
    assert "original provision failure is preserved" in result.stdout
    assert "original-failure-still-authoritative" in result.stdout


def test_non_retryable_provision_failure_is_diagnosed_without_retry() -> None:
    result = invoke_workflow_contract(
        "$script:provisionCount = 0; $script:diagnosticCount = 0; "
        "$script:guidanceCount = 0; "
        "function Invoke-CheckedCommand { "
        "$script:provisionCount++; "
        "return [pscustomobject]@{ ExitCode = 37; "
        "Output = @('Deployment name: root'); Command = 'azd provision' } "
        "}; "
        "function Invoke-AzdProvisionFailureDiagnostics { "
        "$script:diagnosticCount++; "
        "return [pscustomobject]@{ failures = @() } "
        "}; "
        "function Write-AzdProvisionFailureGuidance { "
        "$script:guidanceCount++ "
        "}; "
        "function Set-AzdFirewallCreationMode {}; "
        "try { Invoke-ProvisionWithArmDiagnostics -ProjectDirectory '.' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-test' "
        "-EnvironmentName 'fpha-src-test' | Out-Null; "
        "throw 'Expected provision failure.' } catch { "
        "$failure = $_.Exception.Message; "
        "$nativeExitCode = $_.Exception.Data['NativeExitCode']; "
        "$nativeCommand = $_.Exception.Data['NativeCommand'] }; "
        "Write-Output \"PROVISIONS=$script:provisionCount "
        "DIAGNOSTICS=$script:diagnosticCount GUIDANCE=$script:guidanceCount "
        "EXIT=$nativeExitCode COMMAND=$nativeCommand FAILURE=$failure\""
    )
    assert result.returncode == 0, result.stderr
    assert "PROVISIONS=1 DIAGNOSTICS=1 GUIDANCE=1" in result.stdout
    assert "EXIT=37 COMMAND=azd provision" in result.stdout
    assert "Provision infrastructure" in result.stdout


def test_transient_firewall_failure_retries_unchanged_provision_once() -> None:
    result = invoke_workflow_contract(
        "$script:provisionCount = 0; $script:diagnosticCount = 0; "
        "function Invoke-CheckedCommand { "
        "$script:provisionCount++; "
        "if ($script:provisionCount -eq 1) { "
        "return [pscustomobject]@{ ExitCode = 37; "
        "Output = @('Deployment name: root'); Command = 'azd provision' } "
        "}; return [pscustomobject]@{ ExitCode = 0; "
        "Output = @(); Command = 'azd provision' } "
        "}; "
        "function Invoke-AzdProvisionFailureDiagnostics { "
        "$script:diagnosticCount++; "
        "return [pscustomobject]@{ failures = @([pscustomobject]@{ "
        "resourceType = 'Microsoft.Network/azureFirewalls'; "
        "provisioningState = 'Failed'; code = 'InternalServerError'; "
        "message = 'An error occurred.' }) } "
        "}; "
        "function Write-AzdProvisionFailureGuidance { "
        "throw 'Guidance must not run after a successful retry.' "
        "}; "
        "function Set-AzdFirewallCreationMode {}; "
        "Invoke-ProvisionWithArmDiagnostics -ProjectDirectory '.' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-test' "
        "-EnvironmentName 'fpha-src-test' | Out-Null; "
        "Write-Output \"PROVISIONS=$script:provisionCount "
        "DIAGNOSTICS=$script:diagnosticCount\""
    )
    assert result.returncode == 0, result.stderr
    assert "PROVISIONS=2 DIAGNOSTICS=1" in result.stdout
    assert "Retrying the unchanged idempotent provision once" in result.stdout


def test_provision_progress_labels_active_resources_without_time_estimates() -> None:
    result = invoke_workflow_contract(
        "$types = @("
        "'Microsoft.Network/azureFirewalls', "
        "'Microsoft.Network/virtualNetworkGateways', "
        "'Microsoft.CognitiveServices/accounts/projects', "
        "'Microsoft.Search/searchServices', "
        "'Microsoft.Network/privateEndpoints'); "
        "$types | ForEach-Object { "
        "Get-AzdProvisionResourceDescription "
        "-ResourceType $_ -ResourceName 'test' "
        "} | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    descriptions = json.loads(result.stdout)
    assert [item["label"] for item in descriptions] == [
        "Azure Firewall",
        "VPN Gateway",
        "Foundry project",
        "Azure AI Search",
        "Private Endpoint",
    ]
    assert all("expectation" not in item for item in descriptions)


def test_firewall_creation_stage_runs_only_before_policy_attachment() -> None:
    result = invoke_workflow_contract(
        "$empty = Test-FirewallCreationRequired "
        "-Firewalls @() -EnvironmentName 'env-one'; "
        "$withoutPolicy = Test-FirewallCreationRequired "
        "-Firewalls @([pscustomobject]@{ "
        "tags = [pscustomobject]@{ 'azd-env-name' = 'env-one' }; "
        "firewallPolicy = $null }) -EnvironmentName 'env-one'; "
        "$withPolicy = Test-FirewallCreationRequired "
        "-Firewalls @([pscustomobject]@{ "
        "tags = [pscustomobject]@{ 'azd-env-name' = 'env-one' }; "
        "properties = [pscustomobject]@{ "
        "firewallPolicy = [pscustomobject]@{ id = '/policy/id' } } }) "
        "-EnvironmentName 'env-one'; "
        "Write-Output \"EMPTY=$empty WITHOUT=$withoutPolicy WITH=$withPolicy\""
    )
    assert result.returncode == 0, result.stderr
    assert "EMPTY=True WITHOUT=True WITH=False" in result.stdout


def test_provision_progress_reports_stage_change_and_running_heartbeat() -> None:
    result = invoke_workflow_contract(
        "function Get-AzdProvisionProgressSnapshot { "
        "return @([pscustomobject]@{ "
        "resourceType = 'Microsoft.Network/azureFirewalls'; "
        "resourceName = 'afw-test' }) "
        "}; "
        "$context = [pscustomobject]@{ "
        "LastHeartbeatUtc = [DateTime]::UtcNow.AddMinutes(-2); "
        "LastSignature = '' }; "
        "Write-AzdProvisionProgress -Context $context; "
        "$context.LastHeartbeatUtc = [DateTime]::UtcNow.AddMinutes(-2); "
        "Write-AzdProvisionProgress -Context $context"
    )
    assert result.returncode == 0, result.stderr
    assert "[PROGRESS] Provisioning Azure Firewall 'afw-test'." in result.stdout
    assert (
        "[WAITING] Waiting for Azure Firewall 'afw-test'; ARM status is Running."
        in result.stdout
    )
    assert "SLA" not in result.stdout
    assert "elapsed" not in result.stdout
    assert "minute" not in result.stdout


def test_provision_progress_uses_generic_heartbeat_when_arm_is_not_visible() -> None:
    result = invoke_workflow_contract(
        "function Get-AzdProvisionProgressSnapshot { return @() }; "
        "$context = [pscustomobject]@{ "
        "LastHeartbeatUtc = [DateTime]::UtcNow.AddMinutes(-2); "
        "LastSignature = '' }; "
        "Write-AzdProvisionProgress -Context $context"
    )
    assert result.returncode == 0, result.stderr
    assert "[WAITING] ARM is coordinating nested deployments" in result.stdout
    assert "waiting for the next active resource" in result.stdout
    assert "elapsed" not in result.stdout


def test_streaming_runner_preserves_output_and_exit_when_progress_lookup_fails() -> None:
    result = invoke_workflow_contract(
        "function Write-AzdProvisionProgress { throw 'lookup failed' }; "
        "$script:AzdProvisionProgressContext = [pscustomobject]@{ "
        "InitialProgressDelaySeconds = 0; "
        "ProgressPollIntervalSeconds = 0.1 }; "
        "$result = Invoke-StreamingNativeCommand -FilePath 'pwsh' "
        "-Arguments @('-NoProfile', '-Command', "
        "'Write-Output child-line; Start-Sleep -Milliseconds 300; exit 7'); "
        "Write-Output \"EXIT=$($result.ExitCode) "
        "OUTPUT=$($result.Output -join ',')\""
    )
    assert result.returncode == 0, result.stderr
    assert "[PROGRESS WARNING] ARM progress lookup was temporarily unavailable" in (
        result.stdout
    )
    assert "EXIT=7 OUTPUT=child-line" in result.stdout


def test_successful_provision_skips_diagnostics_and_guidance() -> None:
    result = invoke_workflow_contract(
        "$script:provisionCount = 0; "
        "function Invoke-CheckedCommand { "
        "$script:provisionCount++; "
        "return [pscustomobject]@{ ExitCode = 0; "
        "Output = @(); Command = 'azd provision' } "
        "}; "
        "function Invoke-AzdProvisionFailureDiagnostics { "
        "throw 'Diagnostics must not run after success.' "
        "}; "
        "function Write-AzdProvisionFailureGuidance { "
        "throw 'Guidance must not run after success.' "
        "}; "
        "function Set-AzdFirewallCreationMode {}; "
        "Invoke-ProvisionWithArmDiagnostics -ProjectDirectory '.' "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-test' "
        "-EnvironmentName 'fpha-src-test' | Out-Null; "
        "Write-Output \"PROVISIONS=$script:provisionCount\""
    )
    assert result.returncode == 0, result.stderr
    assert "PROVISIONS=1" in result.stdout


@pytest.mark.parametrize(
    ("resource_type", "code", "message", "category", "action_fragment"),
    [
        (
            "Microsoft.KeyVault/vaults",
            "Conflict",
            "A vault already exists or is soft-deleted.",
            "Conflict",
            "soft-deleted",
        ),
        (
            "Microsoft.Search/searchServices",
            "QuotaExceeded",
            "Regional capacity quota is insufficient.",
            "QuotaOrCapacity",
            "Do not rerun unchanged",
        ),
        (
            "Microsoft.Search/searchServices",
            "RequestDisallowedByPolicy",
            "Policy denied this resource.",
            "Policy",
            "policy assignment",
        ),
        (
            "Microsoft.Authorization/roleAssignments",
            "AuthorizationFailed",
            "ABAC condition rejected assignment.",
            "Authorization",
            "Do not rerun until access is corrected",
        ),
        (
            "Microsoft.CognitiveServices/accounts",
            "InternalServerError",
            "The provider returned HTTP 500.",
            "ServiceOrTransient",
            "single later rerun is reasonable",
        ),
        (
            "Microsoft.Network/privateEndpoints",
            "AccountProvisioningStateInvalid",
            "Foundry account is still in state Accepted.",
            "ServiceOrTransient",
            "single later rerun is reasonable",
        ),
        (
            "Microsoft.Network/privateEndpoints",
            "UnmappedProviderCode",
            "No known classification.",
            "Unknown",
            "Rerun safety is unknown",
        ),
    ],
)
def test_arm_failure_guidance_is_resource_agnostic(
    resource_type: str,
    code: str,
    message: str,
    category: str,
    action_fragment: str,
) -> None:
    result = invoke_workflow_contract(
        "$failure = [pscustomobject]@{ "
        f"resourceType = '{resource_type}'; code = '{code}'; "
        f"message = '{message}'; provisioningState = '' "
        "}; "
        "Get-ArmFailureGuidance -Failure $failure | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    guidance = json.loads(result.stdout)
    assert guidance["category"] == category
    assert action_fragment.lower() in guidance["action"].lower()


def test_terminal_failed_state_has_generic_action() -> None:
    result = invoke_workflow_contract(
        "$failure = [pscustomobject]@{ code = 'UnclassifiedFailure'; "
        "message = 'Provisioning ended.'; provisioningState = 'Failed' }; "
        "Get-ArmFailureGuidance -Failure $failure | ConvertTo-Json -Compress"
    )
    assert result.returncode == 0, result.stderr
    guidance = json.loads(result.stdout)
    assert guidance["category"] == "TerminalFailedState"
    assert "Do not rerun blindly" in guidance["action"]
    assert "existing Failed resource" in guidance["action"]


def test_leaf_diagnostic_prints_resource_agnostic_evidence() -> None:
    resource_id = (
        f"/subscriptions/{SUBSCRIPTION}/resourceGroups/rg-test/providers/"
        "Microsoft.KeyVault/vaults/kv-test"
    )
    correlation_id = "c975c80f-25de-4728-a12c-21808e052eaa"
    result = invoke_workflow_contract(
        "function Get-AzdDeploymentReferences { "
        "return @([pscustomobject]@{ scope = 'resourceGroup'; "
        f"subscriptionId = '{SUBSCRIPTION}'; resourceGroupName = 'rg-test'; "
        "name = 'root'; id = '' }) "
        "}; "
        "function Expand-ArmDeploymentFailures { "
        "return @([pscustomobject]@{ resource = 'kv-test'; "
        "resourceType = 'Microsoft.KeyVault/vaults'; "
        f"resourceId = '{resource_id}'; scope = 'resourceGroup:rg-test'; "
        "code = 'Conflict'; message = 'Vault is soft-deleted'; "
        "target = 'kv-test'; "
        f"correlationId = '{correlation_id}'; "
        "timestampUtc = '2026-07-28T04:00:00Z' }) "
        "}; "
        "function Get-ArmResourceProvisioningState { return 'Failed' }; "
        "$diagnostics = Invoke-AzdProvisionFailureDiagnostics "
        "-ProvisionOutput @('Deployment name: root') "
        f"-SubscriptionId '{SUBSCRIPTION}' "
        "-ResourceGroupName 'rg-test' -EnvironmentName 'fpha-src-test'; "
        "Write-AzdProvisionFailureGuidance "
        "-Failures @($diagnostics.failures) "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-test'"
    )
    assert result.returncode == 0, result.stderr
    for expected in (
        "resource='kv-test'",
        f"id='{resource_id}'",
        "type='Microsoft.KeyVault/vaults'",
        "scope='resourceGroup:rg-test'",
        "state='Failed'",
        "utc='2026-07-28T04:00:00Z'",
        "code='Conflict'",
        "target='kv-test'",
        f"[ARM CORRELATION] {correlation_id}",
        "[NEXT STEP][Conflict]",
        "Deployment details > Operation details",
        "Subscription scope:",
        "Monitor > Activity log",
        "docs/troubleshooting.md#arm-deployment-failure-categories",
        "Azure Support",
    ):
        assert expected in result.stdout
    assert "No Azure resource was modified" in result.stdout


def test_generic_failure_guidance_is_read_only_and_support_ready() -> None:
    result = invoke_workflow_contract(
        "Write-AzdProvisionFailureGuidance -Failures @() "
        f"-SubscriptionId '{SUBSCRIPTION}' -ResourceGroupName 'rg-test'"
    )
    assert result.returncode == 0, result.stderr
    for expected in (
        "No resource-level repair was performed",
        "will not be retried further",
        "Deployment details > Operation details",
        "Monitor > Activity log",
        "Azure Support",
        "docs/troubleshooting.md#arm-deployment-failure-categories",
    ):
        assert expected in result.stdout


def test_diagnostics_source_allows_only_bounded_firewall_transient_retry() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8")
    diagnostics = (
        ROOT / "scripts/deployment/diagnostics.ps1"
    ).read_text(encoding="utf-8")
    deployment_docs = (ROOT / "docs/deployment.md").read_text(encoding="utf-8")
    troubleshooting = (ROOT / "docs/troubleshooting.md").read_text(
        encoding="utf-8"
    )

    assert deploy.count("Invoke-ProvisionWithArmDiagnostics") == 1
    assert "$_.Exception.Data['NativeExitCode']" in deploy
    assert "exit [int]$nativeExitCode" in deploy
    assert diagnostics.count("-Stage 'Provision infrastructure'") == 1
    assert "'resource', 'delete'" not in diagnostics
    assert "'resource', 'wait'" not in diagnostics
    assert "automatic recovery" not in diagnostics.lower()
    normalized_deployment_docs = " ".join(deployment_docs.split())
    assert (
        "retries the same idempotent `azd provision` command once"
        in normalized_deployment_docs
    )
    assert "Microsoft.Network/azureFirewalls" in diagnostics
    assert "AccountProvisioningStateInvalid" in diagnostics
    assert "Provision infrastructure retry (1/1)" in diagnostics
    assert "Write-AzdProvisionProgress" in diagnostics
    assert "[WAITING]" in diagnostics
    assert "not an SLA" not in diagnostics
    assert "can take" not in diagnostics
    assert "& az group exists" in diagnostics
    assert "& az rest" in diagnostics
    assert "az network firewall" not in diagnostics
    assert "FPHA_FIREWALL_CREATION_REQUIRED" in diagnostics
    assert "no resource-level repair" in diagnostics.lower()
    assert "ARM provisioning fails for any resource" in troubleshooting
    assert "## ARM deployment failure categories" in troubleshooting
    assert "docs/internal" not in deployment_docs
    assert "docs/internal" not in troubleshooting


def test_preview_allows_create_only_changes() -> None:
    result = invoke_preview_contract(
        "+ Microsoft.Resources/resourceGroups rg-fpha-src-test Create"
    )
    assert result.returncode == 0, result.stderr


def test_preview_allows_acr_id_as_connection_metadata() -> None:
    result = invoke_preview_contract(
        "+ properties.credentials: "
        '{"resourceId":"/providers/Microsoft.ContainerRegistry/registries/external"}',
        "ExistingPrivateAcr",
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize(
    ("preview", "mode"),
    [
        ("- Microsoft.Search/searchServices old Delete", "Source"),
        ("! Microsoft.KeyVault/vaults old Replace", "Source"),
        ("Delete : Search service : old", "Source"),
        ("Replace : Key Vault : old", "Source"),
        (
            "+ Microsoft.ContainerRegistry/registries enterpriseacr Create",
            "ExistingPrivateAcr",
        ),
        ("Create : Azure Container Registry : enterpriseacr", "ExistingPrivateAcr"),
    ],
)
def test_preview_rejects_destructive_or_external_acr_changes(
    preview: str, mode: str
) -> None:
    result = invoke_preview_contract(preview, mode)
    assert result.returncode != 0


def test_acr_workflow_does_not_own_external_surfaces() -> None:
    deploy = DEPLOY.read_text(encoding="utf-8").lower()
    for forbidden in (
        "az acr create",
        "az acr update",
        "az acr build",
        "az acr import",
        "private-endpoint create",
        "role assignment create",
        "docker ",
    ):
        assert forbidden not in deploy

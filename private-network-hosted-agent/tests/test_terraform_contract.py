import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[1]
TERRAFORM = ROOT / "infra-terraform"
CONTRACT = ROOT / "infra-bicep" / "contract"


def terraform_files() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(TERRAFORM.rglob("*.tf"))
    )


def test_terraform_inputs_match_shared_contract() -> None:
    schema = json.loads(
        (CONTRACT / "parameters.schema.json").read_text(encoding="utf-8")
    )
    tfvars_text = (TERRAFORM / "main.tfvars.json").read_text(
        encoding="utf-8"
    )
    tfvars = set(re.findall(r'^\s*"([^"]+)"\s*:', tfvars_text, re.MULTILINE))
    variables = (TERRAFORM / "variables.tf").read_text(encoding="utf-8")

    assert tfvars == set(schema["properties"])
    for name in schema["properties"]:
        assert f'variable "{name}"' in variables


def test_terraform_outputs_match_shared_contract() -> None:
    schema = json.loads(
        (CONTRACT / "outputs.schema.json").read_text(encoding="utf-8")
    )
    outputs = (TERRAFORM / "outputs.tf").read_text(encoding="utf-8")
    declared = set(re.findall(r'output "([^"]+)"', outputs))

    assert declared == set(schema["properties"])
    assert declared == set(schema["required"])


def test_terraform_preserves_security_controls() -> None:
    content = terraform_files()
    root = (TERRAFORM / "main.tf").read_text(encoding="utf-8")

    for required in (
        'publicNetworkAccess    = "Disabled"',
        "disableLocalAuth       = true",
        "public_network_access_enabled = false",
        'enforcement = "Enabled"',
        'address_prefix         = "0.0.0.0/0"',
        'next_hop_type          = "VirtualAppliance"',
        '"privatelink.cognitiveservices.azure.com"',
        '"privatelink.services.ai.azure.com"',
        '"privatelink.openai.azure.com"',
        '"privatelink.search.windows.net"',
        '"privatelink.vaultcore.azure.net"',
        'group_ids            = ["account"]',
        'group_ids            = ["searchService"]',
        'group_ids            = ["vault"]',
    ):
        assert required in content

    assert content.count('keySize = 3072') == 2
    assert 'sku_name                      = "standard"' in content
    assert 'sku                      = "Standard"' in content
    assert 'resource "azurerm_subnet_route_table_association" "agent_post_injection"' in root
    assert (
        "from = "
        "azurerm_subnet_network_security_group_association."
        "private_endpoints_post_injection" in root
    )
    assert (
        'resource "azapi_update_resource" '
        '"private_endpoint_subnet_nsg_post_injection"' in root
    )
    assert "depends_on = [module.foundry]" in root


def test_terraform_does_not_add_out_of_scope_resources() -> None:
    content = terraform_files().lower()

    for forbidden in (
        "azurerm_container_registry",
        "azurerm_storage_account",
        "azurerm_cosmosdb",
        "azurerm_bastion_host",
        "azurerm_windows_virtual_machine",
        "azurerm_application_insights",
        "azurerm_log_analytics_workspace",
    ):
        assert forbidden not in content


def test_terraform_uses_local_state_and_pinned_providers() -> None:
    providers = (TERRAFORM / "providers.tf").read_text(encoding="utf-8")

    assert 'backend "local"' in providers
    assert 'version = "= 4.80.0"' in providers
    assert 'version = "= 2.10.0"' in providers
    assert 'version = "= 3.9.0"' in providers
    assert (TERRAFORM / ".terraform.lock.hcl").is_file()


def test_subnets_use_one_serialized_azapi_path() -> None:
    root = (TERRAFORM / "main.tf").read_text(encoding="utf-8")
    network = (
        TERRAFORM / "modules/network/main.tf"
    ).read_text(encoding="utf-8")

    assert 'resource "azurerm_subnet"' not in network
    for name in (
        "firewall_subnet",
        "agent_subnet",
        "private_endpoint_subnet",
        "dns_inbound_subnet",
        "gateway_subnet",
    ):
        assert f'resource "azapi_resource" "{name}"' in network
    assert network.count(
        'type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"'
    ) == 5
    assert network.count(
        "locks                     = [azurerm_virtual_network.this.id]"
    ) == 5
    assert network.count("retry                     = local.subnet_retry") == 5
    for dependency in (
        "azapi_update_resource.vnet_private_endpoint_policy",
        "azapi_update_resource.firewall_policy_attachment",
        "azapi_resource.firewall_subnet",
        "azapi_resource.agent_subnet",
        "azapi_resource.private_endpoint_subnet",
        "azapi_resource.dns_inbound_subnet",
        "azapi_resource.gateway_subnet",
    ):
        assert f"depends_on = [{dependency}]" in network
    assert "from = module.network.azurerm_subnet.firewall" in root
    assert "to   = module.network.azapi_resource.firewall_subnet" in root


@pytest.mark.skipif(
    shutil.which("terraform") is None,
    reason="Terraform CLI is not installed",
)
def test_terraform_formats_and_validates() -> None:
    formatting = subprocess.run(
        ["terraform", "fmt", "-check", "-recursive"],
        cwd=TERRAFORM,
        capture_output=True,
        text=True,
        check=False,
    )
    assert formatting.returncode == 0, formatting.stdout + formatting.stderr

    initialization = subprocess.run(
        ["terraform", "init", "-backend=false", "-input=false"],
        cwd=TERRAFORM,
        capture_output=True,
        text=True,
        check=False,
    )
    assert initialization.returncode == 0, (
        initialization.stdout + initialization.stderr
    )

    validation = subprocess.run(
        ["terraform", "validate", "-no-color"],
        cwd=TERRAFORM,
        capture_output=True,
        text=True,
        check=False,
    )
    assert validation.returncode == 0, validation.stdout + validation.stderr

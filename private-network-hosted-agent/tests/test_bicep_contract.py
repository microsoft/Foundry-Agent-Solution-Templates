import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).parents[1]
PARAMETER_SCHEMA = ROOT / "infra-bicep/contract/parameters.schema.json"
OUTPUT_SCHEMA = ROOT / "infra-bicep/contract/outputs.schema.json"


def schema_accepts(schema_path: Path, instance: dict[str, object]) -> bool:
    escaped_schema_path = str(schema_path).replace("'", "''")
    command = (
        "$json = [Console]::In.ReadToEnd(); "
        f"$valid = $json | Test-Json -SchemaFile '{escaped_schema_path}'; "
        "if (-not $valid) { exit 1 }"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        input=json.dumps(instance),
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def build_bicep_template(path: Path) -> dict[str, object]:
    escaped_path = str(path).replace("'", "''")
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-Command",
            f"& az bicep build --file '{escaped_path}' --stdout",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_main_parameters_is_arm_json() -> None:
    parameters = json.loads(
        (ROOT / "infra-bicep/main.parameters.json").read_text(encoding="utf-8")
    )
    assert parameters["$schema"].endswith("deploymentParameters.json#")
    assert "connectivityMode" in parameters["parameters"]


def test_regions_default_to_west_us_3() -> None:
    subscription = (ROOT / "infra-bicep/main.bicep").read_text(encoding="utf-8")
    main = (ROOT / "infra-bicep/solution.bicep").read_text(encoding="utf-8")
    parameters = json.loads(
        (ROOT / "infra-bicep/main.parameters.json").read_text(encoding="utf-8")
    )
    contract = json.loads(
        (ROOT / "infra-bicep/contract/parameters.schema.json").read_text(
            encoding="utf-8"
        )
    )
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")
    deploy = (ROOT / "scripts/deploy.ps1").read_text(encoding="utf-8")
    deployment = (ROOT / "docs/deployment.md").read_text(encoding="utf-8")
    configuration = (ROOT / "docs/configuration.md").read_text(encoding="utf-8")

    assert "param location string = 'westus3'" in subscription
    assert "param searchLocation string = 'westus3'" in main
    assert (
        parameters["parameters"]["location"]["value"]
        == "${AZURE_LOCATION=westus3}"
    )
    assert (
        parameters["parameters"]["searchLocation"]["value"]
        == "${AZURE_SEARCH_LOCATION=westus3}"
    )
    assert contract["properties"]["location"]["default"] == "westus3"
    assert contract["properties"]["searchLocation"]["default"] == "westus3"
    assert "[string]$Location = 'westus3'" in preflight
    assert "[string]$SearchLocation = 'westus3'" in preflight
    assert "[string]$Location = 'westus3'" in deploy
    assert "[string]$SearchLocation = 'westus3'" in deploy
    assert "`westus3`" in deployment
    assert "configuration.md#region-and-capacity-selection" in deployment
    assert "`westus3`" in configuration


def test_bicep_has_no_secret_outputs() -> None:
    bicep = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "infra-bicep").rglob("*.bicep")
    ).lower()
    assert "output s2ssharedkey" not in bicep
    assert "output secret" not in bicep
    assert "administratorlogin" not in bicep
    assert "administratorloginpassword" not in bicep


def test_model_is_regional_standard_only() -> None:
    foundry = (ROOT / "infra-bicep/modules/foundry.bicep").read_text(encoding="utf-8")
    assert "name: 'Standard'" in foundry
    assert "GlobalStandard" not in foundry
    assert "DataZoneStandard" not in foundry


def test_runtime_identity_roles_are_principal_keyed() -> None:
    for name in (
        "key-role-assignment.bicep",
        "key-vault-role-assignment.bicep",
        "account-role-assignment.bicep",
    ):
        content = (ROOT / "infra-bicep/modules" / name).read_text(encoding="utf-8")
        assert "guid(" in content
        assert "principalId" in content


def test_cmk_roles_are_service_specific_and_least_privilege() -> None:
    modules = ROOT / "infra-bicep/modules"
    foundry = (modules / "foundry.bicep").read_text(encoding="utf-8")
    key_vault = (modules / "key-vault.bicep").read_text(encoding="utf-8")
    key_role = (modules / "key-role-assignment.bicep").read_text(encoding="utf-8")
    vault_role = (modules / "key-vault-role-assignment.bicep").read_text(
        encoding="utf-8"
    )
    search = (modules / "search.bicep").read_text(encoding="utf-8")
    validator = (ROOT / "scripts/validate-rbac.ps1").read_text(encoding="utf-8")

    assert "accountKeyVaultRole" in foundry
    assert "projectKeyVaultRole" in foundry
    assert "12338af0-0e69-4776-bea7-57ae8d297424" in foundry
    assert "principalId: account.identity.principalId" in foundry
    assert "principalId: project.identity.principalId" in foundry
    assert "identityClientId: foundryCmkIdentityClientId" in foundry
    assert "module foundryKeyRole './key-role-assignment.bicep'" in key_vault
    assert "principalId: foundryCmkIdentity.properties.principalId" in key_vault
    assert "module searchKeyRole './key-role-assignment.bicep'" in search
    assert "scope: key" in key_role
    assert "scope: keyVault" in vault_role
    assert "'AZURE_AI_ACCOUNT_IDENTITY_PRINCIPAL_ID'" in validator
    assert "'AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID'" in validator
    assert "Unexpected '$($check.Role)'" not in validator


def test_private_endpoint_nsg_allows_only_managed_https_ingress() -> None:
    template = build_bicep_template(ROOT / "infra-bicep/modules/network.bicep")
    resources = template["resources"]
    expected_destination = "[parameters('privateEndpointSubnetPrefix')]"

    assert resources["privateEndpointP2sRule"]["condition"] == (
        "[equals(parameters('connectivityMode'), 'pointToSite')]"
    )
    assert resources["privateEndpointP2sRule"]["properties"] == {
        "priority": 100,
        "direction": "Inbound",
        "access": "Allow",
        "protocol": "Tcp",
        "sourcePortRange": "*",
        "destinationPortRange": "443",
        "sourceAddressPrefix": "[parameters('p2sAddressPool')]",
        "destinationAddressPrefix": expected_destination,
    }
    assert resources["privateEndpointVnetRule"]["properties"] == {
        "priority": 110,
        "direction": "Inbound",
        "access": "Allow",
        "protocol": "Tcp",
        "sourcePortRange": "*",
        "destinationPortRange": "443",
        "sourceAddressPrefix": "VirtualNetwork",
        "destinationAddressPrefix": expected_destination,
    }
    assert resources["privateEndpointDenyInboundRule"]["properties"] == {
        "priority": 120,
        "direction": "Inbound",
        "access": "Deny",
        "protocol": "*",
        "sourcePortRange": "*",
        "destinationPortRange": "*",
        "sourceAddressPrefix": "*",
        "destinationAddressPrefix": expected_destination,
    }
    assert set(resources["privateEndpointDenyInboundRule"]["dependsOn"]) == {
        "privateEndpointNsg",
        "privateEndpointVnetRule",
    }
    assert set(resources["privateEndpointP2sRule"]["dependsOn"]) == {
        "privateEndpointNsg",
        "privateEndpointDenyInboundRule",
    }

    validation = (ROOT / "scripts/validate-network.ps1").read_text(
        encoding="utf-8"
    )
    assert "$privateEndpointNsg.properties.securityRules" in validation
    assert "Assert-ManagedInboundNsgRule" in validation
    assert "$Rules | Where-Object { $_.name -eq $Name }" in validation
    assert "$privateEndpointRules.Count" not in validation


def test_network_zone_contract_matches_connectivity_modes() -> None:
    network = (ROOT / "infra-bicep/modules/network.bicep").read_text(encoding="utf-8")
    connectivity = (ROOT / "infra-bicep/modules/connectivity.bicep").read_text(
        encoding="utf-8"
    )
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")
    configuration = (ROOT / "docs/configuration.md").read_text(encoding="utf-8")

    assert "zones:" not in network
    assert "zones:" in connectivity
    assert "'1'\n    '2'\n    '3'" in connectivity
    assert "name: 'VpnGw2AZ'" in connectivity
    assert "$ConnectivityMode -in @('pointToSite', 'siteToSite')" in preflight
    assert "availabilityZoneMappings" in preflight
    assert "/locations?api-version=2022-12-01" in preflight
    assert "vnetPeering" in configuration
    assert "Azure Firewall Availability Zones" in configuration


def test_vnet_peering_requires_canonical_remote_vnet_id() -> None:
    connectivity = (ROOT / "infra-bicep/modules/connectivity.bicep").read_text(
        encoding="utf-8"
    )
    schema = json.loads(PARAMETER_SCHEMA.read_text(encoding="utf-8"))
    preflight = (ROOT / "scripts/preflight.ps1").read_text(encoding="utf-8")

    assert "length(remoteVnetParts) == 9" in connectivity
    assert "remoteVnetResourceIdIsCanonical" in connectivity
    assert "validatedRemoteVnetResourceId" in connectivity
    assert "Test-CanonicalVirtualNetworkResourceId" in preflight
    assert (
        "Microsoft\\.Network/virtualNetworks/[^/]+$"
        in schema["properties"]["remoteVnetResourceId"]["pattern"]
    )


def test_existing_acr_connection_is_optional_and_connection_only() -> None:
    main = (ROOT / "infra-bicep/solution.bicep").read_text(encoding="utf-8")
    parameters = json.loads(
        (ROOT / "infra-bicep/main.parameters.json").read_text(encoding="utf-8")
    )["parameters"]
    connection = (
        ROOT / "infra-bicep/modules/container-registry-connection.bicep"
    ).read_text(encoding="utf-8")

    assert "containerRegistryInputsArePaired" in main
    assert "fail(" in main
    assert "hasExistingContainerRegistry" in main
    assert parameters["containerRegistryResourceId"]["value"].endswith("=}")
    assert parameters["containerRegistryEndpoint"]["value"].endswith("=}")
    assert "category: 'ContainerRegistry'" in connection
    assert "authType: 'ManagedIdentity'" in connection
    assert "target: containerRegistryEndpoint" in connection
    assert "ResourceId: containerRegistryResourceId" in connection

    forbidden = (
        "Microsoft.ContainerRegistry/registries@",
        "Microsoft.Network/privateEndpoints@",
        "Microsoft.Network/privateDnsZones@",
        "Microsoft.Authorization/roleAssignments@",
    )
    assert all(resource_type not in connection for resource_type in forbidden)


def test_parameter_schema_matches_and_validates_public_entry_point() -> None:
    main = (ROOT / "infra-bicep/main.bicep").read_text(encoding="utf-8")
    parameter_file = json.loads(
        (ROOT / "infra-bicep/main.parameters.json").read_text(encoding="utf-8")
    )["parameters"]
    schema = json.loads(PARAMETER_SCHEMA.read_text(encoding="utf-8"))
    declarations = {
        match.group("name"): (
            match.group("type"),
            match.group("default") is None,
        )
        for match in re.finditer(
            r"^param\s+(?P<name>\w+)\s+"
            r"(?P<type>string|array|bool|int)"
            r"(?P<default>\s*=\s*.+)?$",
            main,
            re.MULTILINE,
        )
    }

    assert set(schema["properties"]) == set(parameter_file) == set(declarations)
    assert set(schema["required"]) == {
        name for name, (_, required) in declarations.items() if required
    }
    schema_types = {
        "string": "string",
        "array": "array",
        "bool": "boolean",
        "int": "integer",
    }
    for name, (bicep_type, _) in declarations.items():
        assert schema["properties"][name]["type"] == schema_types[bicep_type]
    assert schema["properties"]["containerRegistryResourceId"]["pattern"] == (
        "^$|^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/"
        r"Microsoft\.ContainerRegistry/registries/[^/]+$"
    )
    assert schema["properties"]["containerRegistryEndpoint"]["pattern"] == (
        r"^$|^[a-z0-9-]+\.azurecr\.io$"
    )
    assert len(schema["allOf"]) == 1
    assert (
        schema["allOf"][0]["if"]["properties"]["connectivityMode"]["const"]
        == "vnetPeering"
    )

    valid_parameters = {
        name: definition["default"]
        for name, definition in schema["properties"].items()
        if "default" in definition
    }
    valid_parameters.update(
        environmentName="fpha-contract",
        deploymentPrincipalObjectId="11111111-1111-1111-1111-111111111111",
        p2sTenantId="77777777-7777-7777-7777-777777777777",
    )
    assert schema_accepts(PARAMETER_SCHEMA, valid_parameters)
    assert schema_accepts(
        PARAMETER_SCHEMA,
        dict(
            valid_parameters,
            containerRegistryResourceId=(
                "/subscriptions/11111111-1111-1111-1111-111111111111/"
                "resourceGroups/rg-enterprise/providers/"
                "Microsoft.ContainerRegistry/registries/enterpriseacr"
            ),
            containerRegistryEndpoint="enterpriseacr-abc123.azurecr.io",
        ),
    )
    assert schema_accepts(
        PARAMETER_SCHEMA,
        dict(
            valid_parameters,
            containerRegistryResourceId="",
            containerRegistryEndpoint="enterpriseacr.azurecr.io",
        ),
    )
    assert schema_accepts(
        PARAMETER_SCHEMA,
        dict(
            valid_parameters,
            containerRegistryResourceId=(
                "/subscriptions/11111111-1111-1111-1111-111111111111/"
                "resourceGroups/rg-enterprise/providers/"
                "Microsoft.ContainerRegistry/registries/enterpriseacr"
            ),
            containerRegistryEndpoint="",
        ),
    )
    assert not schema_accepts(
        PARAMETER_SCHEMA,
        dict(valid_parameters, unexpectedParameter=True),
    )
    assert not schema_accepts(
        PARAMETER_SCHEMA,
        dict(
            valid_parameters,
            connectivityMode="vnetPeering",
            remoteVnetResourceId=(
                "/subscriptions/11111111-1111-1111-1111-111111111111/"
                "resourceGroups/rg-network/providers/Microsoft.Network/"
                "virtualNetworks/remote-vnet/subnets/default"
            ),
        ),
    )
    assert not schema_accepts(
        PARAMETER_SCHEMA,
        dict(
            valid_parameters,
            connectivityMode="vnetPeering",
            remoteVnetResourceId="",
        ),
    )
def test_output_schema_matches_and_validates_public_outputs() -> None:
    main = (ROOT / "infra-bicep/main.bicep").read_text(encoding="utf-8")
    schema = json.loads(OUTPUT_SCHEMA.read_text(encoding="utf-8"))
    declarations = {
        match.group("name"): match.group("type")
        for match in re.finditer(
            r"^output\s+(?P<name>\w+)\s+(?P<type>\w+)\s*=",
            main,
            re.MULTILINE,
        )
    }

    assert set(schema["properties"]) == set(schema["required"]) == set(declarations)
    assert set(declarations.values()) == {"string"}
    for definition in schema["properties"].values():
        assert definition["type"] == "string"

    valid_outputs = {name: "contract-value" for name in declarations}
    valid_outputs.update(
        CONNECTIVITY_MODE="pointToSite",
        FOUNDRY_PROJECT_ENDPOINT="https://project.services.ai.azure.com/",
        AZURE_AI_PROJECT_ENDPOINT="https://project.services.ai.azure.com/",
        AZURE_SEARCH_ENDPOINT="https://search.search.windows.net/",
        AZURE_KEY_VAULT_URI="https://vault.vault.azure.net/",
        AZURE_CONTAINER_REGISTRY_RESOURCE_ID="",
        AZURE_CONTAINER_REGISTRY_ENDPOINT="",
        AZURE_CONTAINER_REGISTRY_CONNECTION_NAME="",
        AZURE_AI_PROJECT_ACR_CONNECTION_NAME="",
    )
    assert schema_accepts(OUTPUT_SCHEMA, valid_outputs)
    assert not schema_accepts(
        OUTPUT_SCHEMA,
        dict(valid_outputs, unexpectedOutput="not-public"),
    )
    invalid_outputs = valid_outputs.copy()
    invalid_outputs.pop("AZURE_AI_PROJECT_ID")
    assert not schema_accepts(OUTPUT_SCHEMA, invalid_outputs)


def test_subscription_entry_point_owns_only_generated_resource_group() -> None:
    main = (ROOT / "infra-bicep/main.bicep").read_text(encoding="utf-8")
    parameters = json.loads(
        (ROOT / "infra-bicep/main.parameters.json").read_text(encoding="utf-8")
    )["parameters"]

    assert "targetScope = 'subscription'" in main
    assert "var resourceGroupName = 'rg-${environmentName}'" in main
    assert "param resourceGroupName" not in main
    assert "resourceGroupOwnership" not in main
    assert "resource managedResourceGroup" in main
    assert "if (createResourceGroup)" not in main
    assert "'resource-group-ownership': 'template-created'" in main
    assert "scope: resourceGroup(resourceGroupName)" in main
    assert "module solution './solution.bicep'" in main
    assert "resourceGroupName" not in parameters
    assert "resourceGroupOwnership" not in parameters
    assert "AZURE_RESOURCE_GROUP_OWNERSHIP" not in main

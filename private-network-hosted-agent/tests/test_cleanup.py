import json
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[1]
CLEANUP = ROOT / "scripts" / "cleanup.ps1"
ENVIRONMENT = "fpha-src-cleanup"
SUBSCRIPTION = "11111111-1111-1111-1111-111111111111"
RESOURCE_GROUP = f"rg-{ENVIRONMENT}"
ACCOUNT = "aif-cleanup"
PROJECT = "proj-cleanup"
VNET = "vnet-cleanup"


def run_powershell(script: str, tmp_path: Path) -> subprocess.CompletedProcess[str]:
    path = tmp_path / "cleanup-test.ps1"
    path.write_text(script, encoding="utf-8")
    return subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def environment_values() -> str:
    values = {
        "AZURE_SUBSCRIPTION_ID": SUBSCRIPTION,
        "AZURE_RESOURCE_GROUP": RESOURCE_GROUP,
        "AZURE_AI_ACCOUNT_NAME": ACCOUNT,
        "AZURE_AI_ACCOUNT_ID": (
            f"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/"
            f"providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}"
        ),
        "AZURE_AI_PROJECT_NAME": PROJECT,
        "AZURE_AI_PROJECT_ID": (
            f"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/"
            f"providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}/"
            f"projects/{PROJECT}"
        ),
        "AZURE_LOCATION": "westus3",
        "AZURE_VNET_ID": (
            f"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/"
            f"providers/Microsoft.Network/virtualNetworks/{VNET}"
        ),
        "CONNECTIVITY_MODE": "pointToSite",
        "FPHA_DEPLOYMENT_MODE": "Source",
    }
    return json.dumps(values, separators=(",", ":"))


def test_cleanup_public_parameter_and_safety_contract() -> None:
    cleanup = CLEANUP.read_text(encoding="utf-8")

    assert "[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]" in cleanup
    assert "[string]$EnvironmentName" in cleanup
    assert "[switch]$Force" in cleanup
    assert "[switch]$RemoveLocalEnvironment" in cleanup
    for forbidden in (
        "[string]$SubscriptionId",
        "[string]$ResourceGroupName",
        "[string]$AccountName",
        "[string]$ProjectName",
        "[string]$VnetName",
        "[int]$Timeout",
        "[int]$PollInterval",
    ):
        assert forbidden not in cleanup.split("Set-StrictMode", maxsplit=1)[0]

    assert "$salTimeout = [TimeSpan]::FromMinutes(30)" in cleanup
    assert "FPHA_CLEANUP_ACCOUNT_PURGE_REQUESTED" in cleanup
    assert "FPHA_CLEANUP_ACCOUNT_DELETION_STARTED" not in cleanup
    assert "FPHA_CLEANUP_ACCOUNT_PURGED" not in cleanup
    assert "$accountAbsenceConfirmationCount = 3" in cleanup
    assert "'cognitiveservices', 'account', 'show-deleted'" in cleanup
    assert "'cognitiveservices', 'account', 'list-deleted'" not in cleanup
    assert "-not $accountWasDeleted" not in cleanup
    assert "was not found under account" not in cleanup
    assert "network', 'vnet', 'peering', 'delete'" in cleanup
    assert "Assert-RemotePeeringTargetsLocalVnet" in cleanup
    assert "network', 'vnet', 'delete'" not in cleanup
    assert "@('env', 'remove', $EnvironmentName, '--force')" in cleanup
    assert "serviceAssociationLinks" in cleanup
    assert "serviceAssociationLinks', 'delete'" not in cleanup
    assert "serviceAssociationLinks', 'patch'" not in cleanup
    assert cleanup.index("Remove-AndPurgeFoundryAccount") < cleanup.index(
        "Wait-ForAgentSubnetSalRemoval"
    )
    assert cleanup.rindex("Wait-ForAgentSubnetSalRemoval") < cleanup.rindex(
        "Remove-RemotePeering"
    )
    assert cleanup.rindex("Remove-RemotePeering") < cleanup.rindex(
        "Remove-AgentSubnetAssociations"
    )
    assert cleanup.rindex("Remove-AgentSubnetAssociations") < cleanup.rindex(
        "-Stage \"Delete resource group"
    )


def test_cleanup_rejects_environment_name_ambiguity(tmp_path: Path) -> None:
    cleanup_path = str(CLEANUP).replace("'", "''")
    script = f"""
function azd {{
    $global:LASTEXITCODE = 0
    if (($args -join ' ') -like 'env list*') {{
        '[{{"Name":"{ENVIRONMENT}"}}]'
        return
    }}
    throw 'Unexpected azd call.'
}}
function az {{ throw 'Azure must not be queried for an ambiguous environment.' }}
& '{cleanup_path}' -EnvironmentName '{ENVIRONMENT}' -WhatIf
"""
    result = run_powershell(script, tmp_path)

    assert result.returncode != 0
    assert "exists in both project directories" in result.stderr


def test_cleanup_what_if_is_read_only(tmp_path: Path) -> None:
    cleanup_path = str(CLEANUP).replace("'", "''")
    values = environment_values().replace("'", "''")
    script = f"""
$script:mutations = @()
function azd {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -like 'env list*') {{
        if ($PWD.Path -like '*existing-private-acr') {{ '[]' }}
        else {{ '[{{"Name":"{ENVIRONMENT}"}}]' }}
        return
    }}
    if ($joined -like 'env get-values*') {{ '{values}'; return }}
    $script:mutations += "azd $joined"
    throw "Unexpected azd mutation: $joined"
}}
function az {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -match '(?i)( delete | purge | update )') {{
        $script:mutations += "az $joined"
        throw "Mutation attempted during WhatIf: $joined"
    }}
    if ($joined -like 'account show*') {{ '{{}}'; return }}
    if ($joined -like 'cognitiveservices account show*') {{
        '{{"id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}","systemData":{{"createdAt":"2026-08-06T01:02:03Z"}},"tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        return
    }}
    if ($joined -like 'group show*') {{
        '{{"tags":{{"resource-group-ownership":"template-created","solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        return
    }}
    if ($joined -like 'network vnet show*') {{
        '{{"id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/{VNET}","tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        return
    }}
    if ($joined -like 'rest --method get*' -and $joined -like '*projects?api-version=*') {{
        '{{"value":[{{"name":"{ACCOUNT}/{PROJECT}","id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}/projects/{PROJECT}","tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}]}}'
        return
    }}
    throw "Unexpected az call: $joined"
}}
& '{cleanup_path}' -EnvironmentName '{ENVIRONMENT}' -WhatIf
if ($script:mutations.Count -ne 0) {{ throw 'WhatIf performed a mutation.' }}
"""
    result = run_powershell(script, tmp_path)

    assert result.returncode == 0, result.stderr
    assert "What if:" in result.stdout
    assert "[PLAN] Dedicated resource group" in result.stdout


def test_cleanup_returns_immediately_when_group_and_residuals_are_absent(
    tmp_path: Path,
) -> None:
    cleanup_path = str(CLEANUP).replace("'", "''")
    values = environment_values().replace("'", "''")
    script = f"""
function NotFound {{
    $global:LASTEXITCODE = 1
    '404 ResourceNotFound'
}}
function Start-Sleep {{ throw 'Cleanup must not wait when no Azure residual exists.' }}
function azd {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -like 'env list*') {{
        if ($PWD.Path -like '*existing-private-acr') {{ '[]' }}
        else {{ '[{{"Name":"{ENVIRONMENT}"}}]' }}
        return
    }}
    if ($joined -like 'env get-values*') {{ '{values}'; return }}
    throw "Unexpected azd call: $joined"
}}
function az {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -like 'account show*') {{ '{{}}'; return }}
    if ($joined -like 'group show*') {{ NotFound; return }}
    if ($joined -like 'cognitiveservices account show-deleted*') {{
        NotFound
        return
    }}
    throw "Unexpected az call: $joined"
}}
& '{cleanup_path}' -EnvironmentName '{ENVIRONMENT}' -Force -Confirm:$false
"""
    result = run_powershell(script, tmp_path)

    assert result.returncode == 0, result.stderr
    assert "is already absent; no soft-deleted Foundry account" in result.stdout
    assert "[VERIFYING]" not in result.stdout
    assert "Type the former resource group name" not in result.stdout


@pytest.mark.parametrize("soft_delete_visible", [True, False])
def test_cleanup_executes_order_and_deletes_local_state_last(
    tmp_path: Path, soft_delete_visible: bool
) -> None:
    cleanup_path = str(CLEANUP).replace("'", "''")
    stale_values = json.loads(environment_values())
    stale_values.update(
        {
            "FPHA_CLEANUP_ACCOUNT_INCARNATION": (
                f"{ACCOUNT}@2026-07-01T00:00:00Z"
            ),
            "FPHA_CLEANUP_ACCOUNT_PURGE_REQUESTED": (
                f"{ACCOUNT}@2026-07-01T00:00:00Z"
            ),
        }
    )
    values = json.dumps(stale_values, separators=(",", ":")).replace("'", "''")
    script = f"""
$global:testCommands = [Collections.Generic.List[string]]::new()
$global:testProjectDeleted = $false
$global:testAccountDeleted = $false
$global:testAccountPurged = $false
$global:testGroupDeleteRequested = $false
$global:testGroupPollCount = 0
$global:testSoftDeleteVisible = ${str(soft_delete_visible).lower()}
function Record([string]$Value) {{ $global:testCommands.Add($Value) }}
function Start-Sleep {{ }}
function NotFound {{
    $global:LASTEXITCODE = 1
    '404 ResourceNotFound'
}}
function azd {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -like 'env list*') {{
        if ($PWD.Path -like '*existing-private-acr') {{ '[]' }}
        else {{ '[{{"Name":"{ENVIRONMENT}"}}]' }}
        return
    }}
    if ($joined -like 'env get-values*') {{ '{values}'; return }}
    if ($joined -like 'env set*') {{ Record "azd:$joined"; return }}
    if ($joined -like 'env remove*') {{ Record "azd:$joined"; return }}
    throw "Unexpected azd call: $joined"
}}
function az {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -like 'account show*') {{ '{{}}'; return }}
    if ($joined -like 'group show*') {{
        '{{"tags":{{"resource-group-ownership":"template-created","solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        return
    }}
    if ($joined -like 'group exists*') {{
        if ($global:testGroupDeleteRequested) {{
            $global:testGroupPollCount++
        }}
        if ($global:testGroupPollCount -ge 3) {{ 'false' }} else {{ 'true' }}
        return
    }}
    if ($joined -like 'group delete*') {{
        Record "az:$joined"
        $global:testGroupDeleteRequested = $true
        return
    }}
    if ($joined -like 'resource list*') {{
        if ($global:testGroupPollCount -eq 0) {{
            '[{{"name":"vnet-cleanup","type":"Microsoft.Network/virtualNetworks"}},{{"name":"gateway-cleanup","type":"Microsoft.Network/virtualNetworkGateways"}}]'
        }}
        elseif ($global:testGroupPollCount -eq 1) {{
            '[{{"name":"gateway-cleanup","type":"Microsoft.Network/virtualNetworkGateways"}}]'
        }}
        else {{
            '[]'
        }}
        return
    }}
    if ($joined -like 'cognitiveservices account show-deleted*') {{
        if ($global:testAccountDeleted -and
            -not $global:testAccountPurged -and
            $global:testSoftDeleteVisible) {{
            '{{"name":"{ACCOUNT}","location":"westus3","resourceGroup":"{RESOURCE_GROUP}"}}'
        }} else {{ NotFound }}
        return
    }}
    if ($joined -like 'cognitiveservices account show*') {{
        if ($global:testAccountDeleted) {{ NotFound }}
        else {{
            '{{"name":"{ACCOUNT}","id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}","systemData":{{"createdAt":"2026-08-06T01:02:03Z"}},"tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        }}
        return
    }}
    if ($joined -like 'cognitiveservices account delete*') {{
        Record "az:$joined"
        $global:testAccountDeleted = $true
        return
    }}
    if ($joined -like 'cognitiveservices account purge*') {{
        Record "az:$joined"
        $global:testAccountPurged = $true
        return
    }}
    if ($joined -like 'network vnet subnet show*') {{
        '{{"serviceAssociationLinks":[]}}'
        return
    }}
    if ($joined -like 'network vnet show*') {{
        '{{"id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/{VNET}","tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}'
        return
    }}
    if ($joined -like 'network vnet subnet update*') {{
        Record "az:$joined"
        '{{}}'
        return
    }}
    if ($joined -like 'rest --method get*') {{
        $url = [string]$args[([Array]::IndexOf($args, '--url') + 1)]
        if ($url.Contains('/capabilityHosts?api-version=')) {{
            '{{"value":[]}}'
            return
        }}
        if ($url.Contains('/projects?api-version=')) {{
            if ($global:testProjectDeleted) {{ '{{"value":[]}}' }}
            else {{
                '{{"value":[{{"name":"{ACCOUNT}/{PROJECT}","id":"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/{ACCOUNT}/projects/{PROJECT}","tags":{{"solution-template":"foundry-private-hosted-agent","azd-env-name":"{ENVIRONMENT}"}}}}]}}'
            }}
            return
        }}
        if ($url.Contains('/projects/{PROJECT}?api-version=')) {{
            if ($global:testProjectDeleted) {{ NotFound }}
            else {{ '{{"name":"{PROJECT}"}}' }}
            return
        }}
    }}
    if ($joined -like 'rest --method delete*') {{
        $url = [string]$args[([Array]::IndexOf($args, '--url') + 1)]
        Record "az:$joined"
        if ($url.Contains('/projects/{PROJECT}?api-version=')) {{
            $global:testProjectDeleted = $true
        }}
        return
    }}
    throw "Unexpected az call: $joined"
}}
& '{cleanup_path}' -EnvironmentName '{ENVIRONMENT}' -Force `
    -RemoveLocalEnvironment -Confirm:$false | Out-Null
'COMMANDS=' + ($global:testCommands | ConvertTo-Json -Compress)
"""
    result = run_powershell(script, tmp_path)

    assert result.returncode == 0, result.stderr
    commands_line = next(
        line for line in result.stdout.splitlines() if line.startswith("COMMANDS=")
    )
    commands = json.loads(commands_line.removeprefix("COMMANDS="))
    joined = "\n".join(commands)
    project_delete = joined.index("rest --method delete")
    account_delete = joined.index("cognitiveservices account delete")
    subnet_update = joined.index("network vnet subnet update")
    group_delete = joined.index("group delete")
    local_delete = joined.index("azd:env remove")

    assert project_delete < account_delete < subnet_update
    assert subnet_update < group_delete < local_delete
    if soft_delete_visible:
        purge = joined.index("cognitiveservices account purge")
        assert account_delete < purge < subnet_update
        assert joined.count("cognitiveservices account purge") == 1
    else:
        assert "cognitiveservices account purge" not in joined
    assert joined.count("network vnet subnet update") == 3
    assert "[PROGRESS] Deleted 1 resource(s)" in result.stdout
    assert "Microsoft.Network/virtualNetworks/vnet-cleanup" in result.stdout
    assert "[REMAINING] 1 resource(s)" in result.stdout
    assert "Microsoft.Network/virtualNetworkGateways/gateway-cleanup" in result.stdout

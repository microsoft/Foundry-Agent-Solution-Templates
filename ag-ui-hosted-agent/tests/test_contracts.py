"""Offline contracts between azure.yaml, the infrastructure layer and the code."""

import json
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = yaml.safe_load((ROOT / "azure.yaml").read_text())
SERVICES = MANIFEST["services"]


def test_agent_name_matches_everywhere():
    name = SERVICES["claims-triage"]["name"]
    assert f"param agentName string = '{name}'" in (ROOT / "infra/app.bicep").read_text()


def test_agent_runs_the_entry_point_with_pinned_dependencies():
    agent = SERVICES["claims-triage"]
    assert (ROOT / agent["project"] / agent["codeConfiguration"]["entryPoint"]).is_file()
    for project in ("src/agent", "src/gateway"):
        for line in (ROOT / project / "requirements.txt").read_text().split():
            assert "==" in line, f"{project}: pin {line} so remote builds match local tests"


def test_escalation_requires_approval():
    source = (ROOT / "src/agent/main.py").read_text()
    assert '@tool(approval_mode="always_require")\ndef escalate_claim' in source


def test_prompt_capture_is_off():
    env = {e["name"]: e["value"] for e in SERVICES["claims-triage"]["environmentVariables"]}
    assert env["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] == "false"


def test_every_parameter_has_a_producer():
    params = json.loads((ROOT / "infra/app.parameters.json").read_text())["parameters"]
    produced = {
        "AZURE_ENV_NAME",
        "AZURE_LOCATION",
        "AZURE_FOUNDRY_RESOURCE_GROUP",
        "AZURE_AI_ACCOUNT_NAME",
        "AZURE_AI_PROJECT_NAME",
        "FOUNDRY_PROJECT_ENDPOINT",
    }
    for value in params.values():
        for var, default in re.findall(r"\$\{(\w+)(=[^}]*)?\}", value["value"]):
            assert var in produced or default, f"{var} has no producer or default"


def test_gateway_is_internal_and_web_requires_sign_in():
    bicep = (ROOT / "infra/resources.bicep").read_text()
    assert "ingress: { external: false, targetPort: 8000" in bicep
    assert "unauthenticatedClientAction: 'RedirectToLoginPage'" in bicep
    assert "clientSecretSettingName: 'override-use-mi-fic-assertion-client-id'" in bicep


def test_container_apps_are_tagged_for_azd():
    bicep = (ROOT / "infra/resources.bicep").read_text()
    for service in ("gateway", "web"):
        assert SERVICES[service]["host"] == "containerapp"
        assert f"'azd-service-name': '{service}'" in bicep

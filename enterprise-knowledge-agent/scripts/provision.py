from __future__ import annotations

import json
import os
import subprocess
import sys
import hashlib
import re
from copy import deepcopy
from pathlib import Path
from urllib.parse import quote

import requests
from azure.identity import AzureCliCredential
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from template_config import canonical_digest, load_fragments, toolbox_document, validate_cross_path
from ownership import write_ownership

ROOT = Path(__file__).resolve().parents[1]
API_VERSION = "2026-08-01-preview"
SEARCH_SCOPE = "https://search.azure.com/.default"
INDEX_NAME = "enterprise-documents"
KB_NAME = "enterprise-knowledge-kb"
SEMANTIC_NAME = "enterprise-semantic"
INDEX_SOURCE_NAME = "enterprise-documents-ks"
LEARN_SOURCE_NAME = "microsoft-learn-ks"


def ownership_path() -> Path:
    return ROOT / ".azure" / require("AZURE_ENV_NAME") / "enterprise-knowledge-ownership.json"


def scoped_name(base: str) -> str:
    environment = require("AZURE_ENV_NAME")
    normalized = re.sub(r"[^a-z0-9-]+", "-", environment.casefold()).strip("-")
    suffix = hashlib.sha256(environment.encode()).hexdigest()[:8]
    return f"{base}-{normalized[:20]}-{suffix}"


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable {name} is missing")
    return value


class SearchClient:
    def __init__(self, endpoint: str) -> None:
        token = AzureCliCredential().get_token(SEARCH_SCOPE).token
        self.endpoint = endpoint.rstrip("/")
        self.headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        # Provisioning PUT/DELETE and document mergeOrUpload POSTs are
        # idempotent, including when the service resets an applied request.
        retry = Retry(
            total=4,
            backoff_factor=1,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=frozenset({"GET", "PUT", "POST", "DELETE"}),
            respect_retry_after_header=True,
            raise_on_status=False,
        )
        self.session = requests.Session()
        adapter = HTTPAdapter(max_retries=retry)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

    def request(self, method: str, path: str, body: dict | None = None, expected: tuple[int, ...] = (200, 201, 204)) -> dict:
        url = f"{self.endpoint}/{path}?api-version={API_VERSION}"
        response = self.session.request(method, url, headers=self.headers, json=body, timeout=180)
        if response.status_code not in expected:
            raise RuntimeError(f"Search {method} {path} failed ({response.status_code}): {response.text[:1000]}")
        return response.json() if response.content else {}


def run(*args: str, capture: bool = False) -> str:
    process = subprocess.run(args, cwd=ROOT, check=True, text=True, capture_output=capture)
    return process.stdout.strip() if capture else ""


def azd_set(name: str, value: str) -> None:
    run("azd", "env", "set", name, value)


def azd_get(name: str) -> str:
    result = subprocess.run(["azd", "env", "get-value", name], cwd=ROOT, text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def knowledge_base_endpoint(client: SearchClient) -> str:
    return f"{client.endpoint}/knowledgebases/{scoped_name(KB_NAME)}/mcp?api-version={API_VERSION}"


def scope_knowledge_sources(sources: list[dict]) -> list[dict]:
    scoped = deepcopy(sources)
    for source in scoped:
        original_name = source["name"]
        source["name"] = scoped_name(original_name)
        if original_name == INDEX_SOURCE_NAME:
            parameters = source["searchIndexParameters"]
            parameters["searchIndexName"] = scoped_name(INDEX_NAME)
            parameters["semanticConfigurationName"] = scoped_name(SEMANTIC_NAME)
    return scoped


def create_search_objects(client: SearchClient, sources: list[dict]) -> list[dict]:
    index_name = scoped_name(INDEX_NAME)
    semantic_name = scoped_name(SEMANTIC_NAME)
    knowledge_base_name = scoped_name(KB_NAME)
    scoped_sources = scope_knowledge_sources(sources)
    # Journal the environment-scoped targets before the first mutation so a
    # partial provision can be cleaned up and endpoint mismatches fail closed.
    write_ownership(
        ownership_path(), client.endpoint, knowledge_base_name,
        [item["name"] for item in scoped_sources], index_name, [
            item.get("searchIndexParameters", {}).get("searchIndexName")
            for item in sources
            if item.get("kind") == "searchIndex" and item["name"] != INDEX_SOURCE_NAME
        ])
    index = {
        "name": index_name,
        "fields": [
            {"name": "id", "type": "Edm.String", "key": True, "filterable": True},
            {"name": "title", "type": "Edm.String", "searchable": True, "retrievable": True},
            {"name": "content", "type": "Edm.String", "searchable": True, "retrievable": True},
            {"name": "source_url", "type": "Edm.String", "retrievable": True},
        ],
        "semantic": {"configurations": [{"name": semantic_name, "prioritizedFields": {"titleField": {"fieldName": "title"}, "prioritizedContentFields": [{"fieldName": "content"}]}}]},
    }
    client.request("PUT", f"indexes/{quote(index_name)}", index)
    documents = json.loads((ROOT / "data/enterprise-documents.json").read_text(encoding="utf-8"))
    client.request("POST", f"indexes/{quote(index_name)}/docs/index", {"value": [{"@search.action": "mergeOrUpload", **item} for item in documents]})
    for source in scoped_sources:
        client.request("PUT", f"knowledgesources/{quote(source['name'])}", source)
    account_endpoint = require("FOUNDRY_PROJECT_ENDPOINT").split("/api/projects/", 1)[0]
    model = require("AZURE_AI_MODEL_DEPLOYMENT_NAME")
    kb = {
        "name": knowledge_base_name,
        "description": "Enterprise documents and Microsoft Learn unified grounding.",
        "knowledgeSources": [{"name": item["name"]} for item in scoped_sources],
        "outputMode": "answerSynthesis",
        "retrievalReasoningEffort": {"kind": "low"},
        "retrievalInstructions": "Retrieve authoritative enterprise facts and Microsoft documentation with references.",
        "answerInstructions": (
            "Answer using the retrieved evidence. Include exact source URLs and page or section metadata "
            "when available. Prefer the document's source_url metadata for its HTTPS link; reference "
            "IDs alone are not source links. If no source URL is available, say so. Do not invent URLs."
        ),
        "models": [{"kind": "azureOpenAI", "azureOpenAIParameters": {"resourceUri": account_endpoint, "deploymentId": model, "modelName": model}}],
    }
    client.request("PUT", f"knowledgebases/{quote(knowledge_base_name)}", kb)
    # Export this with the Knowledge Base lifecycle so direct-KB customizations
    # do not depend on the optional Toolbox configuration step.
    azd_set("KB_MCP_ENDPOINT", knowledge_base_endpoint(client))
    return scoped_sources


def preflight_external_sources(client: SearchClient, sources: list[dict], tools: list[dict], owned_connection: str) -> None:
    for source in sources:
        if source["name"] in {INDEX_SOURCE_NAME, LEARN_SOURCE_NAME}:
            continue
        kind = source.get("kind")
        if kind == "searchIndex":
            parameters = source.get("searchIndexParameters", {})
            index_name = parameters.get("searchIndexName")
            if not index_name:
                raise RuntimeError(f"Knowledge Source {source['name']} is missing searchIndexName")
            index = client.request("GET", f"indexes/{quote(index_name)}", expected=(200,))
            semantic_name = parameters.get("semanticConfigurationName")
            configurations = index.get("semantic", {}).get("configurations", [])
            if semantic_name and not any(item["name"] == semantic_name for item in configurations):
                raise RuntimeError(f"Knowledge Source {source['name']} references missing semantic configuration {semantic_name}")
            fields = {item["name"]: item for item in index.get("fields", [])}
            for field in parameters.get("searchFields", []):
                name = field["name"]
                if name not in fields or not fields[name].get("searchable", False):
                    raise RuntimeError(f"Knowledge Source {source['name']} requires searchable field {name}")
            for field in parameters.get("sourceDataFields", []):
                name = field["name"]
                if name not in fields or fields[name].get("retrievable") is False:
                    raise RuntimeError(f"Knowledge Source {source['name']} requires retrievable citation field {name}")
        elif kind == "fabricOntology":
            parameters = source.get("fabricOntologyParameters", {})
            if not parameters.get("workspaceId") or not parameters.get("ontologyId"):
                raise RuntimeError(f"Fabric source {source['name']} requires workspaceId and ontologyId")
    for tool in tools:
        connection = tool.get("project_connection_id") or tool.get("connection")
        if connection and connection != owned_connection:
            run("azd", "ai", "connection", "show", str(connection), "--no-prompt")


def configure_toolbox(client: SearchClient, sources: list[dict]) -> None:
    kb_endpoint = knowledge_base_endpoint(client)
    connection_name = scoped_name("enterprise-kb")
    toolbox_name = scoped_name("enterprise-tools")
    run("azd", "ai", "connection", "create", connection_name, "--kind", "remote-tool", "--force", "--target", kb_endpoint, "--auth-type", "agentic-identity", "--audience", "https://search.azure.com", "--metadata", "ApiType=Azure", "--no-prompt")
    tools = load_fragments(ROOT / "config/toolbox-tools", {**os.environ, "KB_MCP_ENDPOINT": kb_endpoint, "KB_CONNECTION_NAME": connection_name})
    validate_cross_path(sources, tools)
    document = toolbox_document(tools)
    configuration_document = {"toolbox": document, "knowledgeSources": sources}
    digest = canonical_digest(configuration_document)
    old_digest = azd_get("TOOLBOX_CONFIG_DIGEST")
    exists = subprocess.run(["azd", "ai", "toolbox", "show", toolbox_name, "--no-prompt"], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if not exists or old_digest != digest:
        generated = ROOT / ".azure" / "toolbox.generated.json"
        generated.parent.mkdir(exist_ok=True)
        generated.write_text(json.dumps(document, indent=2), encoding="utf-8")
        if exists:
            # Current azd exposes immutable versions through mutation commands but
            # cannot replace raw built-ins atomically. Recreate only on a digest
            # change; the unversioned MCP alias consumed by the agent stays stable.
            run("azd", "ai", "toolbox", "delete", toolbox_name, "--force", "--no-prompt")
        run("azd", "ai", "toolbox", "create", toolbox_name, "--from-file", str(generated), "--no-prompt")
        azd_set("TOOLBOX_CONFIG_DIGEST", digest)
    project_endpoint = require("FOUNDRY_PROJECT_ENDPOINT").rstrip("/")
    azd_set("TOOLBOX_ENDPOINT", f"{project_endpoint}/toolboxes/{toolbox_name}/mcp?api-version=v1")
    azd_set("TOOLBOX_NAME", toolbox_name)
    azd_set("KB_CONNECTION_NAME", connection_name)
    azd_set("AZURE_SEARCH_INDEX_NAME", scoped_name(INDEX_NAME))
    azd_set("KNOWLEDGE_SOURCE_NAMES", ",".join(item["name"] for item in sources))
    azd_set("KNOWLEDGE_BASE_NAME", scoped_name(KB_NAME))


def main() -> None:
    sources = load_fragments(ROOT / "config/knowledge-sources")
    client = SearchClient(require("AZURE_SEARCH_ENDPOINT"))
    kb_endpoint = knowledge_base_endpoint(client)
    tools = load_fragments(ROOT / "config/toolbox-tools", {**os.environ, "KB_MCP_ENDPOINT": kb_endpoint, "KB_CONNECTION_NAME": scoped_name("enterprise-kb")})
    validate_cross_path(sources, tools)
    preflight_external_sources(client, sources, tools, scoped_name("enterprise-kb"))
    scoped_sources = create_search_objects(client, sources)
    configure_toolbox(client, scoped_sources)
    print("Enterprise knowledge data plane and toolbox are ready.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise

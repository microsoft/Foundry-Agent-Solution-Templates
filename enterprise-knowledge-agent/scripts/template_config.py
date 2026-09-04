from __future__ import annotations

import hashlib
import json
import os
import re
from urllib.parse import urlsplit, urlunsplit
from pathlib import Path
from typing import Any

import yaml

PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)}")
SECRET_KEYS = re.compile(r"(?i)(api[_-]?key|client[_-]?secret|password|token)$")


def _substitute(value: Any, environment: dict[str, str]) -> Any:
    if isinstance(value, str):
        def replace(match: re.Match[str]) -> str:
            name = match.group(1)
            if not environment.get(name):
                raise ValueError(f"Unresolved environment variable: {name}")
            return environment[name]
        return PLACEHOLDER.sub(replace, value)
    if isinstance(value, list):
        return [_substitute(item, environment) for item in value]
    if isinstance(value, dict):
        return {key: _substitute(item, environment) for key, item in value.items()}
    return value


def _reject_secrets(value: Any, path: str = "") -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            current = f"{path}.{key}" if path else key
            if SECRET_KEYS.search(key) and isinstance(item, str) and item and not PLACEHOLDER.fullmatch(item):
                raise ValueError(f"Plaintext secret is not allowed at {current}")
            _reject_secrets(item, current)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _reject_secrets(item, f"{path}[{index}]")


def load_fragments(folder: Path, environment: dict[str, str] | None = None) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    category = folder.name if folder.name in {"knowledge-sources", "toolbox-tools"} else folder.parent.name
    for path in sorted(folder.glob("*.yaml")):
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict) or not payload.get("name"):
            raise ValueError(f"{path.name} must contain an object with a name")
        if category == "knowledge-sources" and not payload.get("kind"):
            raise ValueError(f"{path.name} must contain a kind")
        if category == "toolbox-tools" and not payload.get("type"):
            raise ValueError(f"{path.name} must contain a type")
        _reject_secrets(payload)
        values.append(_substitute(payload, environment or dict(os.environ)))
    names = [str(item["name"]).casefold() for item in values]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate fragment name")
    return values


def _normalized_endpoint(value: str) -> str:
    parsed = urlsplit(value.strip())
    path = parsed.path.rstrip("/") or "/"
    return urlunsplit((parsed.scheme.casefold(), parsed.netloc.casefold(), path, parsed.query, ""))


def validate_cross_path(knowledge_sources: list[dict[str, Any]], toolbox_tools: list[dict[str, Any]]) -> None:
    names: set[str] = set()
    endpoints: set[str] = set()
    connections: set[str] = set()
    for item in [*knowledge_sources, *toolbox_tools]:
        name = str(item["name"]).casefold()
        if name in names:
            raise ValueError(f"Duplicate identifier across paths: {name}")
        names.add(name)
        endpoint = item.get("server_url") or item.get("mcpServerParameters", {}).get("serverURL")
        if endpoint:
            normalized = _normalized_endpoint(str(endpoint))
            if normalized in endpoints:
                raise ValueError(f"Duplicate endpoint across paths: {normalized}")
            endpoints.add(normalized)
        connection = item.get("project_connection_id") or item.get("connection")
        if connection:
            normalized_connection = str(connection).casefold()
            if normalized_connection in connections:
                raise ValueError(f"Duplicate connection across paths: {normalized_connection}")
            connections.add(normalized_connection)


def toolbox_document(tools: list[dict[str, Any]]) -> dict[str, Any]:
    return {"description": "Enterprise Knowledge Toolbox: Foundry IQ plus Web IQ", "tools": tools}


def canonical_digest(document: dict[str, Any]) -> str:
    encoded = json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    return hashlib.sha256(encoded).hexdigest()

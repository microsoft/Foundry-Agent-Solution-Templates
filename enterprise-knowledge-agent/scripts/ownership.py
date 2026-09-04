from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def write_ownership(path: Path, endpoint: str, kb: str, sources: list[str], demo_index: str, external: list[str]) -> None:
    previous: dict[str, Any] = {}
    if path.exists():
        previous = json.loads(path.read_text(encoding="utf-8"))
        previous_endpoint = previous.get("searchEndpoint", "").rstrip("/").casefold()
        if previous_endpoint and previous_endpoint != endpoint.rstrip("/").casefold():
            raise RuntimeError("Existing ownership state belongs to a different Search endpoint")
    owned_sources = list(dict.fromkeys([*previous.get("knowledgeSources", []), *sources]))
    value = {
        "schemaVersion": 1,
        "searchEndpoint": endpoint.rstrip("/"),
        "knowledgeBase": kb,
        "knowledgeSources": owned_sources,
        "demoIndex": demo_index,
        "externalResources": external,
    }
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def cleanup_targets(path: Path, endpoint: str) -> list[tuple[str, str]]:
    if not path.exists():
        raise RuntimeError("Ownership state is missing; refusing to infer deletion targets from current configuration")
    state: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    if state.get("searchEndpoint", "").rstrip("/").casefold() != endpoint.rstrip("/").casefold():
        raise RuntimeError("Ownership state does not match AZURE_SEARCH_ENDPOINT")
    return [
        ("knowledgebases", state["knowledgeBase"]),
        *[("knowledgesources", name) for name in reversed(state["knowledgeSources"])],
        ("indexes", state["demoIndex"]),
    ]

from __future__ import annotations

import json
from pathlib import Path


def write_ownership(path: Path, endpoint: str, kb: str, sources: list[str], demo_index: str, external: list[str]) -> None:
    previous = {}
    if path.exists():
        previous = json.loads(path.read_text(encoding="utf-8"))
        previous_endpoint = previous.get("searchEndpoint", "").rstrip("/").casefold()
        if previous_endpoint and previous_endpoint != endpoint.rstrip("/").casefold():
            raise RuntimeError("Existing ownership state belongs to a different Search endpoint")
    previous_kbs = previous.get("knowledgeBases", [])
    previous_sources = previous.get("knowledgeSources", [])
    previous_indexes = previous.get("demoIndexes", [])
    owned_kbs = list(dict.fromkeys([*previous_kbs, kb]))
    owned_sources = list(dict.fromkeys([*previous_sources, *sources]))
    owned_indexes = list(dict.fromkeys([*previous_indexes, demo_index]))
    value = {
        "searchEndpoint": endpoint.rstrip("/"),
        "knowledgeBases": owned_kbs,
        "knowledgeSources": owned_sources,
        "demoIndexes": owned_indexes,
        "externalResources": external,
    }
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def cleanup_targets(path: Path, endpoint: str) -> list[tuple[str, str]]:
    if not path.exists():
        raise RuntimeError("Ownership state is missing; refusing to infer deletion targets from current configuration")
    state = json.loads(path.read_text(encoding="utf-8"))
    if state.get("searchEndpoint", "").rstrip("/").casefold() != endpoint.rstrip("/").casefold():
        raise RuntimeError("Ownership state does not match AZURE_SEARCH_ENDPOINT")
    return [
        *[("knowledgebases", name) for name in reversed(state["knowledgeBases"])],
        *[("knowledgesources", name) for name in reversed(state["knowledgeSources"])],
        *[("indexes", name) for name in reversed(state["demoIndexes"])],
    ]

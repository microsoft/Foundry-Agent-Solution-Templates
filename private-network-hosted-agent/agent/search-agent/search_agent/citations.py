"""Stable citation rendering owned by this direct-SDK sample."""

from __future__ import annotations

from collections.abc import Iterable, Mapping


def render_citations(documents: Iterable[Mapping[str, object]]) -> str:
    """Render unique canonical sources in first-seen order."""

    citations: list[str] = []
    seen: set[str] = set()
    for document in documents:
        source_url = str(document.get("source_url", "")).strip()
        if not source_url or source_url in seen:
            continue
        seen.add(source_url)
        title = str(document.get("title", document.get("id", "Source"))).strip()
        citations.append(f"- [{title}]({source_url})")

    return "\n".join(citations)


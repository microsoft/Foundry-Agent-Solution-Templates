"""Direct Azure AI Search SDK tool."""

from __future__ import annotations

import os
from collections.abc import Callable
from typing import Any

from azure.core.credentials import TokenCredential
from azure.search.documents import SearchClient

from search_agent.credentials import get_azure_credential


def create_search_client(
    credential_factory: Callable[[], TokenCredential] = get_azure_credential,
) -> SearchClient:
    endpoint = os.environ["AZURE_SEARCH_ENDPOINT"]
    index_name = os.environ["AZURE_SEARCH_INDEX_NAME"]
    return SearchClient(
        endpoint=endpoint,
        index_name=index_name,
        credential=credential_factory(),
        audience="https://search.azure.com",
    )


def search_private_knowledge(
    question: str,
    *,
    client: SearchClient | None = None,
    top: int = 3,
) -> list[dict[str, Any]]:
    """Return the minimal fields required for grounding and citations."""

    normalized = question.strip()
    if not normalized:
        raise ValueError("question must not be empty")
    if top < 1 or top > 5:
        raise ValueError("top must be between 1 and 5")

    search_client = client or create_search_client()
    results = search_client.search(
        search_text=normalized,
        top=top,
        select=["id", "title", "content", "source_url"],
    )
    return [
        {
            "id": str(result["id"]),
            "title": str(result["title"]),
            "content": str(result["content"]),
            "source_url": str(result["source_url"]),
            "score": result.get("@search.score"),
        }
        for result in results
    ]


TOOL_DEFINITION = {
    "type": "function",
    "name": "search_private_knowledge",
    "description": "Search the private non-sensitive solution-template knowledge index.",
    "parameters": {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The user's question rewritten as a concise search query.",
            }
        },
        "required": ["question"],
        "additionalProperties": False,
    },
    "strict": True,
}


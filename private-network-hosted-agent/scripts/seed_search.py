"""Create the CMK-backed demo index and upload non-sensitive documents."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SearchResourceEncryptionKey,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--index-name", required=True)
    parser.add_argument("--vault-uri", required=True)
    parser.add_argument("--key-name", required=True)
    parser.add_argument("--key-version", required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    args = parser.parse_args()

    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    index_client = SearchIndexClient(
        endpoint=args.endpoint,
        credential=credential,
        audience="https://search.azure.com",
    )
    index = SearchIndex(
        name=args.index_name,
        fields=[
            SearchField(name="id", type=SearchFieldDataType.String, key=True),
            SearchField(
                name="title",
                type=SearchFieldDataType.String,
                searchable=True,
            ),
            SearchField(
                name="content",
                type=SearchFieldDataType.String,
                searchable=True,
            ),
            SearchField(
                name="source_url",
                type=SearchFieldDataType.String,
                filterable=True,
            ),
        ],
        encryption_key=SearchResourceEncryptionKey(
            vault_uri=args.vault_uri,
            key_name=args.key_name,
            key_version=args.key_version,
        ),
    )
    index_client.create_or_update_index(index)

    documents = json.loads(args.corpus.read_text(encoding="utf-8"))
    search_client = SearchClient(
        endpoint=args.endpoint,
        index_name=args.index_name,
        credential=credential,
        audience="https://search.azure.com",
    )
    results = search_client.upload_documents(documents)
    failed = [result.key for result in results if not result.succeeded]
    if failed:
        raise RuntimeError(f"Failed to upload documents: {failed}")
    print(f"Seeded {len(results)} documents into {args.index_name}.")


if __name__ == "__main__":
    main()

"""Credential selection with no production fallback chain."""

from __future__ import annotations

import os

from azure.core.credentials import TokenCredential
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential


def get_azure_credential() -> TokenCredential:
    """Return a deterministic runtime credential.

    Hosted Agent production uses its automatically created agent identity.
    Developer credential discovery is available only when explicitly enabled.
    """

    if os.getenv("FOUNDRY_LOCAL_DEVELOPMENT", "").lower() == "true":
        return DefaultAzureCredential(
            exclude_interactive_browser_credential=True,
            require_envvar=False,
        )

    client_id = os.getenv("AZURE_CLIENT_ID")
    return ManagedIdentityCredential(client_id=client_id) if client_id else ManagedIdentityCredential()


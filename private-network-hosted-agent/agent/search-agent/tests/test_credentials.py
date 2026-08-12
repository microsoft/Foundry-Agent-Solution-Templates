from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

from search_agent.credentials import get_azure_credential


def test_production_uses_managed_identity(monkeypatch) -> None:
    monkeypatch.delenv("FOUNDRY_LOCAL_DEVELOPMENT", raising=False)
    monkeypatch.delenv("AZURE_CLIENT_ID", raising=False)
    assert isinstance(get_azure_credential(), ManagedIdentityCredential)


def test_local_development_is_explicit(monkeypatch) -> None:
    monkeypatch.setenv("FOUNDRY_LOCAL_DEVELOPMENT", "true")
    assert isinstance(get_azure_credential(), DefaultAzureCredential)


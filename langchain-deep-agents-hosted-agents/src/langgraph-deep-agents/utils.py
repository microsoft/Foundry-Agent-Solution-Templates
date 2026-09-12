"""Microsoft Foundry model utilities for the deep research agent."""

import os
from functools import lru_cache

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from langchain_openai import ChatOpenAI

_AZURE_AI_SCOPE = "https://ai.azure.com/.default"


def build_chat_model(deployment: str | None = None) -> ChatOpenAI:
    """Get a chat model for a Foundry deployment."""
    return _build_chat_model(deployment or os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"])


@lru_cache(maxsize=16)
def _build_chat_model(deployment: str) -> ChatOpenAI:
    project_endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=project_endpoint, credential=credential)
    openai_client = project.get_openai_client()
    token_provider = get_bearer_token_provider(credential, _AZURE_AI_SCOPE)

    return ChatOpenAI(
        model=deployment,
        base_url=str(openai_client.base_url),
        api_key=token_provider,
        temperature=0.0,
        use_responses_api=True,
        output_version="responses/v1",
    )

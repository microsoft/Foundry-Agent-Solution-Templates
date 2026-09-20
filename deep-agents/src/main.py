"""Create the research graph for the configuration-driven runner."""

import os

from azure.identity import DefaultAzureCredential
from langchain_azure_ai.chat_models import AzureAIOpenAIApiChatModel

from agent import build_agent


def create_graph():
    model = AzureAIOpenAIApiChatModel(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        credential=DefaultAzureCredential(),
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        use_responses_api=True,
        store=False,
    )
    return build_agent(model)

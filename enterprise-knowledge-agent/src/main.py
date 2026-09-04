import asyncio
import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import FoundryToolbox, ResponsesHostServer
from azure.identity import DefaultAzureCredential


async def main() -> None:
    credential = DefaultAzureCredential()
    toolbox = FoundryToolbox(credential)
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
        default_headers={"User-Agent": "enterprise-knowledge-agent-v1"},
    )
    agent = Agent(
        client=client,
        tools=toolbox,
        instructions=(
            "You are an enterprise knowledge assistant. Use knowledge_base_retrieve for "
            "internal enterprise facts and Microsoft product documentation. Use web_search "
            "for broad public or current information. For mixed questions, use both. Never "
            "invent unavailable facts. Preserve and clearly label source citations as HTTPS links."
        ),
        default_options={"store": False},
    )
    await ResponsesHostServer(agent).run_async()


if __name__ == "__main__":
    asyncio.run(main())


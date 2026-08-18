# Copyright (c) Microsoft. All rights reserved.

import asyncio
import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import FoundryToolbox
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from end_user_identity import (
    EndUserIdentityForwardingMiddleware,
    EndUserIdentityScopedResponsesHostServer,
)

# Load environment variables from .env file
load_dotenv()


async def main():
    credential = DefaultAzureCredential()

    os.environ["TOOLBOX_ENDPOINT"] = os.environ["AGENT_TOOLBOX_ENDPOINT"].strip()

    # FoundryToolbox resolves the toolbox endpoint from the environment
    # (TOOLBOX_ENDPOINT, or FOUNDRY_PROJECT_ENDPOINT + TOOLBOX_NAME), authenticates
    # every request with the credential, and transparently forwards the platform
    # per-request call-id to the toolbox. The hosting server enters the agent, which
    # connects the toolbox on first use and closes it at shutdown.
    toolbox = FoundryToolbox(credential)

    client = FoundryChatClient(
        project_endpoint=os.environ["AGENT_APIM_PROJECT_ENDPOINT"].strip(),
        model=os.environ["AGENT_MODEL_DEPLOYMENT"].strip(),
        credential=credential,
        default_headers={"User-Agent": "apim-hosted-agent-v1"},
        middleware=[EndUserIdentityForwardingMiddleware()],
    )

    agent = Agent(
        client=client,
        instructions="You are a friendly assistant. Keep your answers brief.",
        tools=toolbox,
        # History will be managed by the hosting infrastructure, thus there
        # is no need to store history by the service. Learn more at:
        # https://developers.openai.com/api/reference/resources/responses/methods/create
        default_options={"store": False},
    )

    server = EndUserIdentityScopedResponsesHostServer(agent)
    await server.run_async()


if __name__ == "__main__":
    asyncio.run(main())

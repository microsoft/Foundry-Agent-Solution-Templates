"""Responses protocol entry point for the private Search Hosted Agent."""

from __future__ import annotations

import asyncio
import os

from azure.ai.agentserver.responses import (
    CreateResponse,
    ResponseContext,
    ResponsesAgentServerHost,
    ResponsesServerOptions,
    TextResponse,
)
from azure.ai.agentserver.responses.models import (
    MessageContentInputTextContent,
    MessageContentOutputTextContent,
)
from azure.ai.projects import AIProjectClient

from search_agent.credentials import get_azure_credential
from search_agent.orchestrator import SearchAgent

credential = get_azure_credential()
project_client = AIProjectClient(
    endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    credential=credential,
    user_agent="private-network-hosted-agent-v1",
)
responses_client = project_client.get_openai_client().responses
agent = SearchAgent(
    responses_client=responses_client,
    model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
)

app = ResponsesAgentServerHost(
    options=ResponsesServerOptions(default_fetch_history_count=20),
)

ROLE_MAP = {
    MessageContentOutputTextContent: "assistant",
    MessageContentInputTextContent: "user",
}


def build_input(current_input: str, history: list[object]) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    for item in history:
        for content in getattr(item, "content", None) or []:
            role = ROLE_MAP.get(type(content))
            if role and content.text:
                items.append({"role": role, "content": content.text})
    items.append({"role": "user", "content": current_input})
    return items


@app.response_handler
async def handler(
    request: CreateResponse,
    context: ResponseContext,
    _cancellation_signal: asyncio.Event,
) -> TextResponse:
    user_input = await context.get_input_text()
    if not user_input or not user_input.strip():
        return TextResponse(context, request, text="Please provide a question.")

    history = await context.get_history()
    input_items = build_input(user_input, history)
    answer = await asyncio.get_running_loop().run_in_executor(
        None,
        lambda: agent.answer(input_items),
    )
    return TextResponse(context, request, text=answer)


app.run()

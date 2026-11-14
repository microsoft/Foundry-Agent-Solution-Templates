"""AG-UI gateway: translates AG-UI to the Foundry hosted agent's Responses protocol.

Agent Framework does the protocol translation and approval forwarding. This file adds only
per-user ownership of Foundry conversations, which double as AG-UI thread IDs.
Run locally: uvicorn app:app --port 8000
"""

import os
import re

import aiohttp
from ag_ui.core import EventType
from agent_framework.foundry import FoundryAgent
from agent_framework_ag_ui import AgentFrameworkAgent, add_agent_framework_fastapi_endpoint
from azure.identity.aio import DefaultAzureCredential
from fastapi import FastAPI, Header, HTTPException, Request

PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
AGENT_NAME = os.environ["FOUNDRY_AGENT_NAME"]
CONVERSATIONS_URL = f"{PROJECT_ENDPOINT}/agents/{AGENT_NAME}/endpoint/protocols/openai/conversations"
USER_ID = re.compile(r"^[A-Za-z0-9-]{1,64}$")
THREAD_ID = re.compile(r"^conv_[A-Za-z0-9_-]{1,128}$")

credential = DefaultAzureCredential()
owners: dict[str, str] = {}  # Verified thread -> owner cache; Foundry conversation metadata is the source of truth.


async def foundry(method: str, url: str, body: dict | None = None) -> dict:
    token = await credential.get_token("https://ai.azure.com/.default")
    async with (
        aiohttp.ClientSession() as session,
        session.request(
            method, url, params={"api-version": "v1"}, json=body, headers={"Authorization": f"Bearer {token.token}"}
        ) as response,
    ):
        if response.status in (400, 404):  # Foundry returns 400 for a malformed conv_ ID, 404 for a missing one.
            raise HTTPException(404, "Unknown conversation.")
        response.raise_for_status()
        return await response.json()


def user_id(x_user_id: str = Header("")) -> str:
    """The web app sets this from the signed-in user; the gateway is reachable only inside the environment."""
    if not USER_ID.match(x_user_id):
        raise HTTPException(401, "Missing or invalid user.")
    return x_user_id


async def owned_thread_scope(request: Request, x_user_id: str = Header("")) -> str:
    """AG-UI authorization scope: the caller must own the Foundry conversation used as the thread ID."""
    user = user_id(x_user_id)
    thread = (await request.json()).get("threadId", "")
    if not THREAD_ID.match(thread):
        raise HTTPException(400, "threadId must be a Foundry conversation ID.")
    if owners.get(thread) != user:
        metadata = (await foundry("GET", f"{CONVERSATIONS_URL}/{thread}")).get("metadata") or {}
        if metadata.get("owner") != user:
            raise HTTPException(403, "Conversation belongs to another user.")
        owners[thread] = user
    return user


class HostedApprovalAgent(AgentFrameworkAgent):
    """Interop fixes between agent-framework-ag-ui 1.8.1 and CopilotKit 1.88 / @ag-ui/client 1.0.2.

    1. CopilotKit sends an approval decision twice: as `resume` and as a tool message keyed by the
       interrupt ID. The duplicate makes the adapter skip the model's reply. Keep only `resume`.
    2. The adapter emits TOOL_CALL_END for the hosted approval ID (`mcpr_...`) without a TOOL_CALL_START,
       and @ag-ui/client aborts the run with INCOMPLETE_STREAM. Drop the orphan event.
    Delete this class when a release fixes both and approve, reject and follow-up turns pass without it.
    """

    async def run(self, input_data, **kwargs):
        resumed = {
            r.get("interrupt_id") or r.get("interruptId") or r.get("id")
            for r in (input_data.get("resume") or [])
            if isinstance(r, dict)
        }
        if resumed:
            input_data = {
                **input_data,
                "messages": [
                    m
                    for m in input_data.get("messages", [])
                    if not (m.get("role") == "tool" and (m.get("tool_call_id") or m.get("toolCallId")) in resumed)
                ],
            }
        started: set[str] = set()
        async for event in super().run(input_data, **kwargs):
            if event.type == EventType.TOOL_CALL_START:
                started.add(event.tool_call_id)
            elif event.type == EventType.TOOL_CALL_END and event.tool_call_id not in started:
                continue
            yield event


app = FastAPI()


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.post("/threads")
async def create_thread(x_user_id: str = Header("")) -> dict:
    user = user_id(x_user_id)
    conversation = await foundry("POST", CONVERSATIONS_URL, {"metadata": {"owner": user}})
    owners[conversation["id"]] = user
    return {"threadId": conversation["id"]}


hosted_agent = FoundryAgent(
    project_endpoint=PROJECT_ENDPOINT, agent_name=AGENT_NAME, credential=credential, allow_preview=True
)
add_agent_framework_fastapi_endpoint(
    app,
    # threadId is the Foundry conversation ID, so Foundry keeps history and the gateway keeps no thread state.
    HostedApprovalAgent(agent=hosted_agent, use_service_session=True, service_session_id_from_thread_id=True),
    "/",
    authorization_scope_resolver=owned_thread_scope,
)

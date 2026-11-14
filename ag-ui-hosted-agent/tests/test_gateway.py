"""Offline tests for the gateway's per-user conversation ownership."""

import importlib
import sys
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

GATEWAY = Path(__file__).resolve().parents[1] / "src" / "gateway"
RUN = {"runId": "r1", "messages": [], "tools": [], "context": [], "state": {}, "forwardedProps": {}}


@pytest.fixture
def gateway(monkeypatch):
    monkeypatch.setenv("FOUNDRY_PROJECT_ENDPOINT", "https://example.services.ai.azure.com/api/projects/demo")
    monkeypatch.setenv("FOUNDRY_AGENT_NAME", "claims-triage")
    monkeypatch.syspath_prepend(str(GATEWAY))
    sys.modules.pop("app", None)
    module = importlib.import_module("app")
    conversations: dict[str, dict] = {"conv_alice": {"metadata": {"owner": "alice"}}}

    async def fake_foundry(method, url, body=None):
        if method == "POST":
            conversations["conv_new"] = {"metadata": body["metadata"]}
            return {"id": "conv_new"}
        conversation = conversations.get(url.rsplit("/", 1)[-1])
        if conversation is None:
            raise HTTPException(404, "Unknown conversation.")
        return conversation

    monkeypatch.setattr(module, "foundry", fake_foundry)
    return module


def run(client, thread, user):
    headers = {"x-user-id": user} if user else {}
    return client.post("/", json={**RUN, "threadId": thread}, headers=headers)


def test_rejects_missing_user(gateway):
    assert run(TestClient(gateway.app), "conv_alice", None).status_code == 401


def test_rejects_thread_that_is_not_a_conversation(gateway):
    assert run(TestClient(gateway.app), "../other", "alice").status_code == 400


def test_rejects_another_users_conversation(gateway):
    assert run(TestClient(gateway.app), "conv_alice", "mallory").status_code == 403


def test_rejects_unknown_conversation(gateway):
    assert run(TestClient(gateway.app), "conv_missing", "alice").status_code == 404


def test_new_thread_is_owned_by_its_creator(gateway):
    client = TestClient(gateway.app)
    response = client.post("/threads", headers={"x-user-id": "bob"})
    assert response.json() == {"threadId": "conv_new"}
    assert run(client, "conv_new", "mallory").status_code == 403


def test_owner_passes_the_authorization_scope(gateway):
    scope = gateway.owned_thread_scope
    request = type("R", (), {"json": staticmethod(lambda: _async({"threadId": "conv_alice"}))})()
    import asyncio

    assert asyncio.run(scope(request, "alice")) == "alice"


async def _async(value):
    return value


def test_shim_drops_duplicate_decision_and_orphan_tool_call_end(gateway, monkeypatch):
    import asyncio
    from types import SimpleNamespace

    from ag_ui.core import EventType

    seen = {}

    async def fake_parent_run(self, input_data, **kwargs):
        seen["messages"] = input_data["messages"]
        for event_type, call_id in [
            (EventType.TOOL_CALL_START, "call_1"),
            (EventType.TOOL_CALL_END, "call_1"),
            (EventType.TOOL_CALL_END, "mcpr_1"),  # Orphan: no matching start.
        ]:
            yield SimpleNamespace(type=event_type, tool_call_id=call_id)

    monkeypatch.setattr(gateway.AgentFrameworkAgent, "run", fake_parent_run)
    agent = gateway.HostedApprovalAgent.__new__(gateway.HostedApprovalAgent)
    input_data = {
        "resume": [{"interrupt_id": "mcpr_1", "status": "resolved", "payload": {"approved": True}}],
        "messages": [
            {"role": "user", "content": "Escalate CLM-1002."},
            {"role": "tool", "tool_call_id": "mcpr_1", "content": '{"approved": true}'},
        ],
    }

    async def collect():
        return [e async for e in agent.run(input_data)]

    events = asyncio.run(collect())
    assert [m["role"] for m in seen["messages"]] == ["user"]
    assert [(e.type, e.tool_call_id) for e in events] == [
        (EventType.TOOL_CALL_START, "call_1"),
        (EventType.TOOL_CALL_END, "call_1"),
    ]

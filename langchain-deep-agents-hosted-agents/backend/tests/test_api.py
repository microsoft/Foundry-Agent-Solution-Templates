import asyncio
import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.auth import get_user
from app.config import Settings, get_settings
from app.foundry import FoundryService
from app.main import app, foundry, is_text_file, store
from app.models import ConversationMapping, Project, UserContext
from app.store import InMemoryDomainStore, SqliteDomainStore


class FakeFoundryService:
    def __init__(self) -> None:
        self.session_ids: list[str] = []
        self.conversation_ids: list[str] = []
        self.stream_calls: list[tuple[str, str, str, str]] = []
        self.file_name = "report.md"
        self.file_size = 12

    async def create_session(self) -> str:
        session_id = f"session-{len(self.session_ids) + 1}"
        self.session_ids.append(session_id)
        return session_id

    async def get_session(self, session_id: str) -> dict:
        return {"agent_session_id": session_id, "status": "running", "agent_version": "6"}

    async def stop_session(self, session_id: str) -> None:
        return None

    async def delete_session(self, session_id: str) -> None:
        self.session_ids.remove(session_id)

    async def list_response_models(self) -> list[dict]:
        return [{"name": "gpt-responses", "modelName": "gpt-responses", "modelVersion": "1", "modelPublisher": "OpenAI", "isDefault": True}]

    async def list_session_files(self, session_id: str, path: str) -> list[dict]:
        return [{"name": self.file_name, "path": f"{'' if path == '/' else path}/{self.file_name}", "size": self.file_size, "isDirectory": False, "modifiedAt": datetime(2026, 1, 1, tzinfo=UTC)}]

    async def download_session_file(self, session_id: str, path: str):
        return iter([b"test report\n"])

    async def read_session_file(self, session_id: str, path: str, limit: int) -> bytes:
        return b"test report\n"

    async def create_conversation(self, project_id: str, title: str) -> str:
        conversation_id = f"conversation-{len(self.conversation_ids) + 1}"
        self.conversation_ids.append(conversation_id)
        return conversation_id

    async def delete_conversation(self, conversation_id: str) -> None:
        self.conversation_ids.remove(conversation_id)

    async def list_items(self, conversation_id: str) -> list[dict]:
        return [{"id": "message-1", "type": "message", "role": "assistant", "content": [{"type": "output_text", "text": conversation_id}]}]

    async def stream_response(
        self,
        conversation_id: str,
        session_id: str,
        model_name: str,
        input_value: str | list[dict[str, object]],
        response_id: str,
        execution_mode: str,
    ) -> AsyncIterator[str]:
        self.stream_calls.append((conversation_id, session_id, model_name, execution_mode))
        async def events() -> AsyncIterator[str]:
            response = {"id": "response-1", "status": "completed", "output": [], "output_text": str(input_value), "agent_session_id": session_id}
            yield f"data: {json.dumps({'type': 'response.completed', 'response': response})}\n\n"
            yield "data: [DONE]\n\n"

        return events()

    async def retrieve_response(self, response_id: str, starting_after: int | None) -> AsyncIterator[str]:
        async def events() -> AsyncIterator[str]:
            response = {"id": response_id, "status": "completed", "output": []}
            yield f"data: {json.dumps({'type': 'response.completed', 'sequence_number': starting_after, 'response': response})}\n\n"
            yield "data: [DONE]\n\n"

        return events()


@pytest.fixture
def api() -> tuple[TestClient, FakeFoundryService]:
    domain = InMemoryDomainStore()
    agent = FakeFoundryService()
    app.dependency_overrides[get_user] = lambda: UserContext(owner_id="owner-1", display_name="Test User")
    app.dependency_overrides[get_settings] = lambda: Settings(foundry_project_endpoint="https://example.invalid", local_development=True)
    app.dependency_overrides[store] = lambda: domain
    app.dependency_overrides[foundry] = lambda: agent
    with TestClient(app) as client:
        yield client, agent
    app.dependency_overrides.clear()


def test_project_conversation_and_shared_session_lifecycle(api: tuple[TestClient, FakeFoundryService]) -> None:
    client, agent = api

    status = client.get("/api/status").json()
    assert status["user"] == {"name": "Test User", "email": ""}
    assert client.get("/api/models").json() == [{"name": "gpt-responses", "modelName": "gpt-responses", "modelVersion": "1", "modelPublisher": "OpenAI", "isDefault": True}]

    project_response = client.post("/api/projects", json={"name": "Deep Agent"})
    assert project_response.status_code == 201
    project = project_response.json()

    first = client.post(f"/api/projects/{project['id']}/conversations", json={"title": "First"}).json()
    second = client.post(f"/api/projects/{project['id']}/conversations", json={"title": "Second"}).json()
    assert {item["id"] for item in client.get(f"/api/projects/{project['id']}/conversations").json()} == {first["id"], second["id"]}

    renamed = client.patch(f"/api/projects/{project['id']}/conversations/{first['id']}", json={"title": "Renamed"})
    assert renamed.json()["title"] == "Renamed"

    response_url = f"/api/projects/{project['id']}/conversations/{first['id']}/responses"
    response_id = f"caresp_{'0' * 50}"
    request_body = {"input": "research", "response_id": response_id}
    assert client.post(response_url, json=request_body).status_code == 400
    assert client.post(response_url, headers={"x-model-deployment-name": "unsupported"}, json=request_body).status_code == 400
    response = client.post(response_url, headers={"x-model-deployment-name": "gpt-responses"}, json=request_body)
    assert response.status_code == 200
    assert "response.completed" in response.text
    assert agent.stream_calls == [(first["id"], project["sessionId"], "gpt-responses", "default")]
    auto_response = client.post(response_url, headers={"x-model-deployment-name": "gpt-responses"}, json={**request_body, "execution_mode": "auto"})
    assert auto_response.status_code == 200
    assert agent.stream_calls[-1] == (first["id"], project["sessionId"], "gpt-responses", "auto")
    assert client.post(response_url, headers={"x-model-deployment-name": "gpt-responses"}, json={**request_body, "execution_mode": "invalid"}).status_code == 422
    replay = client.get(f"{response_url}/{response_id}", params={"starting_after": 7})
    assert replay.status_code == 200
    assert response_id in replay.text

    files = client.get(f"/api/projects/{project['id']}/files", params={"path": "/"})
    assert files.status_code == 200
    assert files.json()[0]["path"] == "/report.md"
    download = client.get(f"/api/projects/{project['id']}/files/download", params={"path": "/report.md"})
    assert download.content == b"test report\n"
    assert "report.md" in download.headers["content-disposition"]
    preview = client.get(f"/api/projects/{project['id']}/files/text", params={"path": "/report.md"})
    assert preview.text == "test report\n"
    assert preview.headers["cache-control"] == "private, no-store"
    agent.file_size = 1024 * 1024
    assert client.get(f"/api/projects/{project['id']}/files/text", params={"path": "/report.md"}).status_code == 413
    agent.file_name = "archive.zip"
    agent.file_size = 12
    assert client.get(f"/api/projects/{project['id']}/files/text", params={"path": "/archive.zip"}).status_code == 415
    assert client.get(f"/api/projects/{project['id']}/files", params={"path": "/../secret"}).status_code == 400
    assert is_text_file("main.py")
    assert is_text_file("Dockerfile")
    assert not is_text_file("archive.zip")

    sessions = client.get("/api/sessions").json()
    assert sessions == [{"agent_session_id": project["sessionId"], "status": "running", "agent_version": "6", "projectId": project["id"], "projectName": "Deep Agent"}]

    deleted = client.delete(f"/api/sessions/{project['sessionId']}")
    assert deleted.status_code == 204
    assert client.get("/api/projects").json() == []
    assert agent.conversation_ids == []


def test_project_records_are_owner_scoped(api: tuple[TestClient, FakeFoundryService]) -> None:
    client, _ = api
    project = client.post("/api/projects", json={"name": "Private"}).json()

    app.dependency_overrides[get_user] = lambda: UserContext(owner_id="owner-2", display_name="Other User")

    assert client.get("/api/projects").json() == []
    assert client.get(f"/api/projects/{project['id']}").status_code == 404


def test_response_stream_uses_resilient_conversation_chain() -> None:
    calls: list[dict] = []

    class FakeResponses:
        def create(self, **kwargs):
            calls.append(kwargs)
            return iter([{"type": "response.completed", "response": {"id": "response-1", "status": "completed", "output": []}}])

        def retrieve(self, response_id, **kwargs):
            calls.append({"response_id": response_id, **kwargs})
            return iter([{"type": "response.completed", "response": {"id": response_id, "status": "completed", "output": []}}])

    service = object.__new__(FoundryService)
    service._openai = SimpleNamespace(responses=FakeResponses())

    async def consume_stream() -> list[str]:
        stream = await service.stream_response(
            "conversation-1",
            "session-1",
            "gpt-responses",
            "Steer now",
            "caresp-1",
            "auto",
        )
        chunks = [chunk async for chunk in stream]
        replay = await service.retrieve_response("caresp-1", 7)
        chunks.extend([chunk async for chunk in replay])
        return chunks

    chunks = asyncio.run(consume_stream())
    assert calls[0]["conversation"] == "conversation-1"
    assert "previous_response_id" not in calls[0]
    assert calls[0]["background"] is True
    assert calls[0]["store"] is True
    assert calls[0]["extra_headers"]["x-agent-response-id"] == "caresp-1"
    assert calls[0]["extra_headers"]["x-client-execution-mode"] == "auto"
    assert calls[1] == {"response_id": "caresp-1", "stream": True, "starting_after": 7}
    assert chunks[-1] == "data: [DONE]\n\n"


def test_sqlite_store_persists_across_instances(tmp_path) -> None:
    database_path = tmp_path / "domain.db"
    project = Project(id="project-1", ownerId="owner-1", name="Persistent", sessionId="session-1")
    conversation = ConversationMapping(id="conversation-1", ownerId="owner-1", projectId=project.id, title="Saved conversation")

    async def exercise_store() -> None:
        first = SqliteDomainStore(database_path)
        await first.save_project(project)
        await first.save_conversation(conversation)

        reopened = SqliteDomainStore(database_path)
        assert await reopened.get_project("owner-1", project.id) == project
        assert await reopened.list_conversations("owner-1", project.id) == [conversation]
        assert await reopened.list_projects("owner-2") == []

        await reopened.delete_project("owner-1", project.id)
        reopened_again = SqliteDomainStore(database_path)
        assert await reopened_again.list_projects("owner-1") == []
        assert await reopened_again.list_conversations("owner-1", project.id) == []

    asyncio.run(exercise_store())
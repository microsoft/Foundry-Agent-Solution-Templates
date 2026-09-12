import asyncio
import json
from collections.abc import AsyncIterator, Callable, Iterator
from time import monotonic
from typing import Any

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import ModelDeployment
from azure.identity import DefaultAzureCredential

from .config import Settings

# Keep aligned with https://learn.microsoft.com/azure/foundry/openai/how-to/responses#supported-models.
_RESPONSES_MODEL_VERSIONS = {
    ("gpt-6-astra", "2026-09-03"),
    ("gpt-5.6-sol", "2026-07-09"),
    ("gpt-5.6-terra", "2026-07-09"),
    ("gpt-5.6-luna", "2026-07-09"),
    ("gpt-chat-latest", "2026-08-06"),
    ("gpt-chat-latest", "2026-06-24"),
    ("gpt-chat-latest", "2026-05-28"),
    ("gpt-chat-latest", "2026-05-05"),
    ("gpt-5.5", "2026-04-24"),
    ("gpt-5.4", "2026-03-05"),
    ("gpt-5.4-pro", "2026-03-05"),
    ("gpt-5.4-mini", "2026-03-17"),
    ("gpt-5.4-nano", "2026-03-17"),
    ("gpt-5.3-chat", "2026-03-03"),
    ("gpt-5.3-codex", "2026-02-24"),
    ("gpt-5.2-codex", "2026-01-14"),
    ("gpt-5.2", "2025-12-11"),
    ("gpt-5.2-chat", "2025-12-11"),
    ("gpt-5.2-chat", "2026-02-10"),
    ("gpt-5.1-codex-max", "2025-12-04"),
    ("gpt-5.1", "2025-11-13"),
    ("gpt-5.1-chat", "2025-11-13"),
    ("gpt-5.1-codex", "2025-11-13"),
    ("gpt-5.1-codex-mini", "2025-11-13"),
    ("gpt-5-pro", "2025-10-06"),
    ("gpt-5", "2025-08-07"),
    ("gpt-5-mini", "2025-08-07"),
    ("gpt-5-nano", "2025-08-07"),
    ("gpt-5-chat", "2025-08-07"),
    ("gpt-5-chat", "2025-10-03"),
    ("gpt-5-codex", "2025-09-11"),
    ("gpt-5-codex", "2025-09-15"),
    ("gpt-4o", "2024-11-20"),
    ("gpt-4o", "2024-08-06"),
    ("gpt-4o", "2024-05-13"),
    ("gpt-4o-mini", "2024-07-18"),
    ("gpt-4.1", "2025-04-14"),
    ("gpt-4.1-mini", "2025-04-14"),
    ("gpt-4.1-nano", "2025-04-14"),
    ("o1", "2024-12-17"),
    ("o3-mini", "2025-01-31"),
    ("o3", "2025-04-16"),
    ("o4-mini", "2025-04-16"),
}
_MODEL_CACHE_SECONDS = 300.0


class FoundryService:
    def __init__(self, settings: Settings) -> None:
        credential = DefaultAzureCredential(managed_identity_client_id=settings.azure_client_id)
        self._agent_name = settings.foundry_agent_name
        self._agent_version = settings.foundry_agent_version
        self._default_model_name = settings.foundry_model_name
        self._project = AIProjectClient(endpoint=settings.foundry_project_endpoint, credential=credential)
        self._openai = self._project.get_openai_client(agent_name=self._agent_name)
        self._response_models: list[dict] = []
        self._response_models_loaded_at = 0.0

    async def create_session(self) -> str:
        kwargs: dict[str, Any] = {"agent_name": self._agent_name}
        if self._agent_version:
            from azure.ai.projects.models import VersionRefIndicator

            kwargs["version_indicator"] = VersionRefIndicator(agent_version=self._agent_version)
        session = await asyncio.to_thread(self._project.agents.create_session, **kwargs)
        return session.agent_session_id

    async def create_conversation(self, project_id: str, title: str) -> str:
        conversation = await asyncio.to_thread(
            self._openai.conversations.create,
            metadata={"app": "deep-agent", "project_id": project_id, "title": title[:100]},
        )
        return conversation.id

    async def delete_conversation(self, conversation_id: str) -> None:
        await asyncio.to_thread(self._openai.conversations.delete, conversation_id)

    async def get_session(self, session_id: str) -> dict:
        session = await asyncio.to_thread(self._project.agents.get_session, self._agent_name, session_id)
        return session.as_dict() if hasattr(session, "as_dict") else dict(session)

    async def stop_session(self, session_id: str) -> None:
        await asyncio.to_thread(self._project.agents.stop_session, self._agent_name, session_id)

    async def delete_session(self, session_id: str) -> None:
        await asyncio.to_thread(self._project.agents.delete_session, self._agent_name, session_id)

    async def list_response_models(self) -> list[dict]:
        if self._response_models and monotonic() - self._response_models_loaded_at < _MODEL_CACHE_SECONDS:
            return self._response_models
        deployments = await asyncio.to_thread(
            lambda: list(self._project.deployments.list(deployment_type="ModelDeployment"))
        )
        models = [
            {
                "name": deployment.name,
                "modelName": deployment.model_name,
                "modelVersion": deployment.model_version,
                "modelPublisher": deployment.model_publisher,
                "isDefault": deployment.name == self._default_model_name,
            }
            for deployment in deployments
            if isinstance(deployment, ModelDeployment)
            and (deployment.model_name, deployment.model_version) in _RESPONSES_MODEL_VERSIONS
        ]
        self._response_models = sorted(models, key=lambda model: (not model["isDefault"], model["name"]))
        self._response_models_loaded_at = monotonic()
        return self._response_models

    async def list_items(self, conversation_id: str) -> list[dict]:
        page = await asyncio.to_thread(self._openai.conversations.items.list, conversation_id, order="asc", limit=100)
        return [item.model_dump(mode="json") for item in page]

    async def list_session_files(self, session_id: str, path: str) -> list[dict]:
        entries = await asyncio.to_thread(
            lambda: list(
                self._project.agents.list_session_files(
                    self._agent_name,
                    session_id,
                    path=None if path == "/" else path,
                    limit=1000,
                )
            )
        )
        base_path = "" if path == "/" else path.rstrip("/")
        return [
            {
                "name": entry.name,
                "path": f"{base_path}/{entry.name}",
                "size": entry.size,
                "isDirectory": entry.is_directory,
                "modifiedAt": entry.modified_time,
            }
            for entry in entries
        ]

    async def download_session_file(self, session_id: str, path: str) -> Iterator[bytes]:
        return await asyncio.to_thread(
            self._project.agents.download_session_file,
            self._agent_name,
            session_id,
            path=path,
        )

    async def read_session_file(self, session_id: str, path: str, limit: int) -> bytes:
        content = await self.download_session_file(session_id, path)
        return await asyncio.to_thread(_read_limited, content, limit)

    async def stream_response(
        self,
        conversation_id: str,
        session_id: str,
        model_name: str,
        input_value: str | list[dict[str, object]],
        response_id: str,
        execution_mode: str,
    ) -> AsyncIterator[str]:
        request = {
            "input": input_value,
            "model": model_name,
            "background": True,
            "stream": True,
            "store": True,
            "conversation": conversation_id,
            "extra_body": {"agent_session_id": session_id},
            "extra_headers": {
                "x-agent-response-id": response_id,
                "x-client-execution-mode": execution_mode,
                "x-client-model": model_name,
            },
        }
        stream = await asyncio.to_thread(self._openai.responses.create, **request)
        return _stream_events(stream)

    async def retrieve_response(self, response_id: str, starting_after: int | None) -> AsyncIterator[str]:
        request: dict[str, Any] = {"stream": True}
        if starting_after is not None:
            request["starting_after"] = starting_after
        stream = await asyncio.to_thread(self._openai.responses.retrieve, response_id, **request)
        return _stream_events(stream)


async def _stream_events(stream: Iterator) -> AsyncIterator[str]:
    iterator = iter(stream)
    while True:
        has_item, item = await asyncio.to_thread(_next_item, iterator)
        if not has_item:
            break
        model_dump = getattr(item, "model_dump", None)
        payload = model_dump(mode="json") if callable(model_dump) else item
        yield f"data: {json.dumps(payload)}\n\n"
    yield "data: [DONE]\n\n"


def _next_item(iterator: Iterator) -> tuple[bool, object | None]:
    try:
        return True, next(iterator)
    except StopIteration:
        return False, None


def _read_limited(iterator: Iterator[bytes], limit: int) -> bytes:
    content = bytearray()
    for chunk in iterator:
        content.extend(chunk)
        if len(content) >= limit:
            raise ValueError("File is too large to preview.")
    return bytes(content)
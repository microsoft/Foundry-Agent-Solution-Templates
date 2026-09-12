from abc import ABC, abstractmethod
from pathlib import Path
import sqlite3

from azure.cosmos import exceptions
from azure.cosmos.aio import CosmosClient
from azure.identity.aio import DefaultAzureCredential

from .config import Settings
from .models import ConversationMapping, Project


class DomainStore(ABC):
    @abstractmethod
    async def list_projects(self, owner_id: str) -> list[Project]: ...

    @abstractmethod
    async def get_project(self, owner_id: str, project_id: str) -> Project | None: ...

    @abstractmethod
    async def save_project(self, project: Project) -> Project: ...

    @abstractmethod
    async def delete_project(self, owner_id: str, project_id: str) -> None: ...

    @abstractmethod
    async def list_conversations(self, owner_id: str, project_id: str) -> list[ConversationMapping]: ...

    @abstractmethod
    async def get_conversation(self, owner_id: str, conversation_id: str) -> ConversationMapping | None: ...

    @abstractmethod
    async def save_conversation(self, conversation: ConversationMapping) -> ConversationMapping: ...

    @abstractmethod
    async def delete_conversation(self, owner_id: str, conversation_id: str) -> None: ...


class InMemoryDomainStore(DomainStore):
    def __init__(self) -> None:
        self._items: dict[tuple[str, str], Project | ConversationMapping] = {}

    async def list_projects(self, owner_id: str) -> list[Project]:
        return sorted(
            [item for (owner, _), item in self._items.items() if owner == owner_id and isinstance(item, Project)],
            key=lambda item: item.updatedAt,
            reverse=True,
        )

    async def get_project(self, owner_id: str, project_id: str) -> Project | None:
        item = self._items.get((owner_id, project_id))
        return item if isinstance(item, Project) else None

    async def save_project(self, project: Project) -> Project:
        self._items[(project.ownerId, project.id)] = project
        return project

    async def delete_project(self, owner_id: str, project_id: str) -> None:
        self._items.pop((owner_id, project_id), None)
        for key, item in list(self._items.items()):
            if isinstance(item, ConversationMapping) and item.ownerId == owner_id and item.projectId == project_id:
                self._items.pop(key)

    async def list_conversations(self, owner_id: str, project_id: str) -> list[ConversationMapping]:
        return sorted(
            [item for (owner, _), item in self._items.items() if owner == owner_id and isinstance(item, ConversationMapping) and item.projectId == project_id],
            key=lambda item: item.updatedAt,
            reverse=True,
        )

    async def get_conversation(self, owner_id: str, conversation_id: str) -> ConversationMapping | None:
        item = self._items.get((owner_id, conversation_id))
        return item if isinstance(item, ConversationMapping) else None

    async def save_conversation(self, conversation: ConversationMapping) -> ConversationMapping:
        self._items[(conversation.ownerId, conversation.id)] = conversation
        return conversation

    async def delete_conversation(self, owner_id: str, conversation_id: str) -> None:
        self._items.pop((owner_id, conversation_id), None)


class SqliteDomainStore(DomainStore):
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path
        database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS domain_items (
                    owner_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    project_id TEXT,
                    updated_at TEXT NOT NULL,
                    data TEXT NOT NULL,
                    PRIMARY KEY (owner_id, id)
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS ix_domain_items_project ON domain_items (owner_id, kind, project_id, updated_at DESC)"
            )

    async def list_projects(self, owner_id: str) -> list[Project]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT data FROM domain_items WHERE owner_id = ? AND kind = 'project' ORDER BY updated_at DESC",
                (owner_id,),
            ).fetchall()
        return [Project.model_validate_json(row[0]) for row in rows]

    async def get_project(self, owner_id: str, project_id: str) -> Project | None:
        item = self._read(owner_id, project_id, "project")
        return Project.model_validate_json(item) if item else None

    async def save_project(self, project: Project) -> Project:
        self._save(project, None)
        return project

    async def delete_project(self, owner_id: str, project_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "DELETE FROM domain_items WHERE owner_id = ? AND kind = 'conversation' AND project_id = ?",
                (owner_id, project_id),
            )
            connection.execute(
                "DELETE FROM domain_items WHERE owner_id = ? AND id = ? AND kind = 'project'",
                (owner_id, project_id),
            )

    async def list_conversations(self, owner_id: str, project_id: str) -> list[ConversationMapping]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT data FROM domain_items WHERE owner_id = ? AND kind = 'conversation' AND project_id = ? ORDER BY updated_at DESC",
                (owner_id, project_id),
            ).fetchall()
        return [ConversationMapping.model_validate_json(row[0]) for row in rows]

    async def get_conversation(self, owner_id: str, conversation_id: str) -> ConversationMapping | None:
        item = self._read(owner_id, conversation_id, "conversation")
        return ConversationMapping.model_validate_json(item) if item else None

    async def save_conversation(self, conversation: ConversationMapping) -> ConversationMapping:
        self._save(conversation, conversation.projectId)
        return conversation

    async def delete_conversation(self, owner_id: str, conversation_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "DELETE FROM domain_items WHERE owner_id = ? AND id = ? AND kind = 'conversation'",
                (owner_id, conversation_id),
            )

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._database_path, timeout=10)

    def _read(self, owner_id: str, item_id: str, kind: str) -> str | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT data FROM domain_items WHERE owner_id = ? AND id = ? AND kind = ?",
                (owner_id, item_id, kind),
            ).fetchone()
        return row[0] if row else None

    def _save(self, item: Project | ConversationMapping, project_id: str | None) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO domain_items (owner_id, id, kind, project_id, updated_at, data)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(owner_id, id) DO UPDATE SET
                    kind = excluded.kind,
                    project_id = excluded.project_id,
                    updated_at = excluded.updated_at,
                    data = excluded.data
                """,
                (item.ownerId, item.id, item.kind, project_id, item.updatedAt.isoformat(), item.model_dump_json()),
            )


class CosmosDomainStore(DomainStore):
    def __init__(self, settings: Settings) -> None:
        credential = DefaultAzureCredential(managed_identity_client_id=settings.azure_client_id)
        client = CosmosClient(settings.cosmos_endpoint, credential=credential)
        self._container = client.get_database_client(settings.cosmos_database_name).get_container_client(settings.cosmos_container_name)

    async def list_projects(self, owner_id: str) -> list[Project]:
        query = "SELECT * FROM c WHERE c.ownerId = @ownerId AND c.kind = 'project' ORDER BY c.updatedAt DESC"
        items = self._container.query_items(query=query, parameters=[{"name": "@ownerId", "value": owner_id}], partition_key=owner_id)
        return [Project.model_validate(item) async for item in items]

    async def get_project(self, owner_id: str, project_id: str) -> Project | None:
        item = await self._read(owner_id, project_id)
        return Project.model_validate(item) if item and item.get("kind") == "project" else None

    async def save_project(self, project: Project) -> Project:
        await self._container.upsert_item(project.model_dump(mode="json"))
        return project

    async def delete_project(self, owner_id: str, project_id: str) -> None:
        conversations = await self.list_conversations(owner_id, project_id)
        for conversation in conversations:
            await self._container.delete_item(conversation.id, partition_key=owner_id)
        await self._container.delete_item(project_id, partition_key=owner_id)

    async def list_conversations(self, owner_id: str, project_id: str) -> list[ConversationMapping]:
        query = "SELECT * FROM c WHERE c.ownerId = @ownerId AND c.kind = 'conversation' AND c.projectId = @projectId ORDER BY c.updatedAt DESC"
        parameters = [{"name": "@ownerId", "value": owner_id}, {"name": "@projectId", "value": project_id}]
        items = self._container.query_items(query=query, parameters=parameters, partition_key=owner_id)
        return [ConversationMapping.model_validate(item) async for item in items]

    async def get_conversation(self, owner_id: str, conversation_id: str) -> ConversationMapping | None:
        item = await self._read(owner_id, conversation_id)
        return ConversationMapping.model_validate(item) if item and item.get("kind") == "conversation" else None

    async def save_conversation(self, conversation: ConversationMapping) -> ConversationMapping:
        await self._container.upsert_item(conversation.model_dump(mode="json"))
        return conversation

    async def delete_conversation(self, owner_id: str, conversation_id: str) -> None:
        await self._container.delete_item(conversation_id, partition_key=owner_id)

    async def _read(self, owner_id: str, item_id: str) -> dict | None:
        try:
            return await self._container.read_item(item_id, partition_key=owner_id)
        except exceptions.CosmosResourceNotFoundError:
            return None


def create_store(settings: Settings) -> DomainStore:
    if settings.cosmos_endpoint:
        return CosmosDomainStore(settings)
    if settings.local_development:
        return SqliteDomainStore(settings.local_store_path)
    return InMemoryDomainStore()
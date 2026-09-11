import mimetypes
from functools import lru_cache
from pathlib import PurePosixPath
from typing import Annotated
from urllib.parse import quote

from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from openai import APIStatusError

from .auth import get_user
from .config import Settings, get_settings
from .foundry import FoundryService
from .models import ConversationCreate, ConversationMapping, ModelDeploymentInfo, Project, ProjectCreate, ProjectFile, ResponseRequest, UserContext, utc_now
from .store import DomainStore, create_store

app = FastAPI(title="Deep Agent API", version="0.1.0")
TEXT_PREVIEW_LIMIT = 1024 * 1024
TEXT_FILE_SUFFIXES = {
    ".bat", ".c", ".cfg", ".conf", ".cpp", ".cs", ".css", ".csv", ".env",
    ".go", ".h", ".hpp", ".html", ".ini", ".java", ".js", ".json", ".jsx",
    ".log", ".md", ".mjs", ".ps1", ".py", ".rb", ".rs", ".sh", ".sql",
    ".toml", ".ts", ".tsx", ".txt", ".xml", ".yaml", ".yml",
}
TEXT_FILE_NAMES = {"dockerfile", "makefile", "readme", "license"}
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@lru_cache
def store() -> DomainStore:
    return create_store(get_settings())


@lru_cache
def foundry() -> FoundryService:
    return FoundryService(get_settings())


User = Annotated[UserContext, Depends(get_user)]
Store = Annotated[DomainStore, Depends(store)]
Foundry = Annotated[FoundryService, Depends(foundry)]


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/status")
async def api_status(user: User, settings: Annotated[Settings, Depends(get_settings)]) -> dict:
    return {
        "ready": True,
        "credential": "ManagedIdentity" if not settings.local_development else "DefaultAzureCredential",
        "agentName": settings.foundry_agent_name,
        "projectEndpoint": settings.foundry_project_endpoint,
        "ownerId": user.owner_id,
        "defaultModel": settings.foundry_model_name,
        "user": {"name": user.display_name or "Signed-in user", "email": user.email or ""},
    }


@app.get("/api/models", response_model=list[ModelDeploymentInfo])
async def list_models(user: User, agent: Foundry) -> list[dict]:
    del user
    return await agent.list_response_models()


@app.get("/api/projects", response_model=list[Project])
async def list_projects(user: User, domain: Store) -> list[Project]:
    return await domain.list_projects(user.owner_id)


@app.post("/api/projects", response_model=Project, status_code=status.HTTP_201_CREATED)
async def create_project(body: ProjectCreate, user: User, domain: Store, agent: Foundry) -> Project:
    session_id = await agent.create_session()
    project = Project(ownerId=user.owner_id, name=body.name, description=body.description, sessionId=session_id)
    return await domain.save_project(project)


@app.get("/api/projects/{project_id}", response_model=Project)
async def get_project(project_id: str, user: User, domain: Store) -> Project:
    return await require_project(domain, user.owner_id, project_id)


@app.delete("/api/projects/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_project(project_id: str, user: User, domain: Store, agent: Foundry) -> Response:
    project = await require_project(domain, user.owner_id, project_id)
    await delete_project_resources(domain, agent, user.owner_id, project)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/projects/{project_id}/files", response_model=list[ProjectFile])
async def list_project_files(project_id: str, user: User, domain: Store, agent: Foundry, path: str = "/") -> list[dict]:
    project = await require_project(domain, user.owner_id, project_id)
    return await agent.list_session_files(project.sessionId, session_path(path))


@app.get("/api/projects/{project_id}/files/download")
async def download_project_file(project_id: str, user: User, domain: Store, agent: Foundry, path: str) -> StreamingResponse:
    project = await require_project(domain, user.owner_id, project_id)
    safe_path = session_path(path)
    if safe_path == "/":
        raise HTTPException(status_code=400, detail="Select a file to download.")
    content = await agent.download_session_file(project.sessionId, safe_path)
    filename = PurePosixPath(safe_path).name
    return StreamingResponse(
        content,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}"},
    )


@app.get("/api/projects/{project_id}/files/text", response_class=PlainTextResponse)
async def preview_project_text_file(project_id: str, user: User, domain: Store, agent: Foundry, path: str) -> PlainTextResponse:
    project = await require_project(domain, user.owner_id, project_id)
    safe_path = session_path(path)
    if safe_path == "/":
        raise HTTPException(status_code=400, detail="Select a text file to preview.")
    file_path = PurePosixPath(safe_path)
    parent = str(file_path.parent)
    entries = await agent.list_session_files(project.sessionId, parent)
    entry = next((item for item in entries if item["name"] == file_path.name), None)
    if not entry or entry["isDirectory"]:
        raise HTTPException(status_code=404, detail="Project file not found.")
    if entry["size"] >= TEXT_PREVIEW_LIMIT:
        raise HTTPException(status_code=413, detail="Text preview is limited to files smaller than 1 MiB.")
    if not is_text_file(file_path.name):
        raise HTTPException(status_code=415, detail="This file type is download-only.")
    try:
        content = await agent.read_session_file(project.sessionId, safe_path, TEXT_PREVIEW_LIMIT)
        text = content.decode("utf-8-sig")
    except (UnicodeDecodeError, ValueError) as exc:
        raise HTTPException(status_code=415, detail="This file is not UTF-8 text.") from exc
    return PlainTextResponse(text, headers={"Cache-Control": "private, no-store"})


@app.get("/api/sessions")
async def list_sessions(user: User, domain: Store, agent: Foundry) -> list[dict]:
    sessions = []
    for project in await domain.list_projects(user.owner_id):
        try:
            session = await agent.get_session(project.sessionId)
            sessions.append({**session, "projectId": project.id, "projectName": project.name})
        except Exception:
            sessions.append({"agent_session_id": project.sessionId, "status": "unavailable", "projectId": project.id, "projectName": project.name})
    return sessions


@app.post("/api/sessions/{session_id}/stop", status_code=status.HTTP_204_NO_CONTENT)
async def stop_session(session_id: str, user: User, domain: Store, agent: Foundry) -> Response:
    await require_session_project(domain, user.owner_id, session_id)
    await agent.stop_session(session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.delete("/api/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(session_id: str, user: User, domain: Store, agent: Foundry) -> Response:
    project = await require_session_project(domain, user.owner_id, session_id)
    await delete_project_resources(domain, agent, user.owner_id, project)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/projects/{project_id}/conversations", response_model=list[ConversationMapping])
async def list_conversations(project_id: str, user: User, domain: Store) -> list[ConversationMapping]:
    await require_project(domain, user.owner_id, project_id)
    return await domain.list_conversations(user.owner_id, project_id)


@app.post("/api/projects/{project_id}/conversations", response_model=ConversationMapping, status_code=status.HTTP_201_CREATED)
async def create_conversation(project_id: str, body: ConversationCreate, user: User, domain: Store, agent: Foundry) -> ConversationMapping:
    await require_project(domain, user.owner_id, project_id)
    conversation_id = await agent.create_conversation(project_id, body.title)
    mapping = ConversationMapping(id=conversation_id, ownerId=user.owner_id, projectId=project_id, title=body.title)
    return await domain.save_conversation(mapping)


@app.get("/api/projects/{project_id}/conversations/{conversation_id}/items")
async def list_conversation_items(project_id: str, conversation_id: str, user: User, domain: Store, agent: Foundry) -> list[dict]:
    await require_mapping(domain, user.owner_id, project_id, conversation_id)
    return await agent.list_items(conversation_id)


@app.patch("/api/projects/{project_id}/conversations/{conversation_id}", response_model=ConversationMapping)
async def update_conversation(project_id: str, conversation_id: str, body: ConversationCreate, user: User, domain: Store) -> ConversationMapping:
    mapping = await require_mapping(domain, user.owner_id, project_id, conversation_id)
    mapping.title = body.title
    mapping.updatedAt = utc_now()
    await domain.save_conversation(mapping)
    return mapping


@app.delete("/api/projects/{project_id}/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(project_id: str, conversation_id: str, user: User, domain: Store, agent: Foundry) -> Response:
    await require_mapping(domain, user.owner_id, project_id, conversation_id)
    await agent.delete_conversation(conversation_id)
    await domain.delete_conversation(user.owner_id, conversation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/api/projects/{project_id}/conversations/{conversation_id}/responses")
async def create_response(
    project_id: str,
    conversation_id: str,
    body: ResponseRequest,
    user: User,
    domain: Store,
    agent: Foundry,
    model_name: Annotated[str | None, Header(alias="x-model-deployment-name")] = None,
) -> StreamingResponse:
    if not model_name:
        raise HTTPException(status_code=400, detail="Select a Responses API model.")
    models = await agent.list_response_models()
    if not any(model["name"] == model_name for model in models):
        raise HTTPException(status_code=400, detail="The selected model does not support the Responses API in this project.")
    project = await require_project(domain, user.owner_id, project_id)
    mapping = await require_mapping(domain, user.owner_id, project_id, conversation_id)
    mapping.updatedAt = utc_now()
    project.updatedAt = mapping.updatedAt
    await domain.save_conversation(mapping)
    await domain.save_project(project)
    try:
        stream = await agent.stream_response(
            conversation_id,
            project.sessionId,
            model_name,
            body.input,
            body.response_id,
            body.execution_mode,
        )
    except APIStatusError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    return StreamingResponse(stream, media_type="text/event-stream", headers={"Cache-Control": "no-cache, no-transform"})


@app.get("/api/projects/{project_id}/conversations/{conversation_id}/responses/{response_id}")
async def retrieve_response(
    project_id: str,
    conversation_id: str,
    response_id: str,
    user: User,
    domain: Store,
    agent: Foundry,
    starting_after: int | None = None,
) -> StreamingResponse:
    await require_mapping(domain, user.owner_id, project_id, conversation_id)
    try:
        stream = await agent.retrieve_response(response_id, starting_after)
    except APIStatusError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    return StreamingResponse(stream, media_type="text/event-stream", headers={"Cache-Control": "no-cache, no-transform"})


async def require_project(domain: DomainStore, owner_id: str, project_id: str) -> Project:
    project = await domain.get_project(owner_id, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found.")
    return project


def session_path(path: str) -> str:
    if not path or "\\" in path or "\x00" in path:
        raise HTTPException(status_code=400, detail="Invalid project file path.")
    parts = PurePosixPath(path).parts
    if ".." in parts:
        raise HTTPException(status_code=400, detail="Project file paths must stay within the project workspace.")
    normalized = "/" + "/".join(part for part in parts if part not in {"/", "."})
    return normalized


def is_text_file(filename: str) -> bool:
    path = PurePosixPath(filename.lower())
    media_type, _ = mimetypes.guess_type(filename)
    return path.suffix in TEXT_FILE_SUFFIXES or path.name in TEXT_FILE_NAMES or bool(media_type and media_type.startswith("text/"))


async def require_mapping(domain: DomainStore, owner_id: str, project_id: str, conversation_id: str) -> ConversationMapping:
    mapping = await domain.get_conversation(owner_id, conversation_id)
    if not mapping or mapping.projectId != project_id:
        raise HTTPException(status_code=404, detail="Conversation not found in this project.")
    return mapping


async def require_session_project(domain: DomainStore, owner_id: str, session_id: str) -> Project:
    project = next((item for item in await domain.list_projects(owner_id) if item.sessionId == session_id), None)
    if not project:
        raise HTTPException(status_code=404, detail="Session is not mapped to one of your projects.")
    return project


async def delete_project_resources(domain: DomainStore, agent: FoundryService, owner_id: str, project: Project) -> None:
    for mapping in await domain.list_conversations(owner_id, project.id):
        await agent.delete_conversation(mapping.id)
    await agent.delete_session(project.sessionId)
    await domain.delete_project(owner_id, project.id)
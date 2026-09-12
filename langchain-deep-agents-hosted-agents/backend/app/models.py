from datetime import UTC, datetime
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel, Field


def utc_now() -> datetime:
    return datetime.now(UTC)


class ProjectCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str = Field(default="", max_length=1000)


class Project(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    ownerId: str
    kind: Literal["project"] = "project"
    name: str
    description: str = ""
    sessionId: str
    createdAt: datetime = Field(default_factory=utc_now)
    updatedAt: datetime = Field(default_factory=utc_now)


class ConversationCreate(BaseModel):
    title: str = Field(default="New research", min_length=1, max_length=120)


class ConversationMapping(BaseModel):
    id: str
    ownerId: str
    kind: Literal["conversation"] = "conversation"
    projectId: str
    title: str
    createdAt: datetime = Field(default_factory=utc_now)
    updatedAt: datetime = Field(default_factory=utc_now)


class ResponseRequest(BaseModel):
    input: str | list[dict[str, object]]
    response_id: str = Field(pattern=r"^caresp_[A-Za-z0-9]{50}$")
    execution_mode: Literal["default", "auto"] = "default"
    previous_response_id: str | None = None


class ModelDeploymentInfo(BaseModel):
    name: str
    modelName: str
    modelVersion: str
    modelPublisher: str
    isDefault: bool = False


class ProjectFile(BaseModel):
    name: str
    path: str
    size: int
    isDirectory: bool
    modifiedAt: datetime


class UserContext(BaseModel):
    owner_id: str
    display_name: str | None = None
    email: str | None = None
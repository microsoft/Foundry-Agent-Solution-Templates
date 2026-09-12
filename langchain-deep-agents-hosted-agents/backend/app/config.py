from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    foundry_project_endpoint: str
    foundry_agent_name: str = "langgraph-deep-agents"
    foundry_agent_version: str | None = None
    foundry_model_name: str | None = None
    cosmos_endpoint: str | None = None
    cosmos_database_name: str = ""
    cosmos_container_name: str = ""
    local_development: bool = False
    local_owner_id: str = "local-developer"
    local_user_name: str = "Local developer"
    local_user_email: str = ""
    local_store_path: Path = Path(__file__).resolve().parents[1] / ".data" / "deep-coding.db"
    azure_client_id: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
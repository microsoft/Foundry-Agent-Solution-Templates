"""Deep research agent assembly."""

import os
from datetime import datetime
from pathlib import Path
from typing import Any

from deepagents import SubAgent, create_deep_agent
from deepagents.middleware import FilesystemMiddleware
from langchain.agents.middleware import ModelRequest, ModelResponse, TodoListMiddleware, ToolCallRequest, wrap_model_call
from langchain_core.tools import BaseTool
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.base import BaseCheckpointSaver
from langgraph.config import get_config
from langgraph.store.base import BaseStore
from langmem import create_manage_memory_tool, create_search_memory_tool

from research_agent.prompts import (
    CODING_AGENT_INSTRUCTIONS,
    RESEARCH_DELEGATION_INSTRUCTIONS,
    RESEARCHER_INSTRUCTIONS,
)
from terminal_backend import PlatformShellBackend
from utils import build_chat_model

MAX_CONCURRENT_RESEARCH_UNITS = 3
MAX_RESEARCHER_ITERATIONS = 3
TERMINAL_ENVIRONMENT_VARIABLES = (
    "COMSPEC",
    "HOME",
    "LANG",
    "PATH",
    "PATHEXT",
    "SYSTEMROOT",
    "TEMP",
    "TMP",
    "USERPROFILE",
)


@wrap_model_call
async def select_request_model(request: ModelRequest, handler) -> ModelResponse:
    """Use the deployment selected on the current Responses request."""
    config = get_config()
    response_context = (config.get("configurable") or {}).get("response_context")
    client_headers = getattr(response_context, "client_headers", {})
    deployment = client_headers.get("x-client-model")
    if deployment:
        request = request.override(model=build_chat_model(deployment))
    return await handler(request)


def build_terminal_backend() -> PlatformShellBackend:
    """Create the shell backend without forwarding application credentials."""
    terminal_environment = {
        name: os.environ[name]
        for name in TERMINAL_ENVIRONMENT_VARIABLES
        if name in os.environ
    }
    configured_root = os.environ.get("TERMINAL_ROOT")
    terminal_root = Path(configured_root or os.getcwd()).expanduser().resolve()
    terminal_root.mkdir(parents=True, exist_ok=True)
    return PlatformShellBackend(
        root_dir=terminal_root,
        env=terminal_environment,
    )


def require_tool_approval(_: ToolCallRequest) -> bool:
    """Require HITL unless the current request explicitly enables Auto mode."""
    config = get_config()
    response_context = (config.get("configurable") or {}).get("response_context")
    client_headers = getattr(response_context, "client_headers", {})
    return client_headers.get("x-client-execution-mode") != "auto"


def build_memory_tools() -> list[BaseTool]:
    """Create the official LangMem tools backed by the graph's configured store."""
    return [
        create_manage_memory_tool(
            namespace="memories",
            instructions="Save, update, or delete durable project facts, user preferences, and coding conventions. Never store secrets or transient task state.",
        ),
        create_search_memory_tool(
            namespace="memories",
            instructions="Search saved memories when prior project facts, preferences, or coding conventions may help the current task.",
        ),
    ]


def build_agent(
    model: ChatOpenAI,
    checkpointer: BaseCheckpointSaver[Any],
    memory_store: BaseStore,
    tools: list[BaseTool],
):
    """Build the coordinator and its focused research subagent."""
    backend = build_terminal_backend()
    current_date = datetime.now().strftime("%Y-%m-%d")  # noqa: DTZ005
    instructions = (
        CODING_AGENT_INSTRUCTIONS
        + "\n\n"
        + "=" * 80
        + "\n\n"
        + RESEARCH_DELEGATION_INSTRUCTIONS.format(
            max_concurrent_research_units=MAX_CONCURRENT_RESEARCH_UNITS,
            max_researcher_iterations=MAX_RESEARCHER_ITERATIONS,
        )
    )
    research_sub_agent: SubAgent = {
        "name": "research-agent",
        "description": "Delegate research to the sub-agent. Give one topic at a time.",
        "system_prompt": RESEARCHER_INSTRUCTIONS.format(date=current_date),
        "tools": tools,
        "middleware": [select_request_model, FilesystemMiddleware(backend=backend, tools=["read_file"])],
        "interrupt_on": {},
    }
    memory_tools = build_memory_tools()

    return create_deep_agent(
        model=model,
        tools=[*tools, *memory_tools],
        system_prompt=instructions,
        subagents=[research_sub_agent],
        backend=backend,
        interrupt_on={
            "execute": {
                "allowed_decisions": ["approve", "reject"],
                "when": require_tool_approval,
            }
        },
        middleware=[select_request_model, TodoListMiddleware()],
        checkpointer=checkpointer,
        store=memory_store,
        name="foundry-deep-research-agent",
    )

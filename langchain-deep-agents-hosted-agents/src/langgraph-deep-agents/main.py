# Copyright (c) Microsoft. All rights reserved.

"""Run the Deep Agents research service from source over Foundry Responses."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path

from dotenv import load_dotenv
from langchain_azure_ai.agents.hosting import (
    FoundryCheckpointSaver,
    ResponsesHostServer,
    ResponsesServerOptions,
)
from langgraph.store.sqlite import AsyncSqliteStore

from agent import build_agent
from research_agent.tools import load_tools
from utils import build_chat_model

load_dotenv()


async def main() -> None:
    state_root = Path(os.environ.get("TERMINAL_ROOT") or os.getcwd()).expanduser().resolve()
    memory_path = state_root / ".deepagents" / "memories.sqlite"
    memory_path.parent.mkdir(parents=True, exist_ok=True)
    async with (
        FoundryCheckpointSaver() as checkpointer,
        AsyncSqliteStore.from_conn_string(str(memory_path)) as memory_store,
    ):
        await memory_store.setup()
        tools = await load_tools()
        agent = build_agent(build_chat_model(), checkpointer, memory_store, tools)
        port = int(os.environ.get("PORT", "8088"))
        await ResponsesHostServer(
            agent,
            options=ResponsesServerOptions(
                resilient_background=True,
                steerable_conversations=True,
            ),
        ).run_async(port=port)


if __name__ == "__main__":
    asyncio.run(main())

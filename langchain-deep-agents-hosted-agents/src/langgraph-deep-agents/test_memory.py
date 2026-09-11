import asyncio
import tempfile
from pathlib import Path

from langchain_core.language_models.fake_chat_models import FakeMessagesListChatModel
from langchain_core.messages import AIMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.sqlite import AsyncSqliteStore
from langmem import create_manage_memory_tool, create_search_memory_tool

from agent import build_agent, build_memory_tools


class ToolModel(FakeMessagesListChatModel):
    def bind_tools(self, tools, **kwargs):
        return self


async def test_sqlite_memory_tools_persist_across_restarts() -> None:
    assert {tool.name for tool in build_memory_tools()} == {"manage_memory", "search_memory"}
    with tempfile.TemporaryDirectory() as directory:
        database_path = Path(directory) / "memories.sqlite"

        async with AsyncSqliteStore.from_conn_string(str(database_path)) as store:
            await store.setup()
            manage_memory = create_manage_memory_tool(namespace="memories", store=store)
            result = await manage_memory.ainvoke({"content": "The project uses TypeScript for frontend code."})
            assert result.startswith("created memory ")

        async with AsyncSqliteStore.from_conn_string(str(database_path)) as reopened_store:
            await reopened_store.setup()
            search_memory = create_search_memory_tool(namespace="memories", store=reopened_store)
            result = await search_memory.ainvoke({"query": "TypeScript frontend"})
            assert "TypeScript for frontend code" in result

            graph = build_agent(
                ToolModel(responses=[AIMessage(content="ready")]),
                InMemorySaver(),
                reopened_store,
                [],
            )
            assert graph is not None


if __name__ == "__main__":
    asyncio.run(test_sqlite_memory_tools_persist_across_restarts())
    print("SQLITE_MEMORY_TOOLS_TEST_OK")

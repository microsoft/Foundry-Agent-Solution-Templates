"""Offline workflow check: real graph/tools, scripted model, no Azure calls."""

import asyncio
from itertools import count
import os
from pathlib import Path
import sys
import tempfile
import shutil
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from langchain_core.language_models.fake_chat_models import FakeMessagesListChatModel
from langchain_core.messages import AIMessage, ToolMessage
from langchain_core.tools import tool
from deepagents.backends import LocalShellBackend
from deepagents.middleware.summarization import SummarizationMiddleware
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command

from agent import build_agent, think_tool


@tool
async def web_search(search_query: str) -> dict:
    """Return synthetic search evidence for offline tests only."""
    return {"results": [{"title": "Test source", "url": "https://example.com/research",
                         "content": "Synthetic search result"}]}


class ScriptedModel(FakeMessagesListChatModel):
    def bind_tools(self, tools, **kwargs):
        return self

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        for message in messages:
            if isinstance(message, ToolMessage):
                if message.status == "error":
                    raise AssertionError(f"Tool failed: {message.name}")
        return super()._generate(messages, stop=stop, run_manager=run_manager, **kwargs)


def call(name, args):
    return AIMessage(content="", tool_calls=[{
        "name": name, "args": args, "id": name, "type": "tool_call",
    }])


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.workspace = Path(self.directory.name)
        source = Path(__file__).resolve().parents[1] / "src"
        for name in ("skills", "data"):
            shutil.copytree(source / name, self.workspace / name)
        self.backend = LocalShellBackend(root_dir=self.workspace)
        self.checkpointer = InMemorySaver()
        self.config = {"configurable": {"thread_id": "test-conversation"}}

    def test_configuration_runner_loads_graph(self):
        from langchain_azure_ai.agents.hosting import run

        model = ScriptedModel(responses=[AIMessage(content="MOCK runner response")])
        config = Path(__file__).resolve().parents[1] / "src" / "langgraph.json"
        with (
            patch.dict(os.environ, {
                "FOUNDRY_PROJECT_ENDPOINT": "https://example.com/api/projects/test",
                "AZURE_AI_MODEL_DEPLOYMENT_NAME": "test-model",
                "TOOLBOX_NAME": "test-tools",
            }),
            patch("main.DefaultAzureCredential"),
            patch("main.AzureAIProjectToolbox") as toolbox,
            patch("main.AzureAIOpenAIApiChatModel", return_value=model) as model_factory,
            patch("main.create_backend", return_value=self.backend),
            patch("main.FoundryCheckpointSaver", return_value=self.checkpointer) as saver,
            patch("langchain_azure_ai.agents.hosting.ResponsesHostServer") as server,
        ):
            toolbox.return_value.get_tools = AsyncMock(return_value=[web_search])
            run.main(["--config", str(config), "--protocol", "responses",
                      "--host", "127.0.0.1", "--port", "8088"])
            graph = server.call_args.args[0]
            result = graph.invoke({"messages": [{"role": "user", "content": "Hello"}]}, self.config)
            self.assertEqual(result["messages"][-1].content, "MOCK runner response")
            self.assertEqual(model_factory.call_args.kwargs["model"], "test-model")
            server.return_value.run.assert_called_once_with(host="127.0.0.1", port=8088)
            saver.assert_called_once_with(user_isolation=True)
            toolbox.return_value.get_tools.assert_awaited_once()
            self.assertEqual(toolbox.call_args.kwargs["toolbox_name"], "test-tools")

    def test_research_workflow(self):
        report = "Synthetic search result [1].\n\nSources\n[1] Test source: https://example.com/research"
        assessment = "The returned source covers the question; no gaps remain. Stop searching."
        model = ScriptedModel(responses=[
            call("write_todos", {"todos": [{"content": "Research and report", "status": "in_progress"}]}),
            call("write_file", {"file_path": "/research_request.md", "content": "Research a topic"}),
            call("task", {"subagent_type": "research-agent", "description": "Research a topic"}),
            call("web_search", {"search_query": "test topic"}),
            call("think_tool", {"summary": assessment}),
            AIMessage(content=report),
            call("write_file", {"file_path": "/final_report.md", "content": report}),
            call("read_file", {"file_path": "/final_report.md"}),
            call("read_file", {"file_path": "/research_request.md"}),
            call("write_todos", {"todos": [{"content": "Research and report", "status": "completed"}]}),
            AIMessage(content=report),
        ])
        graph = build_agent(model, self.backend, self.checkpointer, [web_search])
        events = []

        def record_progress(summary):
            events.append("assess")
            return original_assess(summary=summary)

        original_search = web_search.coroutine
        original_assess = think_tool.func

        async def search_result(search_query):
            events.append("search")
            return await original_search(search_query=search_query)

        with (
            patch.object(web_search, "coroutine", side_effect=search_result) as search,
            patch.object(think_tool, "func", side_effect=record_progress) as assess,
        ):
            state = asyncio.run(graph.ainvoke({"messages": [{"role": "user", "content": "Research a topic"}]}, self.config))
            search.assert_awaited_once_with(search_query="test topic")
            assess.assert_called_once_with(summary=assessment)
        self.assertEqual(events, ["search", "assess"])
        self.assertEqual(state["messages"][-1].content, report)
        self.assertEqual(state["todos"][0]["status"], "completed")
        self.assertEqual((self.workspace / "final_report.md").read_text(), report)
        results = [m for m in state["messages"] if isinstance(m, ToolMessage)]
        self.assertTrue(any(m.name == "task" and "https://example.com/research" in str(m.content) for m in results))
        self.assertFalse(any(m.status == "error" for m in results))
        # Same session files survive a rebuilt graph, with isolated conversation state.
        model.responses = [call("read_file", {"file_path": "/final_report.md"}), AIMessage(content=report)]
        model.i = 0
        rebuilt = build_agent(model, self.backend, self.checkpointer, [web_search])
        continued = rebuilt.invoke({"messages": [{"role": "user", "content": "Read my report"}]}, self.config)
        self.assertGreater(len(continued["messages"]), len(state["messages"]))
        model.responses = [AIMessage(content="New conversation")]
        model.i = 0
        fresh = rebuilt.invoke({"messages": [{"role": "user", "content": "Hello"}]}, {"configurable": {"thread_id": "other-conversation"}})
        self.assertEqual(len(fresh["messages"]), 2)

    def test_toolbox_selection_and_failures(self):
        from main import create_graph

        unrelated = web_search.model_copy(update={"name": "unrelated_tool"})
        with (
            patch.dict(os.environ, {
                "FOUNDRY_PROJECT_ENDPOINT": "https://example.com/api/projects/test",
                "AZURE_AI_MODEL_DEPLOYMENT_NAME": "test-model",
                "TOOLBOX_NAME": "test-tools",
            }),
            patch("main.DefaultAzureCredential"),
            patch("main.AzureAIProjectToolbox") as toolbox,
            patch("main.AzureAIOpenAIApiChatModel"),
            patch("main.create_backend", return_value=self.backend),
            patch("main.FoundryCheckpointSaver", return_value=self.checkpointer),
            patch("main.build_agent") as build,
        ):
            toolbox.return_value.get_tools = AsyncMock(return_value=[web_search, unrelated])
            asyncio.run(create_graph())
            self.assertEqual(build.call_args.args[3], [web_search])
            build.reset_mock()
            for tools in ([], [unrelated]):
                toolbox.return_value.get_tools.return_value = tools
                with self.assertRaisesRegex(ValueError, "must expose web_search"):
                    asyncio.run(create_graph())
            toolbox.return_value.get_tools.side_effect = RuntimeError("Toolbox unavailable")
            with self.assertRaisesRegex(RuntimeError, "Toolbox unavailable"):
                asyncio.run(create_graph())
            build.assert_not_called()

    def test_shell_approval_and_rejection_including_subagents(self):
        for delegated in (False, True):
            for decision in ("approve", "reject"):
                with self.subTest(delegated=delegated, decision=decision):
                    target = self.workspace / "approved.txt"
                    target.unlink(missing_ok=True)
                    (self.workspace / "approve.py").write_text("from pathlib import Path\nPath('approved.txt').write_text('approved')\n")
                    command = f'"{sys.executable}" approve.py'
                    responses = [call("execute", {"command": command}), AIMessage(content="Done")]
                    if delegated:
                        responses = [call("task", {"subagent_type": "research-agent", "description": "Run approved check"})] + responses + [AIMessage(content="Complete")]
                    # Rejections intentionally produce an error ToolMessage.
                    model = ScriptedModel(responses=responses) if decision == "approve" else PermissiveModel(responses=responses)
                    graph = build_agent(model, self.backend, InMemorySaver(), [web_search])
                    pending = graph.invoke({"messages": [{"role": "user", "content": "Execute"}]}, self.config)
                    self.assertTrue(pending["__interrupt__"])
                    self.assertFalse(target.exists())
                    # Rebuild before resuming to verify the saved interrupt is sufficient.
                    resumed = build_agent(model, self.backend, graph.checkpointer, [web_search])
                    resumed.invoke(Command(resume={"decisions": [{"type": decision}]}), self.config)
                    self.assertEqual(target.exists(), decision == "approve")

    def test_dataset_skill(self):
        script = ("import json\nfrom collections import defaultdict\n"
                  "totals = defaultdict(lambda: [0, 0])\n"
                  "for row in json.load(open('data/quarterly_sales.json')):\n"
                  "    totals[row['product']][0] += row['revenue']\n"
                  "    totals[row['product']][1] += row['cost']\n"
                  "for product, (revenue, cost) in sorted(totals.items()):\n"
                  "    print(product, revenue, cost, revenue - cost)\n")
        model = ScriptedModel(responses=[
            call("read_file", {"file_path": "/skills/dataset-analysis/SKILL.md"}),
            call("read_file", {"file_path": "/data/quarterly_sales.json"}),
            call("write_file", {"file_path": "/analyze_sales.py", "content": script}),
            call("execute", {"command": f'"{sys.executable}" analyze_sales.py'}),
            AIMessage(content="Done"),
        ])
        graph = build_agent(model, self.backend, self.checkpointer, [web_search])
        pending = graph.invoke(
            {"messages": [{"role": "user", "content": "Analyze"}]}, self.config,
        )
        self.assertTrue(pending["__interrupt__"])
        state = graph.invoke(Command(resume={"decisions": [{"type": "approve"}]}), self.config)
        results = [m for m in state["messages"] if isinstance(m, ToolMessage)]
        self.assertIn("Fictional dataset analysis", results[0].content)
        self.assertIn("Cedar", results[1].content)
        self.assertIn("Cedar 300 180 120", results[-1].content)
        self.assertIn("Maple 360 240 120", results[-1].content)

    def test_large_shell_output_is_offloaded(self):
        (self.workspace / "large.py").write_text("print('fictional evidence ' * 5000)\n")
        model = ScriptedModel(responses=[
            call("execute", {"command": f'"{sys.executable}" large.py'}),
            AIMessage(content="Output saved"),
        ])
        graph = build_agent(model, self.backend, self.checkpointer, [web_search])
        graph.invoke({"messages": [{"role": "user", "content": "Generate synthetic output"}]}, self.config)
        state = graph.invoke(Command(resume={"decisions": [{"type": "approve"}]}), self.config)
        output = next(m for m in state["messages"] if isinstance(m, ToolMessage))
        self.assertIn("large_tool_results", output.content)
        self.assertTrue(any(p.stat().st_size > 80000 for p in self.workspace.rglob('*') if p.is_file() and "large_tool_results" in p.parts))

    def test_summarization_keeps_retrievable_history(self):
        model = ScriptedModel(responses=[AIMessage(content="Summary of fictional discussion"), AIMessage(content="Continued")])
        # Lower only the test threshold; production keeps native model-aware defaults.
        with patch("deepagents.graph.create_summarization_middleware", side_effect=lambda model, backend: SummarizationMiddleware(
            model=model, backend=backend, trigger=("messages", 4), keep=("messages", 2),
        )):
            graph = build_agent(model, self.backend, self.checkpointer, [web_search])
        messages = [{"role": "user" if i % 2 == 0 else "assistant", "content": f"Fictional observation {i}"} for i in range(7)]
        graph.invoke({"messages": messages}, self.config)
        archives = list(self.workspace.glob("conversation_history/*.md"))
        self.assertTrue(archives)
        self.assertIn("Fictional observation 0", archives[0].read_text(encoding="utf-8"))
        self.assertTrue(graph.get_state(self.config).values.get("_summarization_event"))

    def test_backend_workspace_and_environment(self):
        from main import create_backend

        with patch.dict(os.environ, {"FOUNDRY_HOSTING_ENVIRONMENT": "test", "HOME": str(self.workspace), "AZURE_CLIENT_SECRET": "fictional-test-secret"}):
            backend = create_backend()
            dataset = backend.cwd / "data/quarterly_sales.json"
            dataset.write_text("existing user data")
            create_backend()
            self.assertEqual(dataset.read_text(), "existing user data")
        self.assertEqual(backend.cwd, self.workspace / "deep-agents")
        self.assertNotIn("AZURE_CLIENT_SECRET", backend._env)
        self.assertTrue((backend.cwd / "skills/dataset-analysis/SKILL.md").is_file())

    def test_persistent_checkpoint_reloads_pending_approval(self):
        from langchain_azure_ai.agents.hosting import FoundryCheckpointSaver

        async def check():
            (self.workspace / "persist.py").write_text("from pathlib import Path\nPath('resumed.txt').write_text('ok')\n")
            model = ScriptedModel(responses=[call("execute", {"command": f'"{sys.executable}" persist.py'})])
            async with FoundryCheckpointSaver() as saver:
                graph = build_agent(model, self.backend, saver, [web_search])
                pending = await graph.ainvoke({"messages": [{"role": "user", "content": "Execute"}]}, self.config)
                self.assertTrue(pending["__interrupt__"])
            self.assertFalse((self.workspace / "resumed.txt").exists())
            async with FoundryCheckpointSaver() as saver:
                graph = build_agent(ScriptedModel(responses=[AIMessage(content="Resumed")]), self.backend, saver, [web_search])
                result = await graph.ainvoke(Command(resume={"decisions": [{"type": "approve"}]}), self.config)
                self.assertEqual(result["messages"][-1].content, "Resumed")
            self.assertEqual((self.workspace / "resumed.txt").read_text(), "ok")

        # SDK local timestamps have one-second precision and tie-break by hashed
        # item ID. Advance that clock so this test isolates durable resume.
        with (
            patch.dict(os.environ, {"FOUNDRY_HOSTING_ENVIRONMENT": "", "AGENTSERVER_STATE_ROOT": str(self.workspace / "state")}),
            patch("azure.ai.agentserver.core.storage._local_state._now", side_effect=count(1_800_000_000)),
        ):
            asyncio.run(check())


class PermissiveModel(FakeMessagesListChatModel):
    def bind_tools(self, tools, **kwargs):
        return self


if __name__ == "__main__":
    unittest.main()

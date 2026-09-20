"""Offline workflow check: real graph/tools, scripted model, no Azure calls."""

import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from langchain_core.language_models.fake_chat_models import FakeMessagesListChatModel
from langchain_core.messages import AIMessage, ToolMessage

from agent import build_agent, mock_search


class ScriptedModel(FakeMessagesListChatModel):
    def bind_tools(self, tools, **kwargs):
        return self

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        for message in messages:
            if isinstance(message, ToolMessage):
                if message.status == "error":
                    raise AssertionError(f"Tool failed: {message.name}")
                if message.name == "mock_search":
                    assert json.loads(message.content)["mock"] is True
        return super()._generate(messages, stop=stop, run_manager=run_manager, **kwargs)


def call(name, args):
    return AIMessage(content="", tool_calls=[{
        "name": name, "args": args, "id": name, "type": "tool_call",
    }])


class WorkflowTest(unittest.TestCase):
    def test_configuration_runner_loads_graph(self):
        from langchain_azure_ai.agents.hosting import run

        model = ScriptedModel(responses=[AIMessage(content="MOCK runner response")])
        config = Path(__file__).resolve().parents[1] / "src" / "langgraph.json"
        with (
            patch.dict(os.environ, {
                "FOUNDRY_PROJECT_ENDPOINT": "https://example.com/api/projects/test",
                "AZURE_AI_MODEL_DEPLOYMENT_NAME": "test-model",
            }),
            patch("main.DefaultAzureCredential"),
            patch("main.AzureAIOpenAIApiChatModel", return_value=model) as model_factory,
            patch("langchain_azure_ai.agents.hosting.ResponsesHostServer") as server,
        ):
            run.main(["--config", str(config), "--protocol", "responses",
                      "--host", "127.0.0.1", "--port", "8088"])
            graph = server.call_args.args[0]
            result = graph.invoke({"messages": [{"role": "user", "content": "Hello"}]})
            self.assertEqual(result["messages"][-1].content, "MOCK runner response")
            self.assertEqual(model_factory.call_args.kwargs["model"], "test-model")
            server.return_value.run.assert_called_once_with(host="127.0.0.1", port=8088)

    def test_mock_research_workflow(self):
        evidence = mock_search.invoke({"query": "Compare Cedar and Maple"})
        self.assertEqual(evidence, mock_search.invoke({"query": "other query"}))
        self.assertTrue(evidence["mock"])
        with self.assertRaises(ValueError):
            mock_search.invoke({"query": " "})
        report = "MOCK / FICTIONAL TEST DATA: Cedar costs 12 credits. https://example.com/mock/cedar"
        model = ScriptedModel(responses=[
            call("write_todos", {"todos": [{"content": "Research and report", "status": "in_progress"}]}),
            call("write_file", {"file_path": "/research_request.md", "content": "Compare Cedar and Maple"}),
            call("task", {"subagent_type": "research-agent", "description": "Compare Cedar and Maple"}),
            call("mock_search", {"query": "Cedar and Maple"}),
            AIMessage(content=json.dumps(evidence)),
            call("write_file", {"file_path": "/final_report.md", "content": report}),
            call("read_file", {"file_path": "/final_report.md"}),
            call("write_todos", {"todos": [{"content": "Research and report", "status": "completed"}]}),
            AIMessage(content=report),
        ])
        graph = build_agent(model)
        with patch.object(mock_search, "func", wraps=mock_search.func) as search:
            state = graph.invoke({"messages": [{"role": "user", "content": "Compare Cedar and Maple"}]})
            search.assert_called_once_with(query="Cedar and Maple")
        self.assertEqual(state["messages"][-1].content, report)
        self.assertEqual(state["todos"][0]["status"], "completed")
        self.assertEqual(state["files"]["/final_report.md"]["content"], report)
        results = [m for m in state["messages"] if isinstance(m, ToolMessage)]
        self.assertTrue(any(m.name == "task" and "FICTIONAL" in str(m.content) for m in results))
        self.assertFalse(any(m.status == "error" for m in results))
        # A second independent request must not inherit the first request's files.
        model.responses = [AIMessage(content="No previous files.")]
        model.i = 0
        fresh = graph.invoke({"messages": [{"role": "user", "content": "Hello"}]})
        self.assertFalse(fresh.get("files"))


if __name__ == "__main__":
    unittest.main()

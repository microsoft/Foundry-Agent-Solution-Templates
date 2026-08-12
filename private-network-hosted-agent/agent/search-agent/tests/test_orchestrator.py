import json
from types import SimpleNamespace

from search_agent.orchestrator import SearchAgent


class ToolCall:
    type = "function_call"
    name = "search_private_knowledge"
    call_id = "call-1"
    arguments = json.dumps({"question": "canary"})

    def model_dump(self, exclude_none: bool):
        assert exclude_none
        return {
            "type": self.type,
            "name": self.name,
            "call_id": self.call_id,
            "arguments": self.arguments,
        }


class FakeResponses:
    def __init__(self) -> None:
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if len(self.calls) == 1:
            return SimpleNamespace(output=[ToolCall()])
        return SimpleNamespace(output_text="The canary is blue [1].")


def test_agent_executes_one_search_and_appends_citations() -> None:
    responses = FakeResponses()
    search = lambda _query: [
        {
            "id": "canary",
            "title": "Canary",
            "content": "The canary is blue.",
            "source_url": "https://example.test/canary",
        }
    ]
    agent = SearchAgent(responses, "model", search)

    answer = agent.answer([{"role": "user", "content": "What color?"}])

    assert "The canary is blue" in answer
    assert "[Canary](https://example.test/canary)" in answer
    assert responses.calls[0]["store"] is False
    assert responses.calls[1]["tool_choice"] == "none"


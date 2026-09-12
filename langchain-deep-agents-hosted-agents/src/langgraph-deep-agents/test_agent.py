from types import SimpleNamespace
from unittest.mock import patch

from agent import require_tool_approval


def test_require_tool_approval_defaults_to_enabled() -> None:
    with patch("agent.get_config", return_value={}):
        assert require_tool_approval(SimpleNamespace())


def test_require_tool_approval_disables_hitl_in_auto_mode() -> None:
    response_context = SimpleNamespace(client_headers={"x-client-execution-mode": "auto"})
    with patch("agent.get_config", return_value={"configurable": {"response_context": response_context}}):
        assert not require_tool_approval(SimpleNamespace())
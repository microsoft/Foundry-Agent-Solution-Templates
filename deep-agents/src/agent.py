"""Small Deep Research adaptation; see ../ATTRIBUTION.md."""

import json
from pathlib import Path

from deepagents import create_deep_agent
from deepagents.backends import LocalShellBackend
from langchain.agents.middleware import TodoListMiddleware
from langchain_core.language_models import BaseChatModel
from langchain_core.tools import tool
from langgraph.types import Checkpointer


@tool
def mock_search(query: str) -> dict:
    """Return bundled FICTIONAL Cedar/Maple evidence, never live web search.

    Only supports the demonstration comparison of Cedar and Maple document
    processing. Every nonempty query returns the same two labeled fixtures.
    """
    if not query.strip():
        raise ValueError("A nonempty research query is required.")
    return {
        "mock": True,
        "scope": "Fictional Cedar and Maple comparison only; no live web search.",
        "results": json.loads(
            Path(__file__).with_name("mock_evidence.json").read_text(encoding="utf-8")
        ),
    }


WORKFLOW = """Coordinate research and dataset analysis using FICTIONAL TEST DATA only.
For dataset analysis, first read /skills/dataset-analysis/SKILL.md and follow it.
Use the research workflow below for Cedar/Maple research questions.
1. Plan with write_todos and save the question to /research_request.md.
2. Delegate evidence gathering to research-agent with task; use one researcher
   by default, at most two for independent comparisons. Do not research yourself.
3. Synthesize the returned evidence, citing only the exact fixture source URLs.
4. Write /final_report.md, then read it and verify it answers the saved request.
5. Complete the todos and return the entire report inline in the final response.
Clearly label both the report and citations MOCK / FICTIONAL TEST DATA; the URLs
are fixture identifiers, not independently verified sources. Research evidence
concerns Cedar and Maple document processing; the analysis skill has a separate
fictional quarterly sales dataset. Explain missing evidence
for other topics; never invent findings. Stop after two delegation rounds.
Working files are shared within the Hosted Agent session. Conversation state is
checkpointed separately. Do not promise cross-session memory or live search.
Shell commands require human approval. Never ask for credentials, inspect the
host environment, access paths outside the workspace, or download packages.
File tools use virtual absolute paths; shell commands use workspace-relative
paths. Return results inline even when also writing a workspace artifact.
"""

RESEARCHER = """You are the focused research-agent for FICTIONAL TEST DATA.
Call mock_search for your assigned topic, then return relevant facts and exact
source URLs. Label findings and sources MOCK. The tool returns the same finite
Cedar/Maple fixture set each time, so one search is sufficient. State evidence
gaps for unsupported questions. Do not invent product facts or fetch URLs.
"""


def build_agent(model: BaseChatModel, backend: LocalShellBackend, checkpointer: Checkpointer):
    """Keep the upstream planner / researcher / report flow on a supplied model."""
    return create_deep_agent(
        model=model,
        system_prompt=WORKFLOW,
        backend=backend,
        checkpointer=checkpointer,
        skills=["/skills/"],
        interrupt_on={"execute": {"allowed_decisions": ["approve", "reject"]}},
        middleware=[TodoListMiddleware()],
        subagents=[{
            "name": "research-agent",
            "description": "Research one topic using the labeled mock evidence.",
            "system_prompt": RESEARCHER,
            "tools": [mock_search],
        }],
        name="foundry-deep-research",
    )

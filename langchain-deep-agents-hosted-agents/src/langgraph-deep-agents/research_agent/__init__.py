"""Research subagent prompts and tools."""

from research_agent.prompts import (
    CODING_AGENT_INSTRUCTIONS,
    RESEARCH_DELEGATION_INSTRUCTIONS,
    RESEARCHER_INSTRUCTIONS,
)
from research_agent.tools import load_tools

__all__ = [
    "CODING_AGENT_INSTRUCTIONS",
    "RESEARCH_DELEGATION_INSTRUCTIONS",
    "RESEARCHER_INSTRUCTIONS",
    "load_tools",
]

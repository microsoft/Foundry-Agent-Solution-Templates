"""Claims triage hosted agent: two read-only tools and one approval-gated action."""

import json
import logging
import os
from pathlib import Path
from typing import Annotated

from agent_framework import Agent, tool
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from pydantic import Field

logger = logging.getLogger("claims-triage")
CLAIMS = {c["claim_id"]: c for c in json.loads((Path(__file__).parent / "claims.json").read_text())}
INSTRUCTIONS = (
    "You help a claims handler triage synthetic insurance claims. Call a tool before you cite a claim, "
    "never invent figures, and keep answers short. Escalate only when the user asks you to. "
    "If the user rejects an escalation, do not retry it: say it was not escalated and ask what to do next."
)


@tool
def list_flagged_claims() -> list[dict]:
    """List open claims that automated checks flagged for review."""
    return [
        {"claim_id": c["claim_id"], "amount": c["amount"], "flag_reason": c["flag_reason"]}
        for c in CLAIMS.values()
        if c["flagged"] and c["status"] == "open"
    ]


@tool
def lookup_claim(claim_id: Annotated[str, Field(description="Claim identifier in CLM-nnnn format.")]) -> dict:
    """Return the full record for one claim."""
    return CLAIMS.get(claim_id.upper(), {"error": f"No claim {claim_id}."})


@tool(approval_mode="always_require")
def escalate_claim(
    claim_id: Annotated[str, Field(description="Claim identifier in CLM-nnnn format.")],
    reason: Annotated[str, Field(description="Why the claim needs a senior investigator.")],
) -> dict:
    """Escalate a claim to the special investigations unit. A human must approve this action."""
    claim = CLAIMS.get(claim_id.upper())
    if claim is None:
        return {"error": f"No claim {claim_id}."}
    claim["status"] = "escalated"
    logger.info("Escalated %s: %s", claim["claim_id"], reason)
    return {"claim_id": claim["claim_id"], "status": "escalated", "reference": f"SIU-{claim['claim_id'][4:]}"}


def build_agent() -> Agent:
    # Called per request, not at startup, so /readiness answers even when configuration is missing.
    # A startup crash surfaces in Foundry only as HTTP 424 session_not_ready.
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=DefaultAzureCredential(),
    )
    return Agent(
        client=client,
        instructions=INSTRUCTIONS,
        tools=[list_flagged_claims, lookup_claim, escalate_claim],
        default_options={"store": False},  # The hosting layer owns conversation history.
    )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    ResponsesHostServer(build_agent).run()

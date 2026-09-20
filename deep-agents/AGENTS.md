# Coding Agent Instructions

This project is a Microsoft Foundry Hosted Agent built with LangChain and
Deep Agents. It exposes the Responses protocol and demonstrates a research
workflow using bundled fictional evidence.

## Key files

- `azure.yaml` — native azd provisioning for the Foundry project, model and
  Hosted Agent
- `src/main.py` — Foundry model wrapper and graph factory
- `src/langgraph.json` — graph selection for the SDK configuration-driven runner
- `src/agent.py` — planning, research delegation, mock search and report workflow
- `src/mock_evidence.json` — fictional research fixtures
- `src/requirements.txt` — pinned direct dependencies
- `tests/test_agent.py` — offline graph workflow and request-isolation check
- `docs/cost.md` — cost components and quota considerations
- `ATTRIBUTION.md` — upstream sources and license notices

## Preserve these invariants

- Keep mock evidence and generated reports clearly labeled as fictional.
  Fixture URLs use reserved example domains; they are not live sources.
- Keep the default workflow usable without an external search API key.
- Use the SDK model and Responses hosting adapters rather than custom HTTP
  hosting. Retain managed-identity authentication in the hosted runtime.
- Keep the local `startupCommand` and hosted `codeConfiguration.entryPoint`
  on the same SDK runner, with the graph selected through `src/langgraph.json`.
- State-backed files last for one request. Return the report inline; do not
  claim durable files, checkpoint recovery or cross-conversation memory.
- Keep credentials, local Azure settings, resource identifiers and generated
  output out of tracked files. Keep content recording disabled by default.
- Preserve upstream attribution and license notices for adapted material.

## Development workflow

Run commands from `deep-agents`, using the Python environment described in
the README:

```powershell
python -m pip install -r src/requirements.txt
python -m unittest discover -s tests -v
```

For local development with a configured Foundry model, use
`azd ai agent run deep-agents`. Deploy with `azd up`, or `azd deploy` for source
updates, and follow the README's verification workflow. Distinguish offline
test results from actual Azure deployment and model behavior.

## References

- [Microsoft Foundry hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
- [Upstream examples and attribution](ATTRIBUTION.md)

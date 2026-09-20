# Coding Agent Instructions

This Deep Agents template demonstrates sales-informed marketing planning on Foundry.

## Key files

- `azure.yaml` — project, model, Toolbox and Hosted Agent deployment
- `src/main.py` and `src/langgraph.json` — graph factory and runner configuration
- `src/agent.py` — research prompts, tools, approvals and file permissions
- `src/skills/` and `src/data/` — analysis skill and fictional inputs
- `tests/test_agent.py` — offline agent tests
- `docs/validation.md` — remote verification and approval procedure

## Preserve these invariants

- Load only `web_search` through the Toolbox adapter. Keep search evidence
  separate from the fictional analysis dataset; retain source citations.
- Keep research assessments on the subagent. Search budgets are prompt guidance.
- Keep model deployment names literal and aligned with the agent's default.
- Keep local and hosted startup commands on the same configuration-driven runner.
- Allow file-tool writes only under `/work/`; keep `write_file` and `execute` approval enabled for
  all agents and pass only the shell environment allowlist. File permissions
  do not sandbox approved code.
- Keep concise stage/approval updates and separate simulated company metrics,
  external evidence and assumptions. Do not invent marketing ROI/CAC or budgets.
- Seed only missing skill/data files. Preserve session files and checkpoint
  user isolation. Keep credentials and deployment identifiers out of Git.
- Keep content recording disabled and use hosting SDK telemetry initialization.
- Keep checkpoint write pacing confined to the persisted-approval test.
- Preserve [upstream attribution](ATTRIBUTION.md).

## Development workflow

From `deep-agents`, with dependencies installed:

```powershell
python -m unittest discover -s tests -v
```

Use `azd ai agent run deep-agents` locally and `azd deploy deep-agents` for
source updates. Follow [Validation](docs/validation.md) for remote checks.

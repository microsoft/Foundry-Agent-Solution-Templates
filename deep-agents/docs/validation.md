# Validation

Run all commands from the `deep-agents` template directory, not `docs/`.
Follow the [deployment instructions](../README.md#run-the-agent) first for remote
checks. Offline tests use a scripted model; remote checks exercise real model
and search calls and can incur charges.

## Research workflow

```powershell
azd ai agent invoke deep-agents --new-session --new-conversation --protocol responses "Research how Microsoft Foundry hosted agents handle session storage. Use official documentation, plan the work, delegate research, save and read the final report, and return the report inline with source URLs."
```

The same prompt can be used in the deployed agent's Foundry playground.
When testing a newly deployed version, add `--version <version>` and start a
new session and conversation; existing sessions remain bound to their version.
Verify the following:

- The run completes through the Responses endpoint. Tool activity shows
  `write_todos`, `task`, `web_search`, `write_file` and `read_file`.
- `web_search` returns real sources through Foundry Toolbox; inspect the tool
  output and open the cited URLs to check the report's claims.
- The inline report cites returned source URLs and states evidence gaps or
  search failures. It does not substitute fictional sales data for web evidence.

Agent behavior is model-driven; inspect tool activity as well as final prose.
Offline tests do not verify Azure connectivity or model-generated results.
After source changes, use `azd deploy` and repeat the same verification prompt.

## Research strategy

To check research strategy, start a fresh session and conversation for each
case. Inspect subagent tool activity as well as the final report:

| Case | Example prompt | Expected behavior |
|---|---|---|
| Simple fact | What happens to a Foundry hosted agent's HOME files when its session stops? Use official documentation. | Search, assess with `think_tool`, and stop once evidence answers the question; no need to exhaust the budget. |
| Multiple aspects | Compare hosted session files, conversation checkpoints and long-term memory in Foundry, including lifetime and scope. | Delegate independent aspects, narrow searches for missing evidence and consolidate citations across researchers. |
| Evidence gap | Find an official guarantee that every arbitrary shell side effect executes exactly once after a hosted-agent crash. If unavailable, report that gap. | Assess insufficient/repeated evidence, stop at the prompt budget and explicitly report what could not be verified. |

Compare the same prompts on the preceding agent version using `--version` and
new sessions. Check search/assessment order, citation support, repeated queries
and disclosed gaps; do not treat fewer calls alone as higher quality. Scripted
tests verify tool wiring, not whether a live model always follows these rules.

## Analysis and execution approval

Ask: "Use the dataset-analysis skill to analyze the bundled fictional sales.
Run the calculation with Python after approval, then save and return a report."
Verify `read_file` loads the skill, `write_file` creates the script and `execute`
pauses before running. Approve only the expected local calculation. The totals
are Cedar: revenue 300, cost 180, profit 120; Maple: 360, 240, 120; combined:
660, 420, 240 fictional credits. Reject a separate execution and verify that
the command does not run. Approval also applies to delegated subagents.

The pinned SDK accepts LangChain's structured resume through the Responses API:
send a `function_call_output` using the pending approval's call ID, in the same
session and conversation. Its `output` is the JSON string
`{"resume":{"decisions":[{"type":"approve"}]}}` (or `reject`).
Use native PowerShell REST for the single-command demo
below. Supply the pending response and session IDs from your own invocation;
inspect the command before choosing a decision. Do not share tokens or output
containing resource identifiers.

```powershell
$responseId = '<pending-response-id>'
$sessionId = '<same-agent-session-id>'
$agent = azd ai agent show deep-agents -o json | ConvertFrom-Json
$pending = azd ai agent invocations show -n deep-agents --protocol responses --id $responseId -o json | ConvertFrom-Json
$calls = @($pending.output | Where-Object { $_.type -eq 'function_call' -and $_.name -eq '__hosted_agent_adapter_interrupt__' })
if ($calls.Count -ne 1 -or -not $pending.conversation.id) { throw 'Expected one pending interrupt and a conversation ID.' }
$actions = @(($calls[0].arguments | ConvertFrom-Json).value.action_requests)
if ($actions.Count -ne 1 -or $actions[0].name -ne 'execute') { throw 'This example handles one execute action only.' }
$actions[0] | ConvertTo-Json -Depth 10
$decision = Read-Host 'Review the command above, then enter approve or reject'
if ($decision -notin @('approve', 'reject')) { throw 'No decision submitted.' }
$resume = @{ resume = @{ decisions = @(@{ type = $decision }) } } | ConvertTo-Json -Depth 10 -Compress
$body = @{
    conversation = @{ id = $pending.conversation.id }
    agent_session_id = $sessionId
    input = @(@{ type = 'function_call_output'; call_id = $calls[0].call_id; output = $resume })
    stream = $false
    store = $true
} | ConvertTo-Json -Depth 10
$token = az account get-access-token --resource https://ai.azure.com/ --query accessToken -o tsv
$result = Invoke-RestMethod -Method Post -Uri $agent.agent_endpoints.responses -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
$result.output
```

## Continuity and recovery

In the same conversation, ask to read `/work/analysis_report.md` and explain a total.
Repeat after the session idles/resumes: both the file and conversation should
remain available. A different conversation in that session shares files but
not checkpointed messages; a new session should not contain the old report.
Recovery resumes the saved graph state, but arbitrary shell side effects are
not transactional or guaranteed to execute exactly once.
Automatic in-flight recovery additionally requires a stored background
response (`background=true`, `store=true`); ordinary foreground requests do not
enable that path. A persisted approval can be resumed after restarting its
session with the structured request above. Session files can be downloaded
with `azd ai agent files download deep-agents/work/analysis_report.md` using the
same session ID.

## Context offloading and summarization

Deep Agents automatically offloads large tool results to `/work/large_tool_results/`
and archives summarized history under `/work/conversation_history/`. Offline tests
exercise both using synthetic output and a reduced summarization threshold.
Production keeps the native model-aware thresholds; a short demo should not
be expected to trigger summarization.

## Offline tests

Use Python 3.13 and install dependencies as described in
[Local development](../README.md#local-development):

```powershell
py -3.13 -m venv .venv
.venv/Scripts/python -m pip install -r src/requirements.txt
.venv/Scripts/python -m unittest discover -s tests -v
```

On Linux/macOS use `python3.13` and `.venv/bin/python`. This check drives the
real graph with a scripted model and an async test-only search stub through
planning, delegation, cited tool results,
file writing/reading, report completion, approved/rejected execution (including
subagents), saved-approval reload with the SDK's local persistent state store,
conversation isolation, output offloading and history summarization. It makes
no Azure calls and does not verify cloud restart recovery or live search quality.
It also checks SDK runner loading, Toolbox tool selection and startup failures.
The persistence test advances the SDK local store's clock deterministically:
its second-resolution timestamps otherwise order simultaneous writes by ID.
That test does not verify latest-checkpoint ordering in the real service.

---
name: dataset-analysis
description: Analyze the bundled fictional quarterly sales dataset with Python and produce a verifiable report.
---

# Fictional dataset analysis

1. Plan with `write_todos`. Read `/data/quarterly_sales.json`; all values are
   simulated credits, unrelated to the research fixtures' product pricing.
2. Write `/work/analyze_sales.py` using only Python's `json` and standard library.
   Calculate revenue, cost and profit by product, plus the combined totals.
   Read `data/quarterly_sales.json` relative to the shell working directory.
   Write any generated outputs to `work/`, for example `work/analysis_payload.json`.
3. Request `execute` with `python work/analyze_sales.py`. Wait for human approval.
   If rejected, do not retry execution or delegate it; explain that it was
   rejected. Do not fabricate calculated results or an executed script.
4. After successful execution, write `/work/analysis_report.md` with the results,
   label it MOCK / FICTIONAL TEST DATA, read it back and complete the todos.
5. Return the full report inline. Keep the source dataset and skill unchanged.
   Do not install dependencies, use the network or inspect host configuration.

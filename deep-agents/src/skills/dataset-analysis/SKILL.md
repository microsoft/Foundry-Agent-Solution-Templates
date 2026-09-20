---
name: dataset-analysis
description: Calculate fictional Cedar/Maple sales metrics to support marketing priorities.
---

# Fictional dataset analysis

1. Read `/data/quarterly_sales.json` before coding. It is a JSON list of
   records with `product`, `quarter` (Q1/Q2), `revenue` and `cost`.
   Validate fields and numeric values; no alternate-schema fallbacks.
2. Write a short standard-library script at `/work/analyze_sales.py`.
   Use plain loops/dictionaries and `sum`. Initialize accumulators before
   reading them, quote string keys, and never call `.get()` on the input list.
   Calculate per-product/quarter and combined revenue, cost and profit, plus:
   - Growth (%) = 100 × (Q2 revenue - Q1 revenue) / Q1 revenue.
   - Overall margin (%) = 100 × total profit / total revenue; do not average
     quarterly margins.
   - Revenue share (%) = 100 × product revenue / combined revenue.
   For zero denominators return unavailable; round only displayed values.
   Assert totals reconcile, profit = revenue - cost, and defined shares sum
   approximately to 100%. Derive all values from data, not hardcoded answers.
3. Print JSON metrics; let the coordinator write the narrative. Python reads
   `data/quarterly_sales.json` and writes only `work/`-relative output paths.
   Read the script back, check its schema, keys, initialization and paths.
   Tell the user what it will do, then call `execute` with
   `python work/analyze_sales.py` to trigger approval. Do not ask for chat consent.
4. If rejected, stop; do not retry or delegate execution. If it fails, explain
   the actual error, fix it, review the change and request fresh approval.
   Mark calculation complete only after successful execution and valid output.
5. Write/read `/work/analysis_report.md` labeled FICTIONAL TEST DATA. For a
   marketing request, use it in the integrated `/work/final_report.md`; otherwise
   return it inline. Sales data alone cannot establish marketing causation,
   ROI or CAC. Never invent missing spend, customers, conversions or budgets.
   Leave inputs/skills unchanged; do not install packages or access the network.

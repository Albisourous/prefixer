# Metrics

The point of tracking is that prefix claims stay honest. No baseline, no
"improvement" — only a story.

## The log

`.prefixer/metrics.jsonl`, one line per task, committed with the repo:

```json
{"ts":"2026-10-26","task":"find-session-expiry","searches":3,"tool_calls":4,"first_try_hit":true,"est_tokens":1400}
```

One schema, optional fields. Every writer emits the same keys it can
honestly fill:

| field | required? | meaning |
|-------|-----------|---------|
| `ts` | yes | date, ISO |
| `task` | yes | short tag for the task |
| `searches` | yes | search calls this line covers |
| `est_tokens` | yes | rough tokens, chars/4 — an estimate, label it as one |
| `hits` | per-search lines | result lines the search returned |
| `tool_calls` | task lines | total tool calls in the task |
| `first_try_hit` | task lines | answer found inside the first scoped search |
| `baseline` | optional | `true` marks the pre-change probe line |
| `notes` | optional | free text |

`scripts/measure_search.sh` wraps a search command and appends a
per-search line (`hits`) automatically — use it when you want real counts
instead of estimates. `--baseline` tags the line as the pre-change probe.
Hand-written task lines carry `tool_calls` and `first_try_hit`.

**Git handling:** `metrics.jsonl` is local telemetry — the scaffold writes
a `.prefixer/.gitignore` for it. Commit it only if the team wants shared
trend data. `namespaces.md` is the opposite: always committed, because it
is the shared prefix every session and teammate benefits from.

## Session metrics

- **Searches per task** — should drop as the namespace map does its job.
- **Tool calls per task** — the number users feel.
- **First-try hit rate** — share of tasks solved inside the first scoped
  search. The metric the map exists to raise.
- **Estimated tokens per exploration** — trend line, not gospel.

## Pipeline metrics

When the work is an index or RAG corpus, use real retrieval vocabulary:

- **Hit@k / recall@k / nDCG@k** — BEIR conventions.
- **Context precision / context recall** — RAGAS names for whether the
  retrieved context is right.
- **Intra-cluster cosine** — the cheap prefix A/B: embed a 10% sample with
  and without prefixes, compare mean cosine to each doc's nearest neighbors.
  Tighter means the prefixes are pulling.

## Baseline → apply → report

1. Record baseline rows *before* recommending changes — either a fixed
   probe (`measure_search.sh --baseline orientation -- grep -rn "TODO" .`)
   or the first few un-mapped tasks counted by hand.
2. Apply the map / prefixes / ordering.
3. Record the same tasks after.
4. Report as a small table:

```
task               searches  tool_calls  first_try   est_tokens
baseline avg       8.4       11.2        22%         6,100
with prefixer      3.1       4.6         71%         1,900
```

5. If the delta is flat, say so. The map may need better namespaces, or the
  task class may not be search-bound. Flat results are findings too.

## Proving the savings — `eval_scope.sh`

The load-bearing number is **bytes of search output the agent did not have
to read**. `scripts/eval_scope.sh <repo> <pattern> <prefix>` runs one grep
at repo root and the same grep inside the namespace's globs, then reports
the delta:

```json
{"task":"eval-scope","ns":"gen","pattern":"seed","root_hits":676,"root_bytes":2808952,"ns_hits":245,"ns_bytes":28245,"pct_saved":98,"est_tokens_saved":695176}
```

`est_tokens_saved` is `bytes_saved / 4`. `--log` appends the line to
`.prefixer/metrics.jsonl`. Run it on a few representative queries after a
map lands — that is the number in the README claims, not a vibes estimate.
A flat `pct_saved` means the namespace is too wide or the pattern was never
search-bound; adjust the row and measure again.

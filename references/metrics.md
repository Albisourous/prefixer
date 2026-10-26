# Metrics

The point of tracking is that prefix claims stay honest. No baseline, no
"improvement" — only a story.

## The log

`.prefixer/metrics.jsonl`, one line per task, committed with the repo:

```json
{"ts":"2026-10-26","task":"find-session-expiry","searches":3,"tool_calls":4,"first_try_hit":true,"est_tokens":1400}
```

| field | meaning |
|-------|---------|
| `ts` | date, ISO |
| `task` | short tag for the task |
| `searches` | grep/glob/search calls made |
| `tool_calls` | total tool calls in the task |
| `first_try_hit` | found the answer inside the first scoped search |
| `est_tokens` | rough tokens consumed, chars/4 — an estimate, label it as one |
| `notes` | optional, free text |

`scripts/measure_search.sh` wraps a search command and appends a line
automatically — use it when you want real counts instead of estimates.

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

1. Record baseline rows *before* recommending changes (§13 of the skill).
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

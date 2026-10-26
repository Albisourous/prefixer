# Metrics

The point of tracking is that prefix claims stay honest. No baseline, no
"improvement"; only a story.

## The log

`.prefixer/metrics.jsonl`, one line per task, committed with the repo:

```json
{"ts":"2026-10-26T14:03:11Z","task":"find-session-expiry","searches":3,"tool_calls":4,"first_try_hit":true,"est_tokens":1400}
```

One schema, optional fields. Every writer emits the same keys it can
honestly fill:

| field | required? | meaning |
|-------|-----------|---------|
| `ts` | yes | date+time, ISO-8601 UTC (`2026-10-26T14:03:11Z`); date-only loses same-day ordering |
| `task` | yes | short tag for the task |
| `searches` | yes | search calls this line covers |
| `est_tokens` | yes | rough tokens, chars/4; an estimate, label it as one |
| `scope` | per-search lines | the glob or dir the search ran in, `root` when unscoped; the field that makes "scoped beats root" measurable |
| `hits` | per-search lines | result lines the search returned |
| `tool_calls` | task lines | total tool calls in the task |
| `first_try_hit` | task lines | answer found inside the first scoped search; agent judgment, or `--hit`/`--miss` on the script |
| `ns` | search.sh lines | the namespace tag the search started in |
| `pattern` | search.sh lines | the searched pattern; needed to judge a map gap honestly |
| `widened_to` | optional | where a widened search found hits: a tag, `root`, or `none` |
| `hit_dirs` | optional | `dir:count` list of where widened hits clustered; the map-gap signal `suggest_map.sh` reads |
| `baseline` | optional | `true` marks the pre-change probe line |
| `baseline_excluded` | eval lines | `true` when every scoped file lives inside dirs the baseline grep skips; `pct_saved` is `null` then |
| `error` | optional | `true` marks a probe whose command failed; `hits` is unreliable |
| `exit` | optional | the probe command's exit status when `error` is set |
| `notes` | optional | free text |

`scripts/search.sh` is the instrumented path: `search.sh <ns> <pattern>`
searches inside the tag's globs, widens one level on a miss, and appends
the per-search line with `ns`, `pattern`, `hits`, `first_try_hit`, and,
when it had to widen, `widened_to` plus `hit_dirs` naming the
directories the hits actually landed in. Those fields are what
`scripts/suggest_map.sh` reads to propose new rows, so searches run
through `search.sh` feed the flywheel automatically.

`scripts/measure_search.sh` wraps a search command and appends a
per-search line (`hits`, `scope`) automatically; use it when you want
real counts instead of estimates. The log always lands at the repo root:
the nearest `.prefixer/` walking up, else the git toplevel; running it
from a subdirectory cannot create a stray `.prefixer/`. Flags:
`--baseline` tags the line as the pre-change probe, `--scope <glob>`
overrides scope inference (default: the command's path args, `root` when
none), `--hit`/`--miss` records `first_try_hit`. A probe whose command
exits nonzero is logged with `"error":true` and its exit status; a crashed
search is not a 0-hit search, and phantom misses would pollute the
baseline. Hand-written task lines carry `tool_calls` and `first_try_hit`.

**Git handling:** `metrics.jsonl` is local telemetry; the scaffold writes
a `.prefixer/.gitignore` for it. Commit it only if the team wants shared
trend data. `namespaces.md` is the opposite: always committed, because it
is the shared prefix every session and teammate benefits from.

## Session metrics

- **Searches per task**: should drop as the namespace map does its job.
- **Tool calls per task**: the number users feel.
- **First-try hit rate**: share of tasks solved inside the first scoped
  search. The metric the map exists to raise.
- **Estimated tokens per exploration**: trend line, not gospel.

## Pipeline metrics

When the work is an index or RAG corpus, use real retrieval vocabulary:

- **Hit@k / recall@k / nDCG@k**: BEIR conventions.
- **Context precision / context recall**: RAGAS names for whether the
  retrieved context is right.
- **Intra-cluster cosine**: the cheap prefix A/B: embed a 10% sample with
  and without prefixes, compare mean cosine to each doc's nearest neighbors.
  Tighter means the prefixes are pulling.

## Baseline → apply → report

1. Record baseline rows *before* recommending changes; either a fixed
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

## Proving the savings: `eval_scope.sh`

The load-bearing number is **bytes of search output the agent did not have
to read**. `scripts/eval_scope.sh <repo> <pattern> <prefix>` runs one grep
at repo root and the same grep inside the namespace's globs, then reports
the delta:

```json
{"task":"eval-scope","ns":"gen","pattern":"seed","root_hits":676,"root_bytes":2808952,"ns_hits":245,"ns_bytes":28245,"pct_saved":98,"est_tokens_saved":695176}
```

`est_tokens_saved` is `bytes_saved / 4`. `--log` appends the line to
`.prefixer/metrics.jsonl`. Run it on a few representative queries after a
map lands; that is the number in the README claims, not a vibes estimate.
A flat `pct_saved` means the namespace is too wide or the pattern was never
search-bound; adjust the row and measure again. A row that maps generated
or vendored dirs gets `"pct_saved":null` + `"baseline_excluded":true`
instead; its scoped grep runs inside files the baseline never reaches, so
no percentage could be honest (the linter fails such rows anyway).

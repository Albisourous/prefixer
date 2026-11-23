# Morning report: prefixer improvement run

2026-11-23. Two releases tagged and published on GitHub: **v1.3.0**
and **v1.3.1** (marked Latest). `main` is at `e1c490e`, validate CI
green, all four global skill dirs installed at 1.3.1.
Full audit trail: `improve/LEDGER.md`.

## Chosen direction and why

Keep the namespace-map core; make its existing savings and decisions
visible at the moments users look. The council converged on this:
researcher, skeptic, and adoption reviewer each found the measuring
machinery already honest (eval_scope counterfactual grep, eval_repo,
metrics.jsonl) and the gap was that nothing surfaced it. The skeptic
killed the expensive variants: per-search counterfactual grep pays the
cost it advertises, blanket narration is a token tax, and a map `why:`
column would break SPEC. What shipped emits reason and size from data
already in the row.

## What changed, per stage

Stage 0: baseline all green (validator, 130 scaffold checks, shell
syntax; `agentskills` CLI absent locally, CI pins it).

Stage 1: three proposals converged; judge accepted the convergence and
the skeptic's kill list. No unresolved P0.

Stage 2: three implementers on disjoint write sets, judge-gated per
increment. `search.sh` echoes the `contains` reason plus scoped file
count; `session_start.sh` recaps logged searches; `report_metrics.sh`
stops failing on an empty log and labels its delta a trend; `init` and
`install.sh` end pointing at `eval_repo.sh`; `install_hook.sh` and
`doctor.sh` stop pretending `.devin` hooks work for every harness;
SKILL.md gained a thin conditional-narration rule; README quickstart
routes through eval_repo with the receipt quoted verbatim.

Stage 3: measured before/after on a fixture (silent scope choice vs
`searched auth: (login, sessions, tokens) → 5 hits (~96 tokens, 5
files)`). Final skeptic pass found real issues, all fixed: a dead
variable, a draft-grammar mismatch between init and lint, a
wrong-harness doctor false-ok, and zero test coverage on the new
surface (9 tests added).

Stage 4: humanizer pass clean; v1.3.0 bumped and shipped. Overnight
audit found two more upstream portability bugs, shipped as v1.3.1.

## Before / after numbers

- Repo self-eval (`eval_repo.sh .`): mean pct_saved 92% across 10
  namespaces; the `imp:` row measured 80% on its own name; self-lint
  warnings 1 → 0.
- Agent eval (`eval/agent/run.sh`, 1 rep on 1.3.x, appended to the
  rolling RESULTS.md): mapped arm 4.5 vs 7.8 mean tool calls, total
  tool-output bytes 50% smaller. Search bytes still larger (+82%) and
  first-try 13%: one rep is noise, and this remains the honest
  negative result the prior runs documented.
- Eval corpus (18 public repos): unchanged, CI-regenerated weekly;
  last published mean 74%.

## Upstream bugs found and fixed on the way

- `init_namespaces.sh`: `case` inside `$( )` lacked the opening paren
  bash 3.2 requires; every derived prefix collapsed to its first dir
  word on macOS (`game:` instead of `client:`). One char fixed it.
- `suggest_map.sh`: BRE `\|` alternation is GNU-only; the CHECK
  section silently never printed on BSD. Now `sed -E`; test added.
- `graphify-out/` missing from the validator's generated-dir skip
  list; any user running graphify hit the no-dash gate. Added.

## Left red / known residual

- `eval/agent` first-try scoped stays low (13-27%). On a ~140-file
  fixture broad grep is cheap, so agents rationally skip scoping; the
  fixture may under-sell. Not fixed; raising it needs either a bigger
  fixture or agent-side evidence the map changed a decision.
- Mapped-arm search bytes exceed baseline by design of the receipt +
  budgeted output; documented in RESULTS.md.
- The corpus claim (74% today) is hand-synced into README/docs/assets;
  CI refreshes RESULTS.md weekly and the new AGENTS.md invariant lists
  every surface to touch. Still a manual step each refresh.

Overnight after the 1.3.1 ship: a portability audit (bash 3.2, BSD
sed), a 1-rep agent-eval smoke run, the corpus-claim sync, release
tagging, and the `release.yml` TODO-guard fix are all in the ledger
(rows 14-24).

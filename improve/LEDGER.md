# Run ledger: prefixer improvement council

Started 2026-11-23. One row per iteration: what was proposed, what the
gate or judge said, keep or revert, one line of evidence.

## Stage 0: baseline (all green)

| check | result |
|---|---|
| `python3 scripts/validate-package.py` | ok: SKILL.md 1878 words, version 1.0.0, manifests in sync |
| `bash scripts/test_scaffold.sh` | 130/130 checks passed |
| `bash -n scripts/*.sh` | all 14 scripts parse |
| `agentskills validate` | CLI not installed locally; CI pins `skills-ref==0.1.1` |
| `git status` | clean except untracked `improve/` |

Repo facts recorded for later gates: SKILL.md is 1,878 of 5,500 words
(headroom ~3,600); version 1.0.0; eval/RESULTS.md shows 79% mean bytes
saved across 18 repos; eval/agent/RESULTS.md shows 4.6 vs 7.2 tool
calls mapped vs unmapped on a ~140-file fixture.

## Iterations

| # | stage | proposal | gate/judge verdict | keep/revert | evidence |
|---|---|---|---|---|---|
| 1 | direction | surface existing measurements at use time; no new instrumentation | researcher, skeptic, adoption converged; skeptic P0s accepted | keep | `improve/PLAN.md`; counterfactual grep, blanket narration, required summary, map why-column, per-search repo-share all cut |
| 2 | implement A | search.sh echoes `contains` reason + scoped file count; tag_contains added | test_scaffold green; subshell-global bug caught and fixed by implementer (run_scoped sets run_hits, last_nfiles) | keep | `searched auth: (login, sessions, tokens) → 5 hits (~96 tokens, 5 files)` on fixture |
| 3 | implement B | session_start recap line + "say which tag" clause | green; silent when no log | keep | `prefixer: 6 scoped searches logged, 50% hit first try.` |
| 4 | implement C | report_metrics: empty log exit 0, honest delta label | green | keep | empty-log run exits 0 with adoption nudge |
| 5 | implement D | init "next:" pointer to eval_repo; install_hook warns on .devin fallback | green | keep | init tail prints `next: bash .../eval_repo.sh (output bytes saved per row, measured on this repo)` |
| 6 | implement E | SKILL.md thin conditional narration + §4 description; metrics.md contradiction fix; README quickstart eval_repo + path fixes | validator green, 1936 words | keep | `git diff` reviewed by judge; no dashes added |
| 7 | implement F | validate-package.py SKIP_DIRS += graphify-out | green | keep | a subagent's graphify run made the gate red mid-session; same `*-out` convention as skipped_gen |
| 8 | verify | skeptic final pass on full diff | no P0; P1s accepted | fix+keep | dead `level` var removed; 9 new tests cover the new surface; init next: lines quoted |
| 9 | verify | adoption fresh-eyes on README+SKILL.md | path works end-to-end; 2 MED, 5 LOW | fix+keep | doctor wrong-harness warn added; init draft grammar aligned with lint (`TODO` counted, doc_line + agent-doc grep filter TODO); real `todo-*` dirs collapse to `todoapp:`; README quotes echo verbatim, draft clause + claude path note + "a minute"; SKILL.md §4-8 overclaim narrowed |
| 10 | verify | accepted residual: `improve/` stays dash-scanned | deliberate | keep | the audit trail is committed and should obey the same prose rules |
| 11 | verify | measured before/after on fixture repo | visible delta | keep | `searched auth: → 5 hits (~96 tokens)` vs `searched auth: (login, sessions, tokens) → 5 hits (~96 tokens, 5 files)`; session_start gained `prefixer: 6 scoped searches logged, 50% hit first try.`; empty log exit 1 to 0 |
| 12 | ship | rebase onto origin/main (upstream at 1.2.0, +8 commits) | conflicted on 10 files | ported | upstream rewrote search.sh (budgeted output) and init (size-weighted scaffold); my changes re-applied on top, version bumped to 1.3.0 not 1.1.0 |
| 13 | ship | upstream regression found: bash 3.2 syntax error in `$(kids_of "$(case ... */*)` made every sibling list empty | fixture failed on upstream code too | fixed | one `(` added (`in ( */*)`); upstream CI runs Linux bash 5 so it never saw it; `client:`/`server:` derive again |

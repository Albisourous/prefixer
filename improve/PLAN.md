# Plan: prefixer improvement run, 2026-11-23

## Chosen direction

**Surface the measurements that already exist; add no instrumentation
that costs what it claims to save.** The map, linter, eval, and hooks
all work. The value is invisible because nothing says it at the three
moments a user looks: end of install, search output, session start.

Council verdicts folded in:

- Skeptic P0 kills, accepted: no per-search counterfactual root grep
  (the cost is the thing being avoided); no blanket narration contract
  (token tax, self-report proves nothing, contradicts "when not to
  prefix"); no "required" session summary (no portable end hook); no
  map `why:` column (SPEC violation, `contains` already carries the
  why); no per-search repo-share denominator (tree-walk latency).
- Researcher keeps: `contains` echo + scoped file count in search.sh,
  init-to-eval pointer, session-start recap, conditional narration.
- Adoption keeps: eval_repo.sh in the quickstart, honest labeling of
  what the number measures, warn on wrong-harness hook default.

## Stage gates

| stage | gate |
|---|---|
| 0 baseline | validate-package, test_scaffold, bash -n: all green (done, LEDGER.md) |
| 1 direction | this plan survives skeptic attack: no unresolved P0 (done) |
| 2 implement | per increment: validate-package.py, test_scaffold.sh, bash -n green; no-dash scan clean |
| 3 verify | before/after script output on a fixture repo; skeptic final pass on full diff; adoption fresh-eyes on README+SKILL.md |
| 4 ship | humanizer pass, bump-version 1.1.0 (additive), CHANGELOG, commit, push only if all green |

## Changes (surgical)

### A. search.sh says what it did and why (scripts/lib_scope.sh, scripts/search.sh)

- lib_scope.sh: add `tag_contains` mirroring `tag_scope` (same compose
  awk, prints the trimmed `contains` cell). ~15 lines.
- search.sh hit line becomes
  `searched auth: (login, sessions, tokens) → 14 hits (~200 est tokens, 312 files)`
  where 312 is `scope_files` count already resolved inside run_scoped.
  Widen/miss lines unchanged except they keep the contains clause on
  the searched tag. Stderr stays <=2 lines. No new claims: file count
  is labeled `files`, never `saved`.

### B. session_start.sh reports the running total (scripts/session_start.sh)

- Healthy-map line gains one clause: `... search inside these scopes
  first, say which tag you used, widen one level on a miss.`
- If `.prefixer/metrics.jsonl` has `scoped-search` lines, append one
  recap line: `prefixer: N scoped searches logged, M% hit first try.`
  Silent otherwise. ~12 lines of awk over the log; O(log size), no new
  files, no marker schema.

### C. report_metrics.sh survives a fresh install (scripts/report_metrics.sh)

- Empty log: exit 0, not 1, with the existing nudge line (it is an
  adoption hint, not a failure).
- Delta line relabeled honestly: `scoped searches returned ~N% of
  baseline-probe output (different patterns; trend, not a claim)`.

### D. install ends on the user's own number (scripts/init_namespaces.sh, scripts/install_hook.sh)

- init_namespaces.sh, after the `wrote` line:
  - drafts>0: `next: fill the draft rows, then bash <here>/check_namespaces.sh and <here>/eval_repo.sh`
  - drafts==0: `next: bash <here>/eval_repo.sh  (output bytes saved per row, measured on this repo)`
- install_hook.sh auto-detect with no marker dir: keep the `.devin`
  default but warn `note: no .devin or .claude found; writing
  .devin/hooks.v1.json, which only Devin reads`.

### E. prose contract, thin (SKILL.md, references/metrics.md, README.md)

- SKILL.md §4: update the search.sh description to match the new echo
  (says the tag, its `contains` reason, hits, files).
- SKILL.md §6: one conditional clause: when a scope choice is not
  obvious, say the tag and why in one clause; search.sh does this for
  you; a path that already says it needs no ceremony.
- metrics.md line 8: fix contradiction, log is local telemetry
  gitignored by default (aligns with SKILL.md).
- README quickstart: add `eval_repo.sh` step with honest label, note
  the skills-add install path varies by host, fix the
  `scripts/eval_repo.sh` path at line ~93 to the `.agents/` form,
  update the "After" block to show the new echo line.

## Deferred (ledger records why)

- PreToolUse scope-nudge hook (researcher #5): real win but ~60 lines
  and false-positive risk; stage it separately after this lands.
- SessionEnd receipt (#6): same payload as B, fires less reliably.
- Blinded agent-level before/after (researcher #7): eval/agent needs a
  live agent CLI; this diff is text-level. Gate 3 verifies script
  output on a fixture; flag the agent eval for the next harness run.
- Per-search `est_tokens_saved` (#1): killed by skeptic P0.

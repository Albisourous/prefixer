# Changelog

## [0.8.0] - 2026-10-26

Field report, round two: telemetry that stays honest, a scaffold that
covers the whole repo — root files, dot dirs, and jumbo files — richer
`contains` derivation, and a public eval corpus that keeps the savings
claim honest.

- **`contains` samples file contents.** The scaffold reads the files it
  maps: first a doc comment (`//`, `#`, `--`, `/*`, `"""` — shebangs,
  license headers, preprocessor lines filtered), then exported symbols
  (`exports handleRequest, handleResponse`), then bare file names.
  Representative files are picked by name overlap with the dir
  (`auth/AuthService.ts` speaks for `auth/`). Still derived, never
  declared — no wordlists, no LLM calls.
- **Eval corpus.** `eval/repos.txt` lists eight public repos of different
  shapes (monorepo, CLI, web framework, docs site); `eval/run.sh`
  shallow-clones, scaffolds, lints, and evals each, then rewrites
  `eval/RESULTS.md`. A weekly workflow commits the refreshed table —
  corpus mean today: 84% of search-output bytes saved.
- **`eval_repo.sh` evals by composed tag.** Rows iterate as
  `tag + leaf + scope`, so a nested `orders:checkout:` is measured against
  its own scope instead of whichever `checkout:` row came first.
- **`eval_scope.sh`** resolves composed tags (`payments:checkout`), takes
  an optional explicit scope argument, refuses non-glob scope text
  instead of eval'ing it, and escapes the pattern/tag in its JSON line.
- **`check_namespaces.sh`** fails rows whose scope is not plain glob
  syntax (scope text is `eval`'d for brace expansion — it can never be
  shell now), lints a relative repo argument correctly (cd invalidated
  the root-relative map path), and treats brace lists as alternations in
  coverage checks.
- `.prefixer/.gitignore` is appended to, not overwritten, by the scripts
  that create it; the validate workflow also `bash -n`s every script.
- **`measure_search.sh` anchors at the repo root.** The log lands beside
  the map (nearest `.prefixer/` walking up, else git toplevel) — running
  it from a subdirectory can no longer create a stray `.prefixer/`. Adds
  a `scope` field (`--scope`, else inferred from the command's path args,
  `root` when unscoped), `--hit`/`--miss` for agent-reported
  `first_try_hit`, and ISO-8601 UTC timestamps so same-day lines stay
  ordered.
- **`init_namespaces.sh` maps what dirs miss.** Rows now cover
  non-generated dot dirs (`.devin`, `.github`, agent tooling), the files
  at repo root (`package.json`, `vite.config.ts`, root docs — `cfg:` or
  `doc:` depending on content), and jumbo files over ~3k lines as
  per-file rows with declaration landmarks (`~10k lines:
  spawnWave@1270`). Synthetic rows reserve budget inside the 12-row cap
  so `cfg:`/`boot:` survive crowded trees.
- **`check_namespaces.sh` coverage warnings** now include dot dirs and
  uncovered root files.
- **`references/namespaces.md`**: jumbo-file convention and a
  session-start injection recipe — hook the map into the harness's
  session-start context instead of relying on agents remembering to read
  it. **`references/metrics.md`** documents `scope` and the new flags.
- SKILL.md: "session-start beats remembering" note; metrics example
  shows the ISO timestamp.

## [0.7.1] - 2026-10-26

Description and docs: better triggers, no behavior change.

- **SKILL.md description** gains "save tokens" and "cut context cost" as
  trigger phrases so agents surface the skill when users ask for cheaper
  search. First sentence unchanged; manifests still conform.
- **README + site** rewritten to plain style, no dash connector overuse;
  landing page gains a flow diagram, stat cards, and real eval output.

## [0.7.0] - 2026-10-26

Whole-repo evaluation with nothing hardcoded.

- **`eval_repo.sh`** — lints a map, then probes every namespace with its
  own name as the grep pattern (derived vocabulary probing itself — zero
  per-repo config). Prints a per-row hit/byte table and the mean
  `pct_saved`. Measured on public repos: 89–91% of search-output bytes
  eliminated on average.
- README now carries measured numbers from public repos instead of an
  illustrative before/after.

## [0.6.0] - 2026-10-26

Map linting and a real token-savings meter.

- **`check_namespaces.sh`** — lints a map: dead scopes (globs that resolve
  to nothing), duplicate tags across nesting levels, draft/TODO rows,
  generated dirs mapped, uncovered code dirs. Brace globs `{a,b}` resolve
  the way the searching shell expands them.
- **`eval_scope.sh`** — runs one grep at repo root and the same grep inside
  a namespace, reports hits/bytes/`est_tokens_saved` as JSON (`--log`
  appends to metrics.jsonl). On real repos: 98–99% of search output
  eliminated per scoped query (~0.6–0.9M est. tokens).
- `test_scaffold.sh` grew to 16 assertions covering both new scripts.

## [0.5.0] - 2026-10-26

Nested namespaces and zero-TODO scaffolds — sub-teams inside a codebase.

- **Sub-namespaces.** The scaffold descends a second level where a child
  holds sub-teams (`services/payments/{checkout,refunds}`) and emits
  indented rows that compose multi-level tags: `payments:checkout:`.
  Uniqueness is per parent level, so `checkout:` can live under both
  `payments:` and `orders:` without a composite name.
- **Zero-TODO drafts.** Empty dirs are skipped instead of mapped; prefix
  derivation always lands on a real name (short name, distinguishing
  segment, dominant file token, full name); `contains` falls back to real
  file names. Same-parent collisions qualify as `parent-name:`.
- New `scripts/test_scaffold.sh` — fixture test covering repo slugs,
  nested rows, name collisions, generated-dir and empty-dir skips;
  wired into the validate workflow.

## [0.4.0] - 2026-10-26

Derived prefixes and org-unique maps — built for the many-codebases case.

- **Prefixes are derived, not declared.** `init_namespaces.sh` dropped its
  hard-coded wordlist: a prefix now comes from the codebase's own
  vocabulary — a distinguishing dir-name segment no sibling shares, then
  the dominant file-name token, then the dir name itself, then a visible
  `todo-` marker. `contains` cells fall back to the real file names inside
  a scope instead of only agent-doc mentions.
- **`repo:` header.** Every map now declares its codebase's unique
  qualifier, derived from the git remote (dir name as fallback). Qualified
  tags (`payments:auth:`) stay unique when dozens of codebases share
  directory names — for shared indexes, org-level maps, and multi-repo
  agent sessions.
- Prefix collisions inside a map now degrade to a `todo-` marker instead of
  two rows sharing a name.

## [0.3.0] - 2026-10-26

Field-report fixes from a real first run on a small TypeScript repo.

- `init_namespaces.sh` now descends one level into `src/`, `lib/`, `app/`
  and monorepo parents; emits a `boot:` row for entry files; skips `*-out`
  and other generated dirs; uses a wordlist for prefixes (`todo-*` marks
  unfinished rows); seeds `contains` from AGENTS.md/CLAUDE.md/README.md;
  reports draft-row count and a small-repo advisory.
- `measure_search.sh` gained `--baseline` for pre-change probe lines and
  writes `.prefixer/.gitignore` (metrics are local telemetry).
- Metrics schema unified: `hits` (per-search lines) and
  `tool_calls`/`first_try_hit` (task lines) are now documented optional
  fields of one schema.
- SKILL.md: size gate (~100 files), "drafts are not maps" TODO rule,
  agent-docs precedence (namespaces.md is canonical for search scope),
  git handling (commit the map, ignore the log).

## [0.2.0] - 2026-10-26

Narrowed the skill to its core job: namespace-scoped codebase search.

- New rule: map the segment you're working in, not the whole repo — partial
  maps are legal, rows get earned by real searches.
- New "Where it earns its keep" section: the sharp use cases (first session
  in a large repo, monorepos, many codebases, repeated exploration).
- Index-time prefix and cache-ordering rules moved out of the skill body;
  those playbooks stay in `references/` for pipeline and prompt authors.
- Tighter description and red-flags table tuned to search discipline.

## [0.1.0] - 2026-10-26

Initial release.

- `SKILL.md`: the prefix discipline — namespace maps, scoped-first search,
  index-time doc prefixes, cache-stable ordering, per-task metrics.
- `references/`: namespaces, index prefixes, prefix library, cache ordering,
  and metrics playbooks.
- `scripts/`: `init_namespaces.sh`, `measure_search.sh`,
  `validate-package.py`.
- Plugin manifests for Claude, Cursor, and Devin; `agents/openai.yaml`.

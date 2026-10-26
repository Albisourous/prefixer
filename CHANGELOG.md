# Changelog

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

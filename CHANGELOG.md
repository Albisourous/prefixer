# Changelog

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

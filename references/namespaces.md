# The namespace map

`.prefixer/namespaces.md` is a small index file an agent reads once to orient
instead of scanning the tree. It is the repo's table of contents written for
search, not for humans browsing folders.

## Format

```markdown
# namespaces

| prefix | scope                  | contains                     |
|--------|------------------------|------------------------------|
| api:   | src/api/**             | REST handlers, routes        |
| auth:  | src/auth/**            | login, sessions, tokens      |
| ui:    | src/components/**      | React components             |
| db:    | src/db/**, migrations/ | schema, queries, migrations  |
| test:  | tests/**, **/*.test.*  | suites, fixtures             |
| docs:  | docs/**, *.md          | documentation                |
| inf:   | infra/**, .github/**   | deploy, CI, config           |
| scr:   | scripts/**             | one-off tooling, maintenance |
```

- `prefix`: 2 to 6 lowercase letters plus a colon. Pick the word a searcher
  would say, not an abbreviation only maintainers know.
- `scope`: one or more path globs. These are the working part — they are what
  get passed to grep and glob calls.
- `contains`: one line, written to disambiguate between sibling namespaces,
  not to describe the folder. "auth: login, sessions, tokens" tells a
  searcher this is where credential checks live; "auth: authentication code"
  tells it nothing the name doesn't.

## Rules

- **5 to 12 rows.** Fewer and the map can't scope; more and choosing a scope
  costs as much as the search.
- **Every row must be glob-backed.** No vibes namespaces. If a concept has no
  path to point at, it is not a namespace.
- **Never map vendored or generated paths** (`node_modules`, `vendor`,
  `dist`, `build`, `target`, lock files). Those are excluded from search by
  default; a row for them invites exactly the scans the map exists to
  prevent.
- **One home.** If a file matches two rows equally often, merge the rows.
  Overlapping scopes are fine; ambiguous ones are not.
- **Update incrementally.** Edit stale rows, add missing ones, keep the rest
  byte-identical. Never regenerate the file wholesale — rewrites drop curated
  detail and break the prompt-cache prefix of every session that loaded it.

## Other repo shapes

**Monorepo:** namespaces are the packages or apps, not the folders inside
them. `pkg-web: packages/web/**`, `pkg-cli: packages/cli/**`. Cross-cutting
concerns (`test:`, `docs:`) stay at the root.

**Single library:** `src:` may be enough for code; the useful split is often
`lib:` vs `test:` vs `docs:` vs `bench:`.

**Docs or content site:** namespace by topic or section, not file type.
`api-docs: docs/api/**`, `guides: docs/guides/**`.

**Data/notebook repos:** `data:`, `nb:`, `model:` — scope by pipeline stage
when that is how people ask questions.

## Many codebases

One map scopes one repo. At org scale — dozens or hundreds of services an
agent can reach — the same trick stacks, and the stakes grow: a cross-repo
scan is the root-grep problem multiplied by every codebase in reach.

- **Org-level map.** A `namespaces.md` at the workspace or org root maps
  prefixes to codebases: `pay: services/payments/**`,
  `web: apps/portal/**`. Search picks the codebase first, then the
  namespace inside it.
- **Two-level tags.** Results read `pay:api:src/refunds.ts:42` — codebase,
  then namespace, then path. Two colons, no ambiguity.
- **Never union the corpus "to be thorough."** Searching every repo at once
  is how unrelated code lands in the context window and crowds out the
  answer. If a task genuinely spans services, run one scoped search per
  service.
- **Index side:** this is the problem index-time prefix injection was built
  for — 400+ tenants sharing one retrieval model, kept from bleeding into
  each other by per-domain prefixes. For hard tenant boundaries, pair text
  prefixes with real vector-DB namespaces; see `index-prefixes.md`.

## Using the map

The map changes three habits:

1. First search goes inside a namespace's globs, not the repo root.
2. Results get reported as `prefix:path:line` so the next search starts
   scoped.
3. A file that fits no namespace is a signal the map has a gap — fix the map,
   don't force a tag.

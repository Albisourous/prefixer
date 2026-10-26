# The namespace map

`.prefixer/namespaces.md` is a small index file an agent reads once to orient
instead of scanning the tree. It is the repo's table of contents written for
search, not for humans browsing folders.

## Format

```markdown
# namespaces
repo: acme-payments

| prefix | scope                  | contains                     |
|--------|------------------------|------------------------------|
| api:   | src/api/**             | REST handlers, routes        |
| auth:  | src/auth/**            | login, sessions, tokens      |
| ui:    | src/components/**      | React components             |
| db:    | src/db/**, migrations/ | schema, queries, migrations  |
| test:  | tests/**, **/*.test.*  | suites, fixtures             |
| docs:  | docs/**, *.md          | documentation                |
|   api-docs: | docs/api/**       | endpoint reference           |
| inf:   | infra/**, .github/**   | deploy, CI, config           |
| scr:   | scripts/**             | one-off tooling, maintenance |
```

Indented rows are **sub-namespaces**: they belong to the row above and
compose multi-level tags — `docs:api-docs:` — for sub-teams inside a
module or packages inside a service. A prefix only needs to be unique
within its parent level: `checkout:` can sit under both `payments:` and
`orders:` because `payments:checkout:` and `orders:checkout:` are already
different tags. Empty dirs are skipped rather than mapped.

- `repo`: one line under the title — this codebase's unique qualifier,
  derived from the git remote (or directory name when there is none). It is
  what keeps `auth:` unique across the org: `acme-payments:auth:` and
  `checkout-service:auth:` name two different namespaces in shared indexes,
  org-level maps, and multi-repo MCP sessions.
- `prefix`: 2 to 8 lowercase letters plus a colon. **Derived, not
  declared** — the word comes from the codebase's own vocabulary: the
  directory's name or distinguishing segment, the dominant term in the
  files it scopes. Invented categories drift as the repo evolves; derived
  names track it.
- `scope`: one or more path globs. These are the working part — they are what
  get passed to grep and glob calls.
- `contains`: one line, written to disambiguate between sibling namespaces,
  not to describe the folder. "auth: login, sessions, tokens" tells a
  searcher this is where credential checks live; "auth: authentication code"
  tells it nothing the name doesn't. Seed it from what actually lives there
  — agent-doc mentions, the files inside — never boilerplate.

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
- **No silent TODOs.** A row whose prefix or `contains` still says `TODO` is
  unfinished. A map full of them is a draft, not a map — finish or cut.

## Relationship to agent docs

`AGENTS.md`, `CLAUDE.md`, and READMEs often already describe the layout in
prose. Don't maintain two drifting tables of contents:

- `namespaces.md` is canonical for **search scope** — the globs and prefixes
  the agent searches inside.
- Agent docs stay canonical for prose explanations.
- The scaffold seeds `contains` cells from those docs when it finds a
  mention. If a repo's agent docs already carry a great layout section,
  the map links to it rather than paraphrasing it.

## Git handling

- **Commit `namespaces.md`.** It is the shared prefix — every future
  session and every teammate's agent benefits.
- **`metrics.jsonl` is local telemetry.** The scaffold writes a
  `.prefixer/.gitignore` for it. Commit it only if the team wants trend
  data in history.

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
- **Multi-level tags.** Results read `pay:api:src/refunds.ts:42` —
  codebase, then namespace (itself possibly nested), then path. The depth
  matches the map's nesting; there is always one colon per level.
- **`repo:` makes prefixes unique.** Namespace names repeat across
  codebases by nature — every service has an `auth/` and an `api/`. The
  `repo:` header in each map qualifies them: `payments:auth:` and
  `checkout-service:auth:` are distinct keys in a shared index or an agent
  session spanning repos. Ingesting many maps into one store? Concatenate
  the rows and let `repo:ns:` be the lookup key — collisions become
  impossible without renaming anything.
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

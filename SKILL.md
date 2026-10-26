---
name: prefixer
description: |
  Give agents a namespace map of a codebase so searches start scoped instead
  of broad. Use to improve a codebase's token efficiency; save tokens and
  cut context cost when agents search code: at the start of work in an
  unfamiliar or large repo, when a task needs repeated codebase search,
  when a grep or glob returns a wall of hits, when results keep landing in
  unrelated parts of the tree, or when the user asks how to make their
  codebase cheaper or more token-efficient for agents.
license: MIT
metadata:
  version: "0.11.1"
allowed-tools:
  - read
  - grep
  - glob
  - exec
  - edit
triggers:
  - user
  - model
---

# Prefixer: scope first, widen on miss, log the delta

An agent that searches the whole repo pays for every irrelevant hit in
tokens. A namespace map, a dozen lines saying what lives where, lets it
search inside the right area from the first call. This skill builds that
map, keeps it alive, and holds the agent to scoped-first searching. It does
one job: cheaper, better codebase search.

**Size gate.** Under roughly a hundred files, or when the repo's shape is
obvious at a glance, skip the map and scope searches by directory names;
the map pays rent past that point.

<IMPORTANT>
If there is even a small chance a search in front of you could be scoped,
scope it. An unscoped search is the failure this skill exists to prevent.
"It is just one grep" is how the tokens go.
</IMPORTANT>

## How to work

1. **Orient once.** Check for `.prefixer/namespaces.md`. If none exists and
   the task will take more than two searches, map the segment you are working
   in (§1 to §3), then search inside it. If a map exists, read it and start
   scoped.
2. **Search scoped, widen on miss.** First search goes to the narrowest
   plausible namespace, not the repo root (§4 to §6).
3. **Log it.** End the task with one line in `.prefixer/metrics.jsonl`, and a
   delta when a baseline exists (§7 to §8). Required output, not optional.

## Where it earns its keep

- **First session in a large or unfamiliar repo.** Read twelve lines of map
  instead of scanning the tree; the first search is already scoped.
- **Monorepos.** One namespace per package: searches stop pulling sibling
  packages' noise into context.
- **Many codebases.** An org-level map picks the codebase, the repo's map
  picks the namespace inside it. Two levels, never a union scan.
- **Repeated exploration.** "Where does X live," refactors, unfamiliar
  feature areas; the first-try-hit rate is where the map pays rent.
- **Repos you will revisit.** The map persists across sessions; every future
  agent starts oriented instead of re-scanning.

## A. The namespace map

### 1. Map the segment, not the world

**Rule:** When a repo has no `.prefixer/namespaces.md` and the work needs
more than two searches, map **the part of the repo this task touches**:
three to five namespaces; not the whole tree. A partial map that scopes
today's searches beats a complete map that took an hour. Grow it when a real
search lands outside it, never in anticipation. Run
`bash scripts/init_namespaces.sh` (in this skill's directory) for a
scaffold, then fix its guesses: name what each namespace is *for*.

**Why:** adoption is incremental by design. The map is a working file, not a
census; it earns a row when a search needs that row.

**Drafts are not maps.** Any row whose prefix or `contains` still says
`TODO` is unfinished; finish it or cut it before relying on the map. The
scaffold reports how many draft rows remain.

**Existing docs first.** If `AGENTS.md`, `CLAUDE.md`, or the README already
describe the layout, seed `contains` from them (the scaffold does this) and
treat `namespaces.md` as canonical for *search scope*; don't maintain two
drifting tables of contents.

**Session-start beats remembering.** Reading the map once per session is
the step most likely to be skipped. If the harness can inject files at
session start, have it emit `namespaces.md`: every search then starts
scoped with no discipline required. Shipped wiring: `scripts/install_hook.sh`
writes the hook for you (`scripts/session_start.sh` emits the map plus a
health verdict); hand snippets live in `integrations/`. Recipe and
rationale: `references/namespaces.md`.

### 2. Keep it small and glob-backed

**Rule:** 5 to 12 namespaces. Each row is a short prefix, a path glob, and a
one-line purpose written for disambiguation. If two rows would match the
same search equally often, merge them. If a row never scopes a real search,
cut it.

**Format:**

```markdown
# namespaces
repo: acme-payments

| prefix | scope              | contains                    |
|--------|--------------------|-----------------------------|
| api:   | src/api/**         | REST handlers, routes       |
| auth:  | src/auth/**        | login, sessions, tokens     |
|   sso: | src/auth/sso/**    | SSO sub-team area           |
| test:  | tests/**, **/*.test.* | suites, fixtures         |
```

The `repo:` header is this codebase's unique qualifier (from the git
remote); it makes every prefix globally unique when an org runs many
codebases: `acme-payments:auth:` can never collide with
`checkout-service:auth:`.

Rows nest: an indented row belongs to the namespace above it, for
sub-teams inside a module or packages inside a service. The tag composes,
`auth:sso:`, so the same name under two parents stays distinct
(`orders:checkout:` vs `payments:checkout:`).

**Names are derived, not declared.** Prefixes and `contains` text come from
the codebase's own vocabulary: directory names, the dominant terms in the
files a row scopes, never from categories you invent. Derived names track
the repo as it evolves; invented ones drift. The scaffold does this for
you: fix what it gets wrong, keep what it got right.

Format details and maps for other repo shapes: `references/namespaces.md`.

### 3. Update, never regenerate

**Rule:** When the map is stale, edit the stale rows. Do not rewrite the
file. Wholesale regeneration loses the accumulated detail that made it
useful. Prune dead rows, add missing ones, keep the rest byte-identical; a
rewritten map also breaks the prompt-cache prefix of every session that
loaded it. After curating, run `bash scripts/check_namespaces.sh`: a row
whose globs resolve to nothing is a lie the map is telling every future
session. When the map feels stale or the log has grown, run
`bash scripts/suggest_map.sh`: it reads `metrics.jsonl` and the tree and
proposes the rows real searches already asked for.

**Many codebases:** the same trick stacks. An org-level map picks the
codebase (`pay: services/payments/**`), the repo map picks the namespace
inside it. Each map's `repo:` header keeps prefixes unique across
codebases; forty services can all have an `auth/` because a qualified tag
`payments:auth:` names exactly one. Never union every repo into one search
that is the root-grep failure at org scale. See
`references/namespaces.md`.

## B. Search scoping

### 4. Narrowest first

**Rule:** Every search starts at the narrowest namespace that could hold the
answer. `grep "expire" src/auth/` beats `grep "expire" .`. A miss costs one
call; a broad search costs the whole hit list in tokens.

**Let the script carry the rule:** `bash scripts/search.sh auth "expire"`
resolves the tag to its globs, searches inside them, widens one level on a
miss, and logs the metrics line; §4 to §8 run themselves. `--scope <ns>`
prints the glob list, `--paths <ns>` the resolved files, `--list` every
tag; the map as an index other commands can query.

**Watch for:** searching the repo root "just in case", glob patterns like
`**/*` with no path constraint, `find` used where a namespace glob would do.

### 5. Widen one level on a miss

**Rule:** Missed inside a namespace? Widen one level: namespace, then its
parent area, then the repo, then vendored and generated dirs. Do not jump
from a miss straight to a whole-repo scan, and do not search `node_modules`,
`vendor`, `dist`, `build`, or lock files unless the task is about them.

### 6. Answer in namespace tags

**Rule:** Report findings as `prefix:path:line` (`auth:src/auth/session.ts:42`).
The next search, yours or a future session's, then starts already scoped.
When a file resists every namespace, that is signal the map has a gap;
mention it instead of inventing a tag.

## C. Tracking

### 7. Baseline before claims

**Rule:** Before recommending search changes, count the current behavior:
searches per task, tool calls per task, first-try hit rate. Without a
baseline there is no delta, only a story. Record one by running a fixed
probe: `bash scripts/measure_search.sh --baseline orientation -- grep -rn
"TODO" .` at repo root, or by counting the first few tasks before the map
exists. See `references/metrics.md` for what to record and how to score it.

### 8. Log every task

**Rule:** Append one JSON line to `.prefixer/metrics.jsonl` at the end of
each task:

```json
{"ts":"2026-10-26T14:03:11Z","task":"find-session-expiry","searches":3,"tool_calls":4,"first_try_hit":true,"est_tokens":1400}
```

`est_tokens` is chars/4, an estimate; keep the field even when you cannot
measure exactly. At session end, report the delta against the baseline.
`scripts/measure_search.sh` wraps a search and logs a per-search line at
the repo root (`hits`, `scope`; `--baseline` marks the probe,
`--hit|--miss` records `first_try_hit`). Hand-written task lines add
`tool_calls` and `first_try_hit`. One schema, optional fields;
`references/metrics.md` lists them. `scripts/report_metrics.sh` reads
the log back: hit rate, per-scope spend, the scoped-vs-baseline delta.

**Git handling.** Commit `namespaces.md`: it is the shared prefix every
future session benefits from. `metrics.jsonl` is local telemetry; the
scaffold writes a `.prefixer/.gitignore` for it. Commit it only if the team
wants trend data.

## Red flags

These thoughts mean stop. You are rationalizing.

| Thought | Reality |
|---------|---------|
| "One broad grep won't hurt" | The broad grep is the cost this skill exists to remove. Scope it. |
| "I know where it probably is" | Verify in the namespace. A wrong guess costs more than a scoped check. |
| "Map the whole repo first" | Map the segment you're in. The rest earns rows when searches need them. |
| "The map is overkill for this task" | A partial map still pays off by the third search. |
| "Skip the baseline, just apply it" | No baseline means no evidence. Measure first. |
| "I'll regenerate the whole map, it's faster" | Regeneration drops curated detail and breaks cache. Edit the stale rows. |
| "A scaffolded map counts" | A map full of TODO rows is a draft, not a map. Finish or cut them. |
| "Search vendor dirs to be thorough" | Generated code is where tokens go to die. Search it only when it's the subject. |

## When not to prefix

- Single-file scripts and throwaway repos: there is nothing to scope.
- Tasks with one obvious file: open it, don't build infrastructure for it.
- When the path already says it: a search inside `src/auth/` needs no
  `auth:` ceremony around it.
- Vendored or generated code, unless it is the subject of the task.
- Repos under ~100 files whose shape is obvious: scope by directory names
  and skip the map.

## References

- `references/namespaces.md`: map format, repo shapes, multi-repo stacking
- `references/metrics.md`: metric definitions, JSONL schema, delta reporting
- `scripts/init_namespaces.sh`: scaffold a namespace map for the current repo
- `scripts/check_namespaces.sh`: lint a map: dead scopes, dup tags, drafts
- `scripts/search.sh`: scoped search as a command: resolve, search, widen, log
- `scripts/suggest_map.sh`: read the log + the tree, propose map edits
- `scripts/measure_search.sh`: run a search and log it in one step
- `scripts/report_metrics.sh`: read the log back: hit rate, scope spend, delta
- `scripts/session_start.sh`: emit the map (+ health) for session-start hooks
- `scripts/install_hook.sh`: wire the SessionStart hook for devin/claude
- `scripts/eval_scope.sh`: measure the token delta of a scoped search vs root
- `scripts/eval_repo.sh`: lint + eval every namespace in a map, mean % saved
- `scripts/visualize.py`: render the map on the file tree + the measured savings as an HTML report
- `SPEC.md`: the namespaces.md format contract, for tools that read or write maps
- `integrations/`: session-start hook snippets + a PR lint workflow for consumer repos

Adjacent playbooks kept for pipeline and prompt authors (outside this
skill's core job): `references/index-prefixes.md`,
`references/prefix-library.md`, `references/cache-ordering.md`.

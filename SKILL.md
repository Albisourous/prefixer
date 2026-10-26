---
name: prefixer
description: |
  Add namespace prefixes to a codebase so searches start scoped, indexed text
  clusters tighter, and prompt caches hit. Use when a task needs repeated
  codebase search, when a search returns a wall of hits, when writing docs or
  chunks that get indexed or embedded, when ordering prompt or skill content,
  or when a repo has no orientation map and scanning the tree is the only way
  to get one.
license: MIT
metadata:
  version: "0.1.0"
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

# Prefixer: scope first, vary last, measure the delta

A prefix is stable, scoping context placed up front. Put one before a search
and the hit list shrinks. Put one before a document at index time and its
embedding lands in a tighter cluster. Put one at the front of a prompt and
the cache keeps it so you stop paying for the same tokens twice. This file is
itself a prefix: a small, stable block of context that shapes everything
after it. Keep it that way.

The research behind each move: index-time prefix injection gained 3 to 8
percent Hit@5 across 400+ deployments with no fine-tuning (Varshney & Mc,
ACL 2026). Prepending situating context before embedding cut retrieval
failures 49 percent (Anthropic contextual retrieval). Prompt caches reuse
any byte-exact shared prefix, so ordering context by stability decides
whether repeat tokens come back cached or get paid for again.

<IMPORTANT>
If there is even a small chance a search, an index, or a prompt layout in
front of you could use this skill, use it. An unscoped search or an
unordered prompt is the failure this skill exists to prevent. "It is just
one grep" is how the tokens go.
</IMPORTANT>

## How to work

1. **Orient once.** Check for `.prefixer/namespaces.md`. If none exists and
   the task will take more than two searches, make one (§1 to §3), then
   search inside namespaces. If one exists, read it and start scoped.
2. **Search scoped, widen on miss.** First search goes to the narrowest
   plausible namespace, not the repo root (§4 to §6).
3. **Prefix what gets indexed.** Docs, chunks, RAG corpora, anything a
   retriever will embed later (§7 to §9).
4. **Order context stable-first.** In prompts, rules files, and skills you
   write: stable up front, volatile last (§10 to §12).
5. **Log it.** End the task with one line in `.prefixer/metrics.jsonl`, and a
   delta when a baseline exists (§13 to §14). The log line is required
   output, not a suggestion.

## A. The namespace map

### 1. Map before you crawl

**Rule:** When a repo has no `.prefixer/namespaces.md` and the work needs
more than two searches, or a future session would have to scan the tree to
orient, write the map first. Run `bash scripts/init_namespaces.sh` (in this
skill's directory) for a scaffold, then fix its guesses: name what each
namespace is *for*, not just where it sits.

**Why:** One small file replaces the tree scan every session would otherwise
repeat. The map is itself a prefix: stable context up front that makes every
later search cheaper.

### 2. Keep it small and glob-backed

**Rule:** 5 to 12 namespaces. Each row is a short prefix, a path glob, and a
one-line purpose written for disambiguation. If two rows would match the
same search equally often, merge them. If a row never scopes a real search,
cut it.

**Format:**

```markdown
# namespaces
| prefix | scope              | contains                    |
|--------|--------------------|-----------------------------|
| api:   | src/api/**         | REST handlers, routes       |
| auth:  | src/auth/**        | login, sessions, tokens     |
| test:  | tests/**, **/*.test.* | suites, fixtures         |
```

Format details and maps for other repo shapes: `references/namespaces.md`.

### 3. Update, never regenerate

**Rule:** When the map is stale, edit the stale rows. Do not rewrite the
file. Wholesale regeneration loses the accumulated detail that made it
useful; context engineers call this collapse. Prune dead rows, add missing
ones, keep the rest byte-identical. Byte-identical matters: a rewritten map
also breaks the prompt-cache prefix of every session that loaded it.

**Many codebases:** the same trick stacks. An org-level map picks the
codebase (`pay: services/payments/**`), the repo map picks the namespace
inside it. Never union every repo into one search — that is the root-grep
failure at org scale. See `references/namespaces.md`.

## B. Search scoping

### 4. Narrowest first

**Rule:** Every search starts at the narrowest namespace that could hold the
answer. `grep "expire" src/auth/` beats `grep "expire" .`. A miss costs one
call; a broad search costs the whole hit list in tokens.

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

## C. Index-side prefixes

### 7. Use the shape `domain type: entity`

**Rule:** Text that will be indexed, embedded, or retrieved later gets a
short descriptive prefix before indexing: `payments API reference: refund
endpoint`, `auth runbook: session rotation`. One line, domain first,
artifact type second, entity last. This is what pulls embeddings into the
tighter cluster the retrieval gains come from.

**Watch for:** writing docs or chunking a corpus with no prefix plan. The
prefix is set at index time, once; retrofitting means re-indexing.

### 8. Discover prefixes in tiers

**Rule:** Propose prefixes in this order: sample the corpus and draft
candidates with the model when data policy allows, ask a domain expert to
curate when it does not, and fall back to `references/prefix-library.md`
when neither is available. Never ship a prefix no human has seen to a
production index.

Full playbook, corpus examples, and the evaluation method:
`references/index-prefixes.md`.

### 9. Lint the prefix

**Rule:** A prefix that could describe any document describes none. Ban
`document:`, `file:`, `misc:`, `note:`. A prefix so specific it fits five
docs splinters the corpus; merge up a level. Test: two docs sharing a prefix
should be neighbors a user would expect together.

## D. Prompt order

### 10. Classify every input by stability

**Rule:** Before writing or reordering context, tag each input: never
changes, changes per session, per turn, or per request. Order them in that
sequence. A cache matches from the first byte forward, so everything after
the first volatile byte is paid for in full.

### 11. Kill silent invalidators

**Rule:** No timestamps, UUIDs, random IDs, reordered JSON keys, or unstable
tool lists inside the stable region. Move them to the end or drop them. One
byte of early volatility invalidates the whole prefix after it.

Full stability table, breakpoint rules, and agent-specific traps:
`references/cache-ordering.md`.

### 12. Contextualize at index time, not query time

**Rule:** When building retrieval, situating context gets prepended to
chunks before embedding, once. Do not pay a per-query cost for what an
index-time pass buys permanently. Prefixed chunks are also stable strings,
which makes their KV reusable at serve time.

## E. Tracking

### 13. Baseline before claims

**Rule:** Before recommending prefix changes, measure the current behavior:
searches per task, tool calls per task, first-try hit rate. Without a
baseline there is no delta, only a story. See `references/metrics.md` for
what to record and how to score it.

### 14. Log every task

**Rule:** Append one JSON line to `.prefixer/metrics.jsonl` at the end of
each task:

```json
{"ts":"2026-10-26","task":"find-session-expiry","searches":3,"tool_calls":4,"first_try_hit":true,"est_tokens":1400}
```

`est_tokens` is chars/4, an estimate; keep the field even when you cannot
measure exactly. At session end, report the delta against the baseline.

## Red flags

These thoughts mean stop. You are rationalizing.

| Thought | Reality |
|---------|---------|
| "One broad grep won't hurt" | The broad grep is the cost this skill exists to remove. Scope it. |
| "I know where it probably is" | Verify in the namespace. A wrong guess costs more than a scoped check. |
| "The map is overkill for this task" | The map pays off by the third search and serves every future session. |
| "Skip the baseline, just apply it" | No baseline means no evidence. Measure first. |
| "The prefix is just metadata" | Position is the mechanism. A late prefix is no prefix. |
| "I'll regenerate the whole map, it's faster" | Regeneration drops curated detail and breaks cache. Edit the stale rows. |
| "Search vendor dirs to be thorough" | Generated code is where tokens go to die. Search it only when it's the subject. |

## When not to prefix

- Single-file scripts and throwaway repos: there is nothing to scope.
- When the path already says it (`docs/api/refunds.md` needs no `api:` tag in
  a search result, though it may need one in an index).
- Prefixes that just restate the obvious at more length.
- Prompts built once and never repeated: caching needs a second reader.

## References

- `references/namespaces.md` — map format, repo-shape examples, update rules
- `references/index-prefixes.md` — tiered discovery playbook and evaluation
- `references/prefix-library.md` — standard prefixes when curation is not available
- `references/cache-ordering.md` — stability classes, invalidators, breakpoints
- `references/metrics.md` — metric definitions, JSONL schema, delta reporting
- `scripts/init_namespaces.sh` — scaffold a namespace map for the current repo
- `scripts/measure_search.sh` — run a search and log it in one step

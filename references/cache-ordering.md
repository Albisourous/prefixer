# Cache ordering

One invariant, everything follows from it:

**A prompt cache is a prefix match.** The provider reuses KV state for the
longest byte-exact leading span. The first byte that differs, a timestamp,
a reordered key, a changed tool list, invalidates everything after it.
Markers and flags cannot fix order; only order fixes order.

## Stability classes

Tag every piece of context before placing it:

| class | changes | examples | position |
|-------|---------|----------|----------|
| never | almost never | identity, behavior rules, tool defs, this skill | first |
| per-session | once per session | repo layout, NAMESPACES map, AGENTS.md, project context | early, after identity |
| per-turn | each user turn | task state, retrieved files | late |
| per-request | every call | timestamps, UUIDs, random seeds, "current time" | eliminate, or dead last |

## Rules

1. **Stable bytes first, always.** Identity and rules, then session-stable
   project context, then volatile content. The namespace map belongs in the
   per-session layer; it changes rarely, reads constantly.
2. **Append, don't rewrite.** Conversation history is a growing prefix. New
   turns go at the end; rewriting or compacting earlier turns resets reuse
   for everything after the edit point.
3. **Place breakpoints at stability boundaries.** Put cache breakpoints on
   the last block of each stable region (after tool defs, after project
   context), never inside volatile content.
4. **Hunt silent invalidators.** The usual suspects:
   - timestamps or dates inside the system prompt
   - random IDs generated per request
   - JSON keys emitted in unstable order
   - tool lists that change order between calls
   - memory snapshots or "recent activity" blocks near the top
   - locale strings, `cwd` paths, environment dumps injected early
5. **Per-request noise goes last or goes away.** If it must exist, it lives
   after the final breakpoint.

## For skills and rules files you write

A skill file is a prefix other agents will load. Keep it byte-stable between
releases, small diffs, not rewrites, and put anything volatile (dates,
counts, "last updated") at the bottom or in a `references/` file. Progressive
disclosure is the other half: frontmatter stays tiny because it is
always-loaded prefix; bulk lives in files read only when needed.

## When it doesn't apply

- One-off prompts with no repeated prefix get nothing from ordering.
- Some harnesses hold the whole system prompt constant for you; check before
  reordering what you don't control.
- Cache reuse needs a *second* identical prefix: a session of one-offs won't
  show the win. That's expected, not a failure.

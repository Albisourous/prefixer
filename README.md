<p align="center">
  <img src="assets/icon.svg" alt="prefixer — namespace prefixes for AI agent code search" width="120">
</p>

# prefixer

An agent skill for scoped codebase search, index-time doc prefixes, and
token-efficient prompt ordering — for Devin, Claude Code, Codex, Cursor,
and friends.

<p>
  <a href="https://github.com/Albisourous/prefixer/stargazers"><img src="https://img.shields.io/github/stars/Albisourous/prefixer" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <a href="https://github.com/Albisourous/prefixer/actions/workflows/validate.yml"><img src="https://github.com/Albisourous/prefixer/actions/workflows/validate.yml/badge.svg" alt="validate"></a>
</p>

**prefixer** is a cross-agent skill that teaches AI coding agents one
discipline — *scope first, vary last, measure the delta* — applied wherever a
prefix does work:

| Where the prefix goes | What it buys you |
|---|---|
| In front of a search (`auth:`, `src/api/`) | Fewer tool calls and smaller results → fewer tokens burned exploring |
| In front of a doc/chunk at index time | Tighter embeddings → better Hit@k with zero fine-tuning |
| At the front of a prompt (stable content first) | Prompt-cache hits → cheaper input tokens, faster TTFT |

The main win today: **better codebase search.** Agents that grep the whole
tree pay for every irrelevant hit in tokens. An agent with a namespace map
scopes the search first — the way you'd type `path:src/auth` into GitHub code
search instead of reading the repo.

**Before** (typical agent, illustrative):

```
grep "session" .            → 400+ hits, dumps pages into context
grep "expire" .             → another wall of noise
read 3 wrong files          → still guessing
≈ 9 tool calls, thousands of tokens, answer found by accident
```

**After** (with prefixer):

```
read .prefixer/namespaces.md            → auth: = src/auth/**
grep "session" src/auth/                → 12 hits
read src/auth/session.ts:40-58          → found
≈ 3 tool calls, a fraction of the tokens, answer found on purpose
```

## Good fit if you

- run AI coding agents over large repos or **many repos** and want fewer,
  better-targeted search calls and a smaller context bill
- are building a **RAG or search index** and want better retrieval without
  fine-tuning (index-time prefix injection, ACL 2026)
- write **prompts, rules files, or skills** and want prompt caches to
  actually hit (stable-prefix ordering)
- want the before/after **measured**, not vibes — `metrics.jsonl` tracking
  is built in

It's grounded in published results — index-time prefix injection (ACL 2026:
+3–8% Hit@5), contextual retrieval (−49% retrieval failures), and prompt
caching (byte-exact prefix reuse, 8–60× TTFT) — and it ships a tracking
loop (`metrics.jsonl`) so the gains get measured instead of assumed.

Fun fact: the skill itself is a prefix — stable context placed up front that
shapes every turn after it. Same trick [humanizer](https://github.com/blader/humanizer)
uses for prose, applied here to context layout.

See [DESIGN.md](DESIGN.md) for the full design, the research base, and the
build plan.

## Status

v0.1.0 — first cut. Layout follows the humanizer model: one canonical
`SKILL.md` at the root, thin plugin manifests per harness.

## Install

### Devin

The repo root *is* the skill, so install is one command.

**Global — every project on your machine:**

```bash
git clone https://github.com/Albisourous/prefixer ~/.config/devin/skills/prefixer
```

Update later with `git -C ~/.config/devin/skills/prefixer pull`.

**Project-level — committed for the team** (fetch a tarball so no nested
`.git` lands in your repo):

```bash
mkdir -p .devin/skills/prefixer
curl -L https://github.com/Albisourous/prefixer/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 -C .devin/skills/prefixer
git add .devin/skills/prefixer
```

`.agents/skills/prefixer/` works as the project path too — Devin reads both.

Then invoke with `/prefixer` in a session, or let the agent fire it itself —
the `triggers: [user, model]` frontmatter allows it when a task needs
repeated codebase search, and `allowed-tools` pre-approves
read/grep/glob/exec/edit so it runs without permission prompts.

### Claude Code

```
/plugin marketplace add Albisourous/prefixer
```

### Other agents

Copy `SKILL.md`, `references/`, and `scripts/` into
`.agents/skills/prefixer/` — Codex, Copilot CLI, and Gemini read that path.
Or `npx skills add Albisourous/prefixer` once listed on skills.sh.

## Layout

```
SKILL.md                  canonical skill (root, single file)
references/               deep-dives loaded on demand
scripts/                  namespace-map + metrics + validator
agents/openai.yaml        OpenAI-compatible agent display data
*-plugin/                 per-harness manifests (claude, cursor, devin)
```

## The short version of what it does

1. **Maps your repo's namespaces** once into a small index file every agent
   session can read instead of scanning the tree.
2. **Searches scoped-first** — narrowest namespace, widen on miss.
3. **Prefixes what gets indexed** — domain-descriptive prefixes on docs,
   chunks, and embeddings inputs, discovered via the paper's tiered strategy.
4. **Keeps prompts cache-friendly** — stable context early, volatile late.
5. **Measures everything** — baseline first, log per task, report the delta.

## Not to be confused with

- **Prefix-tuning** (Li & Liang, ACL 2021): trains soft prompt vectors.
  Ours are plain-text conventions — auditable, cacheable, no training.
- **Prompt compression** (LLMLingua et al.): removes tokens. Complementary,
  not bundled — prefixes organize what compression shrinks.

## Key references

- Varshney & Mc, *Index-Time Prefix Injection for Multi-Tenant Retrieval*
  (ACL 2026 Industry) — https://aclanthology.org/2026.acl-industry.149/
- Anthropic, *Introducing Contextual Retrieval* (2024)
- Gim et al., *Prompt Cache* (MLSys 2024) — arXiv:2311.04934
- Zhang et al., *Agentic Context Engineering* (ICLR 2026) — arXiv:2510.04618
- Full list in [DESIGN.md §9](DESIGN.md#9-references)

## License

MIT — see [LICENSE](LICENSE).

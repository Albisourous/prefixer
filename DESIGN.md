# Prefixer: Skill Design

> A cross-agent skill that adds **prefix best practices** to a codebase:
> namespace prefixes that scope search, descriptive prefixes that improve
> indexing/retrieval, and prefix-order hygiene that makes prompt caches hit,
> with built-in tracking so the gains are measured, not assumed.

## 1. Thesis

A **prefix** is stable, domain-scoping context placed up front. The same
principle shows up in three independent research/results threads, and each one
maps to a concrete agent behavior:

| Position of the prefix | Mechanism | Evidence | Payoff |
|---|---|---|---|
| Before a search query / file pattern | Narrows the candidate space before scanning | Practitioner convention (`repo:`, `path:`, `file:` qualifiers; aider repo-map) | Fewer tool calls, smaller result sets → fewer tokens |
| Before a document/chunk at index time | Shifts embeddings into a tighter, domain-coherent region | Index-Time Prefix Injection (ACL 2026 Industry); Anthropic Contextual Retrieval | +3-8% Hit@5; -49% retrieval failures (-67% with rerank) |
| At the front of a prompt | KV cache is a byte-exact *prefix* match; stable-first ordering preserves it | Anthropic/OpenAI/Meta prompt-caching docs | Lower input-token cost, lower TTFT |
| Before the whole session (rules/skill metadata) | Always-loaded stable context shapes every turn after it | blader/humanizer (a prefix for prose); skills/RULES files everywhere | Behavior change with zero per-task tokens |

So "prefixer" is not three features; it is one discipline applied at three
positions: **scope first, vary last, measure the delta.**

The reflexive case matters: **a skill is itself a prefix.** humanizer (61k★)
is a prefixer for prose; a slab of stable context up front that rewrites
everything downstream. prefixer is the same trick for context layout, which
means the skill must practice what it ships: a tight always-loaded
description, stable byte-for-byte content (a cacheable prefix), and
progressive disclosure for the heavy parts.

## 2. Research base

Organized by the pillar each result supports. Full links in
[§9 References](#9-references).

### A. Index-side prefixes: retrieval quality

1. **Varshney & Mc, "Index-Time Prefix Injection for Multi-Tenant Retrieval",
   ACL 2026 Industry.** The anchor. Prepending domain-descriptive prefixes to
   documents at index time shifts embeddings into a tighter, domain-coherent
   region → +3-8% Hit@5, +4.2% CTR A/B, 18 languages, 400+ tenants, zero
   fine-tuning. Adopt its **tiered prefix discovery** wholesale: LLM-generated
   from samples → expert curation → standardized library fallback. Its failure
   modes become our lint rules: vague prefixes ("document:") cluster nothing;
   over-specific prefixes splinter the corpus.

2. **Anthropic, "Introducing Contextual Retrieval" (2024).** The per-chunk
   cousin: a 1-2 sentence situating context prepended before embedding *and*
   before BM25 → -49% failed retrievals, -67% with rerank. One-time index cost;
   the authors use prompt caching to make generation cheap; a nice loop back
   to pillar B.

3. **Sarthi et al., "RAPTOR" (ICLR 2024, arXiv:2401.18059).** Recursively
   clusters and summarizes chunks into a tree of abstractions; +20% absolute on
   QuALITY. Independent evidence that *what you put in front of content at
   index time* (here, summaries) drives retrieval quality; and a precedent for
   namespace hierarchies when a flat map isn't enough.

4. **HyDE (arXiv:2212.10496) and Query2Doc (arXiv:2303.07678).** Prepend
   *generated* context to a query/document to pull it toward the right region
   of embedding space. Same family; prefixer uses the deterministic, reusable
   variant because a static prefix is both cacheable and auditable.

### B. Prompt-side prefixes: token cost and latency

5. **Gim et al., "Prompt Cache" (MLSys 2024, arXiv:2311.04934).** Precompute
   and reuse attention states for shared prompt segments ("prompt modules") →
   8-60× TTFT reduction. The academic backbone of vendor prompt caching; its
   module schema is the formal version of our stability classification.

6. **Zheng et al., SGLang / RadixAttention (arXiv:2312.07104).** LRU radix-tree
   cache of KV state shared across generation calls. Shows prefix reuse matters
   beyond single prompts, chains, agents, multi-turn, which is exactly the
   agent-session regime prefixer targets.

7. **vLLM PagedAttention (SOSP 2023, arXiv:2309.06180) + Automatic Prefix
   Caching.** Production systems already deduplicate shared prefixes at serve
   time; the agent's job is to *create* shareable prefixes by ordering.

8. **Yao et al., "CacheBlend" (EuroSys 2025, arXiv:2405.16444).** Reuses
   precomputed KV for RAG chunks; the cache counterpart of index-time
   prefixes. When prefixer is used on a retrieval pipeline, prefixed chunks get
   *both* the embedding benefit and KV reuse.

9. **Xiao et al., "Attention Sinks" / StreamingLLM (ICLR 2024,
   arXiv:2309.17453) + Liu et al., "Lost in the Middle" (arXiv:2307.03172).**
   The position argument: initial tokens act as attention sinks, and models
   recall best from the start and end of context. The prefix slot is the
   *strong* slot; scoping context belongs there, not mid-prompt.

10. **Vendor caching guidance**: anthropics/skills `prompt-caching.md` (the
    best single how-to: classify every input never/per-session/per-turn/
    per-request; order stable→volatile; audit silent invalidators like
    timestamps and reordered keys), plus OpenAI and Meta prompt-caching docs
    confirming the same rule: append turns, don't rewrite history.

### C. Token efficiency: the complementary lever

11. **LLMLingua family**: LLMLingua (arXiv:2310.05736, ~20× compression),
    LongLLMLingua (ACL 2024; also *reorders* context to fight position bias,
    which pairs with our ordering rules), LLMLingua-2 (arXiv:2403.12968).
    Prefixes *organize* tokens; compression *removes* them. Referenced as a
    follow-on tool, not bundled.

### D. Context as a curated artifact

12. **Zhang et al., "Agentic Context Engineering" (ICLR 2026,
    arXiv:2510.04618).** Treats agent context as an evolving playbook:
    accumulate, refine, and curate via incremental updates instead of rewrites.
    Two failure modes it names; *brevity bias* (over-compressing away the
    useful detail) and *context collapse* (iterative rewriting erodes it),
    are exactly what `NAMESPACES.md` must avoid. Direct support for our rule:
    update the map incrementally, never regenerate it wholesale.

13. **Aider repo-map.** Practitioner precedent for a small, token-cheap index
    file the agent reads once to orient instead of scanning the tree;
    `NAMESPACES.md` is the namespace-flavored version.

14. **Li & Liang, "Prefix-Tuning" (ACL 2021, arXiv:2101.00190); terminology
    note.** Prefix-tuning trains *continuous soft prefixes* on frozen models.
    Different mechanism, same front-position insight; the skill's README
    should disambiguate so nobody expects trainable vectors.

### E. Measurement: the tracking pillar

15. **RAGAS (arXiv:2309.15217).** Reference-free RAG evaluation metrics
    (context precision/recall, faithfulness); the right vocabulary for the
    pipeline arm's before/after report.

16. **Thakur et al., "BEIR" (NeurIPS 2021, arXiv:2104.08663).** Standard
    retrieval benchmark suite; its nDCG@k / recall@k conventions define the
    metrics format `metrics.jsonl` records.

### F. Skill-craft: how to package it

17. **agentskills.io spec + Anthropic skill-authoring best practices**:
    progressive disclosure: metadata always loaded (~100 words), SKILL.md
    <500 lines, bundled files loaded on demand. The skill must obey the token
    discipline it teaches.

18. **obra/superpowers**: `writing-skills` (TDD-for-skills: baseline-fail
    first, "Use when…" descriptions, match-the-form-to-the-failure,
    rationalization tables, red-flags lists) and `using-superpowers` (the
    invocation discipline that makes skills actually trigger).

19. **DietrichGebert/ponytail**: proof a skill can be one tight rule file;
    reach comes from distribution: one canonical spec + thin per-harness
    adapters + tests per manifest.

19b. **blader/humanizer (61k★)**: the cleanest single-skill distribution
    model to copy: one `SKILL.md` at repo root, `.claude-plugin` +
    `.cursor-plugin` manifests, `agents/` + `scripts/` helpers, listed on
    skills.sh. Two more lessons worth stealing: it grounds every rule in an
    external canon (Wikipedia's *Signs of AI writing*; our canon is the
    research list below), and its README leads with one dramatic
    before/after. We need the same: a scoped-vs-broad search demo with real
    numbers.

20. **Anthropic, "Effective context engineering for AI agents" (2025)**:
    context is a finite, curated resource; the framing prefixer is built on.

## 3. What the skill does

When invoked (`/prefixer`) or auto-triggered, the agent applies the
**Prefix Discipline** in four moves:

### Move 1: Map the namespaces (once per repo)

Survey the repo's top-level structure and write `NAMESPACES.md` at repo root
(or `.prefixer/namespaces.md`: final name TBD, see Open Questions): a
token-cheap orientation index the agent, and every future agent session,
reads once instead of scanning the tree.

```markdown
# NAMESPACES
| prefix      | scope                  | contains                        |
|-------------|------------------------|---------------------------------|
| api:        | src/api/**             | REST handlers, routes           |
| auth:       | src/auth/**            | login, sessions, tokens         |
| ui:         | src/components/**      | React components                |
| test:       | tests/**, **/*.test.*  | test suites, fixtures           |
| docs:       | docs/**, *.md          | documentation                   |
| inf:        | infra/**, .github/**   | deploy, CI, config              |
```

Rules the skill teaches for a good map: 5-12 namespaces, path-glob backed,
one-line descriptions written for *search disambiguation* (not marketing),
stale entries pruned on each use. And the ACE rule: **update incrementally,
never regenerate wholesale**: append/refine entries as the repo changes;
wholesale rewrites are how maps go stale and lose detail (context collapse).

### Move 2: Search with prefixes, widen on miss

Agent habit the skill enforces (the main token win inside sessions):

1. Scope every search to the narrowest plausible namespace first:
   `grep "session" src/auth/` not `grep "session" .`;
   `glob "api/**/*.ts"` not `glob "**/*.ts"`.
2. On a miss, widen one level (namespace → repo → vendored dirs last).
3. Report results namespace-tagged (`auth:session.ts:42`) so follow-up
   searches start pre-scoped.

### Move 3: Prefix what you index or write

When the agent creates/maintains anything that gets *searched later*
(docs, chunks, RAG corpora, generated knowledge bases, embeddings inputs),
apply the paper's method:

- Prepend a short domain-descriptive prefix to each indexed unit:
  `"<domain> <artifact-type>: <entity>"`, for example
  `payments API reference: refund endpoint`,
  before embedding or BM25 indexing.
- Discover prefixes by the tiered strategy: sample docs → LLM-propose →
  human/expert review → fall back to the bundled standard library.
- Also applies inside the repo: doc frontmatter (`domain: payments`,
  `type: runbook`), commit/PR namespace tags, symbol naming conventions that
  make intent grep-able.

### Move 4: Keep the prefix stable

Session-level hygiene for the agent's own context:

- Stable scoping context (NAMESPACES map, conventions) goes *early*; volatile
  content (timestamps, UUIDs, current-task state) goes *late*.
- When authoring prompts, system prompts, or skill files: order by stability:
  identity/rules → project context → per-request variables. A single early
  volatile byte invalidates the whole cached prefix downstream.
- When building RAG pipelines: contextualize chunks *before* indexing
  (one-time cost), not at query time (per-query cost). Prefixed chunks are
  also stable strings; precomputing their KV (CacheBlend-style) makes
  repeated retrieval of the same chunks near-free at serve time.

### Tracking (baked in, per request)

`prefixer` ships a measurement loop so claims are verifiable:

- **Artifact**: `.prefixer/metrics.jsonl`: append-only, git-friendly.
  ```json
  {"ts":"2026-10-26","task":"find-session-expiry","tool_calls":9,"searches":4,"est_tokens":6100,"first_try_hit":false}
  ```
- **Session metrics**: searches-per-task, tool-calls-per-task,
  first-try-hit-rate (found it in the first scoped search?), rough token
  estimate per exploration.
- **Pipeline metrics** (when indexing is involved): Hit@k / recall@k /
  nDCG@k (BEIR conventions) and context precision (RAGAS vocabulary), plus a
  cheap A/B; embed 10% of the corpus with and without prefixes, compare
  neighbor cohesion (mean intra-cluster cosine).
- **Baseline → apply → re-measure**: the skill requires a baseline
  measurement before recommending changes, mirroring superpowers'
  no-skill-without-a-failing-test discipline.
- Optional `scripts/measure_search.sh` wrapper that logs grep/glob calls so
  the agent doesn't have to estimate.

## 4. Repository layout (cross-agent distribution)

Canonical skill + generated harness adapters, ponytail-style; one source of
truth, thin copies per runtime, tests on every adapter:

```
prefixer/
├── DESIGN.md
├── README.md
├── SKILL.md                        # canonical, humanizer-style root file
├── references/
│   ├── namespaces.md               # map format + multi-repo stacking
│   ├── index-prefixes.md           # tiered discovery playbook
│   ├── prefix-library.md           # standardized fallback library
│   ├── cache-ordering.md           # stability-ordering checklist
│   └── metrics.md                  # tracking playbook + scoring
├── scripts/
│   ├── init_namespaces.sh          # scaffold the namespace map
│   ├── measure_search.sh           # wrap a search, log metrics
│   └── validate-package.py         # dependency-free package checks
├── .claude-plugin/plugin.json      # "skills": ["./"] → root SKILL.md
├── .claude-plugin/marketplace.json
├── .cursor-plugin/plugin.json      # no skills key → loads root SKILL.md
├── .devin-plugin/plugin.json
├── agents/openai.yaml              # OpenAI-compatible agent display data
├── AGENTS.md                       # contributor invariants
├── CHANGELOG.md                    # version-synced release notes
└── .github/workflows/validate.yml
```

Notes:
- **Root `SKILL.md`, humanizer-style.** For a single-skill repo this is the
  simplest layout that works everywhere; no nested `skills/prefixer/`
  indirection and no symlink loops. The repo does not ship `.agents/skills/`
  or `.devin/skills/` dirs; installers place the skill into consumer paths
  (skills.sh / `npx skills add`, plugin marketplaces, or a manual copy into
  `.agents/skills/prefixer/` which Devin, Codex, Copilot CLI, and Gemini all
  read).
- Keep **one** `SKILL.md` body for all runtimes. Devin-specific frontmatter
  (`allowed-tools`, `triggers`) is valid extra YAML other runtimes ignore;
  put it in the canonical file rather than forking content.
- **Invariants enforced by `validate-package.py`:** version sync across
  SKILL.md `metadata.version` + CHANGELOG + all manifests; manifest
  descriptions equal the SKILL.md description's first sentence; 5,500-word
  cap; every `references/…`/`scripts/…` path mentioned in SKILL.md exists.

## 5. `SKILL.md` outline

> **Scope decision (v0.2.0):** the shipped skill narrowed to one job:
> namespace-scoped codebase search; plus incremental mapping ("map the
> segment, not the world"). The index-prefix and cache-ordering arms below
> moved into `references/` as playbooks for pipeline and prompt authors.
> Kept here for design history.

Frontmatter (spec + Devin fields; description does the triggering):

```yaml
---
name: prefixer
description: Use when searching a codebase repeatedly, building or maintaining
  a docs/RAG/index corpus, or when token-heavy exploration is likely; adds
  namespace prefixes that scope search, descriptive prefixes for indexing,
  and stable-first context ordering, with before/after tracking.
allowed-tools: [read, grep, glob, exec, edit]
triggers: [user, model]
---
```

Body (<500 lines, progressive disclosure; the skill eats its own dog food):

1. **The rule**: one line: "Scope first, vary last, measure the delta."
   Plus superpowers-style MUST-invoke block tuned to this skill's triggers.
2. **Quick reference**: the 3-position table (search / index / prompt) with
   the single action per position.
3. **Move 1-4 procedures**: short, each ending "details: references/x.md".
4. **Tracking protocol**: baseline first, log to `.prefixer/metrics.jsonl`,
   report delta. (This is what the user asked for: it must be a REQUIRED
   slot in the output, not prose; per "Match the Form to the Failure",
   omission-prone elements belong in the output contract.)
5. **Red flags**: rationalization table:
   | Thought | Reality |
   |---|---|
   | "One more broad grep won't hurt" | Broad greps are the token cost you're fixing. Scope it. |
   | "I know where it probably is" | Verify cheaply in the namespace; a wrong guess costs more. |
   | "Prefixes are for big corpora" | A repo IS a corpus. The map pays off by the third search. |
   | "Skip the baseline, just do it" | No baseline = no claim of improvement. Measure first. |
   | "The prefix is just metadata" | Position IS the mechanism. Late prefix = no prefix. |
6. **When NOT to prefix**: single-file scripts, one-off throwaway repos,
   prefixes that duplicate what the path already says, vague prefixes that
   cluster nothing (`"misc:"`), over-specific prefixes that splinter.

## 6. Evaluation plan

Before shipping (superpowers TDD-for-skills, adapted):

- **Baseline scenarios (RED)**: 3-5 tasks on a medium repo:
  "find where X is validated", "add a field to Y", "locate the retry logic".
  Run with no skill; log tool calls, searches, tokens. Expect broad-scan
  behavior = the failure to fix.
- **With skill (GREEN)**: same tasks; expect scoped-first behavior,
  NAMESPACES.md created on task 1, measurably fewer calls by task 3+.
- **Wording micro-tests**: the "widen on miss" and "baseline first" rules
  get 5+ fresh-context reps against a no-guidance control.
- **Pipeline arm**: tiny corpus (50-200 chunks) embedded with/without
  doc-prefixes → report intra-cluster cosine + Hit@5 on a few queries.
- **Harness smoke test**: the superpowers acceptance-test analog; clean
  session, one prompt that should auto-trigger the skill, per runtime.

## 7. Success criteria

- Task 3+ in a session uses fewer searches/tool-calls than the same class of
  task pre-skill (metrics.jsonl delta).
- Indexed corpus shows tighter clusters / higher Hit@k with prefixes.
- Skill triggers correctly from description alone on Devin + one other harness.
- `SKILL.md` < 500 lines; everything else lives in `references/`.

## 8. Open questions for review

1. **Artifact filename**: `NAMESPACES.md` at root (max visibility, aider-style)
   vs `.prefixer/` directory (tidier, hides it). Leaning `.prefixer/` since we
   also need `metrics.jsonl`: one home for all prefixer state.
2. **Skill naming**: `prefixer` (slash: `/prefixer`); fine, or
   `prefix-discipline`? `prefixer` matches the repo; keep it.
3. **How aggressive should auto-trigger be?** Superpowers-style "MUST invoke
   if 1% relevant" maximizes adoption; a calmer "Use when…" description is
   safer for a search-adjacent skill that could otherwise fire on every grep.
4. **Standard prefix library contents**: needs a seed taxonomy (docs/code/API/
   test/infra/…); start ~15 entries, grow from real usage.
5. **Metrics without API access**: agents can't always see real token counts;
   is `est_tokens` (chars/4) acceptable, or should tracking stay
   tool-calls-only? (Recommend: keep both, mark estimate clearly.)
6. **Git noise**: *resolved in v0.3.0*: commit `namespaces.md` (the shared
   prefix), gitignore `metrics.jsonl` (local telemetry). Field report
   confirmed this is the first question every user hits.

## 9. References

**Index-side prefixes**

- Varshney, V. & Mc, M. N. (2026). *Index-Time Prefix Injection for
  Multi-Tenant Retrieval: Improving Search Relevance Without Model
  Fine-Tuning.* ACL 2026 Industry Track.
  https://aclanthology.org/2026.acl-industry.149/
- Anthropic (2024). *Introducing Contextual Retrieval.*
  https://www.anthropic.com/engineering/contextual-retrieval
- Sarthi, P. et al. (2024). *RAPTOR: Recursive Abstractive Processing for
  Tree-Organized Retrieval.* ICLR 2024. https://arxiv.org/abs/2401.18059
- Gao, L. et al. (2022). *Precise Zero-Shot Dense Retrieval without Relevance
  Labels (HyDE).* https://arxiv.org/abs/2212.10496
- Wang, L. et al. (2023). *Query2doc: Query Expansion with Large Language
  Models.* https://arxiv.org/abs/2303.07678

**Prompt-side prefixes & caching**

- Gim, I. et al. (2024). *Prompt Cache: Modular Attention Reuse for
  Low-Latency Inference.* MLSys 2024. https://arxiv.org/abs/2311.04934
- Zheng, L. et al. (2023). *Efficiently Programming Large Language Models
  using SGLang (RadixAttention).* https://arxiv.org/abs/2312.07104
- Kwon, W. et al. (2023). *Efficient Memory Management for Large Language
  Model Serving with PagedAttention (vLLM).* SOSP 2023.
  https://arxiv.org/abs/2309.06180
- Yao, J. et al. (2025). *CacheBlend: Fast Large Language Model Serving for
  RAG with Cached Knowledge Fusion.* EuroSys 2025.
  https://arxiv.org/abs/2405.16444
- Xiao, G. et al. (2024). *Efficient Streaming Language Models with Attention
  Sinks (StreamingLLM).* ICLR 2024. https://arxiv.org/abs/2309.17453
- Liu, N. F. et al. (2023). *Lost in the Middle: How Language Models Use Long
  Contexts.* https://arxiv.org/abs/2307.03172
- anthropics/skills: `prompt-caching.md`.
  https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/prompt-caching.md
- OpenAI. *Prompt caching guide.*
  https://developers.openai.com/api/docs/guides/prompt-caching
- Meta. *Prompt caching (Model API).* https://dev.meta.ai/docs/prompt-caching

**Token efficiency**

- Jiang, H. et al. (2023). *LLMLingua: Compressing Prompts for Accelerated
  Inference.* https://arxiv.org/abs/2310.05736
- Jiang, H. et al. (2024). *LongLLMLingua: Accelerating and Enhancing LLMs in
  Long Context Scenarios.* ACL 2024. https://aclanthology.org/2024.acl-long.91/
- Pan, Z. et al. (2024). *LLMLingua-2: Data Distillation for Efficient and
  Faithful Task-Agnostic Prompt Compression.*
  https://arxiv.org/abs/2403.12968

**Context as artifact**

- Zhang, Q. et al. (2026). *Agentic Context Engineering: Evolving Contexts
  for Self-Improving Language Models.* ICLR 2026.
  https://arxiv.org/abs/2510.04618
- Anthropic (2025). *Effective context engineering for AI agents.*
  https://www.anthropic.com/engineering/effective-context-engineering
- Gauthier, P. *Building a better repository map with tree sitter* (aider).
  https://aider.chat/2023/10/22/repomap.html
- Li, X. L. & Liang, P. (2021). *Prefix-Tuning: Optimizing Continuous Prompts
  for Generation.* ACL 2021. https://arxiv.org/abs/2101.00190

**Measurement**

- Es, S. et al. (2023). *RAGAS: Automated Evaluation of Retrieval Augmented
  Generation.* https://arxiv.org/abs/2309.15217
- Thakur, N. et al. (2021). *BEIR: A Heterogeneous Benchmark for Zero-shot
  Evaluation of Information Retrieval Models.* NeurIPS 2021.
  https://arxiv.org/abs/2104.08663

**Skill-craft**

- Agent Skills specification. https://agentskills.io/specification
- Anthropic. *Skill authoring best practices.*
  https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Vincent, J. *superpowers*: agentic skills framework.
  https://github.com/obra/superpowers
- Gebert, D. *ponytail.* https://github.com/DietrichGebert/ponytail
- *humanizer*: single-file agent skill; canonical source: Wikipedia,
  *Signs of AI writing*. https://github.com/blader/humanizer
  + https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing
- *graphify*: mature multi-platform skill (python library + generated
  per-harness skills via `tools/skillgen`). Adjacent tool, same goal
  (cheaper agent exploration), different mechanism (persistent knowledge
  graph vs scoped search). Comparison and borrowable packaging patterns:
  [docs/vs-graphify.md](docs/vs-graphify.md).
  https://github.com/Graphify-Labs/graphify

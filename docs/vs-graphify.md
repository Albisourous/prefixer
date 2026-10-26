# Prefixer vs graphify

Both tools exist because agents burn too many tokens exploring
codebases. They attack different halves of the problem:

- **[graphify](https://github.com/Graphify-Labs/graphify) replaces search
  with traversal.** Build a persistent model of the repo (nodes, edges,
  communities) then query the model instead of reading files.
- **Prefixer fixes search itself.** Keep grep, but make every grep land
  inside the right directory on the first try.

| | prefixer | graphify |
|---|---|---|
| Artifact | `.prefixer/namespaces.md`, ~12 rows | `graphify-out/`: graph.json, graph.html, GRAPH_REPORT.md, wiki, exporters (GraphML, Cypher, Obsidian) |
| Build | scaffold script + a few minutes of curation | Python package (`uv tool install graphifyy`), tree-sitter AST pass over ~40 languages, optional LLM semantic pass for docs/media |
| Per-use cost | reads a dozen lines once per session | traverse a prebuilt graph; their code benchmark reports ~140K tokens per query |
| Staleness | stale only when top-level layout changes; edit rows by hand | needs `--update`/`--watch` rebuilds as code moves |
| Answers | "which directory should this search hit?" | "how does X connect to Y?" / "explain this concept" / "what are the subsystems?" |
| Inputs | code repos | code + docs + papers + images + video |
| Deps | none: markdown and shell | Python 3.10+, tree-sitter stack, optional whisper/embedders/MCP server |
| Works in | any agent that reads a file + runs grep | any assistant, via generated per-platform skill variants |

## The honest overlap

graphify's README pitches "cut agent token spend by 80%". Prefixer
measures 79% mean bytes saved across its 18-repo corpus (81%
specifically on Graphify-Labs/graphify). These are not contradictory;
they are different denominators:

- **Prefixer's number** is bytes of *search output*: same grep at repo
  root vs inside the namespace's scope. Raw, per-search, reproducible
  with `eval_repo.sh`.
- **Graphify's numbers** are *question-answering* economics: key-fact
  coverage (70.8% → 82% vs a grep/read baseline on ERPNext), ingest
  cost in dollars, retrieval recall on memory benchmarks.

Prefixer does not answer questions; it makes the agent's existing
search cheaper. Graphify does not make grep cheaper; it makes grep
(usually) unnecessary.

## When graphify wins

- **Relational questions.** "Trace the path from AuthModule to
  Database", "explain SwinTransformer": grep cannot answer these;
  traversal can.
- **Cold onboarding.** The generated report's god nodes, communities,
  and suggested questions are a guided tour of a codebase you do not
  understand yet.
- **Mixed corpora.** Papers, screenshots, videos, tickets: things a
  directory map does not describe.
- **Audit trails.** Every edge tagged EXTRACTED / INFERRED / AMBIGUOUS;
  you know what was found vs inferred.

## When prefixer wins

- **Working, not studying.** Editing, refactoring, bugfixing: tasks
  where the agent already knows what it is looking for and just needs
  to find it fast.
- **Zero-install environments.** CI, sandboxes, restricted agents.
  Prefixer is a markdown file; there is nothing to pip install, no
  service, no API key.
- **Small and medium repos.** Prefixer has a ~100-file size gate and
  pays off with a 3-row partial map; a graph pipeline needs a big
  corpus to amortize its build.
- **Session-start context.** `namespaces.md` is small enough to inject
  every session and stays prompt-cache-stable. `graph.json` cannot go
  in context; it must be queried.
- **Human-editable artifacts.** A row is one line a person can fix. The
  graph is machine-maintained.

## They stack

Run graphify when you need to *understand* a system; run prefixer so
that every search an agent makes, including inside graphify's own
repo, stays cheap. Nothing in either excludes the other.

---

## What graphify's codebase teaches (for building your own tool)

Graphify is a mature skill project (~60 modules, 14 platform
integrations). Patterns worth studying, roughly in order of value:

1. **Generate platform adapters, never hand-sync them.**
   `tools/skillgen/` renders 14 SKILL.md variants from shared
   `fragments/` + `platforms.toml` (per-platform deltas only:
   description, dispatch style, shell flavor, monolith vs
   core+references split). `skillgen --check` fails CI on drift,
   `--bless` refreshes `expected/` snapshots. Prefixer's equivalent is
   `validate-package.py` checking invariants over hand-edited
   manifests, fine at 3 platforms, but a generator is the shape that
   survives 10+.

2. **Make docs provably true.** `tests/test_architecture_doc.py`
   imports every symbol ARCHITECTURE.md names, so the doc cannot drift
   from the code. Prefixer's analog: the validator asserts every
   `references/`/`scripts/` path SKILL.md mentions exists. Extending
   that to script flags and public interfaces is cheap insurance.

3. **Stamp installed artifacts.** The installer writes a
   `.graphify_version` beside every installed skill, enabling
   stale-install detection and auto-refresh. Any tool that copies
   itself into user repos benefits from knowing what version it copied.

4. **Detect the host, don't ask.** `install.py` figures out which
   assistant is present and registers the skill for it. A
   `scripts/install.sh` that detects `.claude`/`.devin`/`.agents/` is
   the same idea at shell scale.

5. **Benchmark methodology is a feature.** Their BENCHMARKS.md: one
   model for every system, identical token budgets, a `--max-spend`
   cap, a spend ledger per run, a judge validated against a second
   judge (Cohen's kappa published), and reproduction commands. You do
   not need all of it. The transferable bits are *same harness for
   every system*, *a ledger for every run*, and *a reproduce line
   under every claim*. Prefixer's `eval/run.sh` + RESULTS.md already
   follow that shape.

6. **Commit worked evidence.** `worked/` ships example outputs in the
   repo. Prefixer's `eval/.work/` is the same idea kept out of git;
   `eval/RESULTS.md` is the committed artifact. Either way: show, don't
   claim.

7. **Version the artifact format.** `graph.json` carries
   `schema_version` + `graphify_version` so integrations detect
   incompatible outputs. Worth adding to `namespaces.md` the first
   time its format changes.

8. **Confidence tags on derived data.** EXTRACTED / INFERRED /
   AMBIGUOUS tells consumers what to trust. Any tool that emits
   machine-readable structure for later agents should tag certainty.

Deliberately **not** borrowed: the Python runtime, MCP server, watch
daemon, LLM extraction, exporters, 30-language README. Each carries a
runtime or maintenance cost that a 12-line map does not need. The
lesson is the packaging discipline, not the pipeline.

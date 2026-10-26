# Changelog

## [0.11.1] - 2026-10-26

Bug-fix release: scaffold allocation, eval honesty, installer safety, a
metrics reader, and a style sweep that the validator now enforces.

- **Child namespaces stop starving.** The scaffold's 12-row budget used to
  fill on top-level dirs before `src/`'s children emitted, so one `src:`
  row could crowd out every nested namespace. Children of code-bearing
  dirs now interleave round-robin with top-level rows, biggest parent
  first.
- **Scope dedup is literal.** `emit()` compared scopes with shell glob
  matching, so `docs/api/**` collapsed into `docs/**` and lost its row.
  Dedup now compares scope strings literally.
- **`boot:` no longer collides.** The synthetic entry-points row checks
  the used prefix set and falls back (`entry:`, then `todo-boot:`) when
  a real `boot/` dir already owns the tag.
- **Jumbo-file rows skip non-source.** Candidates are filtered to
  text/source files; `.min.*` bundles, `.map` sourcemaps, and binary/data
  files can no longer become per-file rows. `desc_for` also keeps spaced
  paths intact instead of word-splitting file lists.
- **Eval baselines exclude `.prefixer/`.** The baseline grep in
  `eval_scope.sh` no longer counts the map and its own telemetry as
  searchable repo, which inflated `root_bytes`.
- **`measure_search.sh` scope inference is path-aware.** A regex like
  `foo.*bar` passed to a wrapped grep is no longer logged as the search's
  scope; only real paths or path-like globs count. `--scope` unchanged.
- **New `scripts/report_metrics.sh`.** Reads `metrics.jsonl` and reports
  searches per task, estimated tokens, first-try hit rate, baseline
  probes, the scoped-vs-baseline delta, and per-scope misses/widening.
  Empty and malformed log lines degrade to zero instead of awk noise.
- **`install.sh` skips self-install.** Installing into the checkout's own
  skill dir no longer aborts under `set -e`; the dev-only scripts
  (`test_scaffold.sh`, `validate-package.py`) are excluded from what gets
  copied out.
- **More issues found in the audit.** `search.sh` prefers an exact
  composed-tag match over same-named leaves and no longer feeds an empty
  file list to `xargs grep` (which would read, and on a terminal block
  on, stdin). `check_namespaces.sh` flags every `PREFIXER_SKIP` dir in a
  mapped scope, not a hardcoded subset. `session_start.sh --repo` parses
  positionally like the other scripts. `suggest_map.sh` no longer counts
  `srcx/` as covered by a `src/` row. `eval/agent/run.sh` resets
  `.prefixer/` before every run, so a self-scaffolded map or its metrics
  log can't leak into the next arm. The `devin` adapter wrote
  `.devin/hooks.v1.json` in claude's nested `{"hooks":{...}}` shape;
  devin's file is the hooks object itself (per
  `integrations/hooks.devin.json`), so PostToolUse logging never fired.
- **Second audit pass, seven more fixes.** `eval_scope.sh` accepts the
  documented `tag:` spelling (a trailing colon no longer routes to a tag
  lookup that can never match), refuses an ambiguous bare leaf the same
  way `search.sh` does, and flags `dir/**` scopes that resolve entirely
  inside generated dirs as `baseline_excluded` instead of reporting
  `pct_saved: 100` for a search of nothing. `search.sh`'s ambiguity
  refusal now prints each candidate's scope instead of an empty slot.
  `check_namespaces.sh` coverage counts `dir/**` scopes against their
  own subdirs (a double-slash prefix bug made every child warn). Map
  indentation counts any whitespace, so a tab-indented row composes the
  same tag in `search.sh --list`, `check_namespaces.sh`, and
  `visualize.py`. `visualize.py` reports a usage error instead of an
  IndexError when `-o`/`--max-files` lacks a value. `install_hook.sh`
  refuses a root that resolves to nothing or `/`, where `cd` would
  silently stay put and write `.devin/hooks.v1.json` into the caller's
  cwd, and it rejects flag-shaped positional args.
- **No em/en dashes in user-facing text.** Swept README, CHANGELOG,
  SKILL.md, SPEC.md, DESIGN.md, references/, docs/, generated strings in
  `report.html`, and CLI output; `validate-package.py` now fails on new
  ones.

## [0.11.0] - 2026-10-26

Evidence on behavior, not just bytes: an eval harness that runs real
agent sessions against a fixed task suite, with and without the map,
and counts what the tools actually did.

- `eval/agent/run.sh` runs `tasks.txt` twice per task: `baseline` (no
  `.prefixer/`) vs `mapped` (scaffolded map injected by a SessionStart
  hook). A PostToolUse hook logs every tool call; `summarize.py` turns
  the log into per-task and aggregate tables: tool calls, searches,
  search-output bytes, first-try-scoped rate, answer correctness, and
  whether a baseline run scaffolded its own map. Adapters for `devin`
  and `claude`; a new harness needs four functions in `adapters/`.
- `build_fixture.sh` builds a deterministic ~140-file repo: one unique
  answer symbol per task, decoy vocabulary spread across sibling dirs,
  and a `dist/` dupe tree so root greps pay for generated files too.
- `run.sh --dry-run` verifies fixture + hook wiring without an agent;
  `--fixture`/`--runs` redirect artifacts.
- `adapters/devin_acp.sh` + `acp_run.py`: a third adapter for machines
  where `devin -p` can't authenticate standalone (the bundled CLI wants
  Devin-account creds). Drives `devin acp` with the app-stored API key,
  reconstructs the same tool-call log from `session/update`
  notifications, and injects the map as a prompt prefix; workspace
  hooks don't execute under ACP. `pick_adapter` now prefers a
  ready adapter over the list order, so it wins automatically.

## [0.10.0] - 2026-10-26

From prompt rules to a tool: the discipline now runs as commands, the
log feeds back into the map, and the map injects itself at session
start.

- **`scripts/search.sh`**: scoped search as a command.
  `search.sh auth "expire"` resolves the tag's globs, greps inside
  them, widens one level on a miss (parent namespace, then the repo
  minus generated dirs), reports where hits landed, and appends the
  metrics line; §4-§8 of the skill execute instead of being
  remembered. `--scope`/`--paths`/`--list` turn the map into an index
  other commands can query (`grep -rn x $(search.sh --paths auth)`).
  Ambiguous leaf names report their composed tags instead of silently
  first-matching; the widened search excludes `.prefixer/` so the log
  can't self-hit its own telemetry.
- **`scripts/suggest_map.sh`**: the flywheel. Reads `metrics.jsonl`,
  the map, and the tree, then prints a review list: ADD rows for
  searched-but-unmapped scopes and widened-hit clusters, CHECK for
  uncovered dirs with drift dates, CUT for rows that never scoped a
  logged search, ROOT for unscoped-search counts. Suggestions only; the
  map stays hand-curated.
- **Session-start injection, shipped.** `scripts/session_start.sh`
  prints the map plus a one-line lint verdict (plain or as the
  `additionalContext` hook envelope Claude Code and Devin both read);
  `scripts/install_hook.sh` writes `.devin/hooks.v1.json` or merges
  `.claude/settings.json`. Reference snippets + a consumer PR-check
  workflow live in `integrations/`.
- **`SPEC.md`**: the namespaces.md format contract: file, header, row
  grammar, scope grammar, tag addressing, companion artifacts. For
  tools that read or write maps.
- **`scripts/lib_scope.sh`**: one shared copy of the scope grammar,
  glob→regex resolver, tag parser, exclusion lists, and root-finding.
  `check_namespaces.sh`, `eval_scope.sh`, `eval_repo.sh`,
  `init_namespaces.sh`, `measure_search.sh` now source it; a fix like
  the unbalanced-brace guard lands everywhere at once.
- **Eval corpus grows to 18 repos**: flask, fastapi, cobra, tokio, gson
  join (python-web, go-lib, rust-async, java shapes).
- Metrics schema gains `ns`, `pattern`, `widened_to`, `hit_dirs`
  (search.sh emits them; suggest_map.sh reads them). `install.sh`
  copies `SPEC.md`; `validate-package.py` checks `integrations/` and
  SPEC.md mentions plus every script's shebang.

Accuracy fixes:

- **Generated scratch stops inflating measurements.** `.work` (eval-corpus
  clones) joins `PREFIXER_SKIP`/`PREFIXER_GREP_SKIP`, and `match_scope`,
  `resolve`, and `scope_files` now prune skipped dirs inside a scoped
  parent; `eval/**` no longer greps vendored clones under `eval/.work`.
  `init_namespaces.sh` sampling and `check_namespaces.sh`'s
  generated-path fail follow the same list.
- **`visualize.py` counts the repo's own files.** `.work` joins its skip
  set (a corpus checkout had 924 MB / ~100k files masquerading as the
  59-file repo), coverage no longer rounds 99.9% into a `100%` claim,
  and the first-try-hit card shows its sample size (`n=`).
- **`[` `]` `{` `}` `\` are literal in scopes.** Character classes were
  never scope syntax, but an unescaped `[` crashed `visualize.py`'s
  `re.compile` and made `grep -E` silently return nothing. `glob_re`
  now escapes them in both implementations, so `src/file[1].txt` matches
  the file named exactly that, and no glob can produce an invalid
  pattern.
- **Cross-universe evals are flagged, not averaged.** A row whose scope
  lives entirely inside dirs the baseline grep skips (vendored, built,
  generated) now emits `pct_saved:null` + `baseline_excluded:true`;
  `eval_repo.sh` prints `n/a` with a reason instead of a blank `%`, and
  `visualize.py` shows `-` badges for those rows and for 0-hit probes.
  `eval_repo.sh` also parses negative `pct_saved` (`-[0-9]+`) instead
  of counting the row as zero.
- **File scopes no longer swallow directories.** `check_namespaces.sh`'s
  coverage check matched `*/**`, which in a case pattern means "any token
  containing a slash", so `src/file.txt` marked `src/` covered. Only
  a literal `/**` suffix widens to its dir now.
- **One row grammar.** `check_namespaces.sh` accepts leading whitespace
  before a row's `|` like `scope_pairs` and `visualize.py` already did,
  so a table nested in a Markdown list is linted, not silently skipped.

## [0.9.0] - 2026-10-26

A visualizer, plus another round of scaffold truthfulness: prefixes stay
name-derived, contains cells stay clean, and the corpus measures fresh
maps instead of stale ones.

- **`scripts/visualize.py`**: stdlib-only, no dependencies. Reads
  `.prefixer/namespaces.md`, walks the repo (same generated-dir
  exclusions and glob semantics as the shell scripts), and writes a
  self-contained `.prefixer/report.html`: stat cards, the map table,
  a coverage partition bar plus an interactive file tree where every
  file is colored by the namespace that scopes it (unscoped files
  gray), per-namespace scoped-vs-root byte bars reusing
  `eval_scope.sh` probes, and a `metrics.jsonl` timeline with
  first-try-hit markers. Flags: `-o OUT`, `--no-eval` (fall back to
  logged eval lines), `--max-files N`, `--open`. `report.html` is
  appended to `.prefixer/.gitignore` like `metrics.jsonl`.

Scaffold and lint fixes:

- **`expand_scope()` no longer hangs** on an unbalanced `{`: a typo'd
  `src/{a,b` scope recursed forever; now it emits the token literally
  and the dead-scope check reports it.
- **BSD `sed` portability.** `[ \t]` matched a literal `t` on macOS and
  corrupted `tools/**`-shaped scope tokens into false `uncovered`
  warnings; now `[[:blank:]]`.
- **`contains` is sanitized**: `|` and `\r` stripped, newlines folded;
  a pipe in derived text made phantom table cells for every consumer.
- **`desc_for` skips badge/link/ASCII-art lines**: the first doc hit
  for a dir name is usually `[![Build status](…`, not prose.
- **Prefixes stay name-derived.** The `file_token` fallback produced
  misleading names (`.changeset/`→`undici:`, `acceptance/`→`create:`);
  long names now use the name itself or a deterministic vowel-drop
  shortening. Same-name children under different parents qualify with
  the parent dir instead of a draft `todo-` prefix.
- **More code parents descend**: `crates`, `cmd`, `internal`, `pkg`,
  `plugins`, `themes`, `components`, `tools`, the project-named dir
  (`django/django`), and any top dir holding ≥3 code-bearing children.
- **Generated/data files out of rows**: lockfiles are excluded from the
  root-file scope, and jumbo rows skip `.txt`/`.json`/lock/snapshot/
  baseline/fixture files so data can't crowd out real source.
- **`eval/run.sh` refreshes maps**: the corpus deletes the disposable
  eval map before scaffolding; weekly CI was measuring the first-run
  map against moving repos.

## [0.8.2] - 2026-10-26

Eval hardening: the scripts now measure what they claim to: real glob
semantics, an honest baseline, visible failure modes, plus the docs and
corpus to back the claims.

- **Glob semantics are defined and enforced.** Scopes are repo-relative
  and root-anchored: `*` stays inside one directory level, `**` crosses,
  `?` is one char, `{a,b}` expands arm-wise, a leading `/` anchors at
  root. `check_namespaces.sh` and `eval_scope.sh` share one
  glob→regex resolver; `find -path` (whose `*` crossed `/`) is gone.
- **No `eval` on scope cells.** A hostile `namespaces.md` could inject
  shell through the old expansion; scope strings are now tokenized, never
  executed, and metacharacters fail the lint.
- **Spaced paths work end to end.** Scaffold, lint, and eval keep
  `my dir/**` as one token instead of shredding it.
- **Honest baseline.** `eval_scope.sh`'s root search is case-sensitive
  and excludes the same generated/vendor dirs the map does; a grep
  through `node_modules` measured a strawman, not the counterfactual.
- **Blind spots are flagged, not scored.** `eval_repo.sh` reports `n/a`
  for a namespace whose own name gets 0 scoped hits instead of a
  meaningless 100%.
- **pipefail SIGPIPE fix.** `resolve()` used `grep -q`, which exits on
  first match and SIGPIPEs `find`; under `pipefail` every live scope
  reported dead. Fixed with `grep -c`.
- **Generated dirs are a fail,** matching the "never map them" rule;
  previously a warn.
- **Binary/asset namespaces are marked `names only`** by the scaffold;
  a content grep there is noise; the useful search is filenames.
- **`measure_search.sh` logs crashed probes as `"error":true`** with the
  exit status instead of a phantom 0-hit search.
- **The 12-row cap says so.** Scaffolded maps end with `unmapped:` naming
  the dirs the cap dropped; previously they vanished silently.
- **`head -200` truncation removed** from scoped-path expansion; it
  undercounted `ns_bytes` on large namespaces and inflated `pct_saved`.
- **`eval_scope.sh` escapes JSON output** (`ns`, `pattern`); quoted
  patterns no longer emit malformed lines into `metrics.jsonl`.
- **Namespace lookup is exact-match**: regex metachars in a prefix
  (`.dev` matching the `xdev` row) can't mis-resolve a scope.

Docs and corpus:

- **Eval corpus grows to 13 repos.** `eval/repos.txt` gains the
  most-installed agent-skill repos: mattpocock/skills, anthropics/skills,
  addyosmani/agent-skills, blader/humanizer, and Graphify-Labs/graphify.
  Corpus mean: 85% of search-output bytes saved across 123 namespaces.
- **README** leads the measured table with the skill repos, and "Not to
  be confused with" gains knowledge-graph skills (graphify: persistent
  queryable graph vs a 12-line search map; they stack) and skills packs
  (many skills vs one skill doing one job).
- **Site** shows the 13-repo table with per-repo ranges, a chart of every
  namespace's saved %, a graphify/skills-pack FAQ entry, and JSON-LD to
  match. `docs/llms.txt` gains a Compare section.
- **`docs/vs-graphify.md`**: the full prefixer-vs-graphify comparison
  (different denominators, different questions, when each wins) plus
  field notes on the packaging patterns worth borrowing from
  Graphify-Labs/graphify: generated platform skills, doc-drift tests,
  version stamps, host detection, benchmark discipline.
- **`scripts/install.sh`**: host-detecting installer (the graphify
  `install.py` pattern at shell scale). Finds `.claude`/`.devin`/`.agents`
  markers, installs project- or user-level, stamps `.prefixer_version`
  beside the skill for stale-install detection.
- **Findability.** README gains a 30-second quickstart, release +
  skills.sh badges, and a platform table; the site gains a real 1200x630
  `og-image.png` (twitter `summary_large_image`), a HowTo JSON-LD block
  for the install steps, `robots.txt`, and `sitemap.xml`; expanded meta
  keywords. Repo description updated to the 13-repo number.

## [0.8.1] - 2026-10-26

Discovery: surface the skill for "token efficiency" asks. No behavior
change.

- **SKILL.md description** gains "improve a codebase's token efficiency"
  and a trigger for "how do I make my codebase cheaper/more
  token-efficient for agents" so other agents recommend prefixer on that
  ask. First sentence unchanged; manifests still conform.
- Manifest keywords gain `token-efficiency` (Claude, Cursor, Devin,
  marketplace).
- README and `docs/llms.txt` agent-facing notes name the token-efficiency
  ask; `agents/openai.yaml` short description mentions it.

## [0.8.0] - 2026-10-26

Field report, round two: telemetry that stays honest, a scaffold that
covers the whole repo (root files, dot dirs, and jumbo files), richer
`contains` derivation, and a public eval corpus that keeps the savings
claim honest.

- **`contains` samples file contents.** The scaffold reads the files it
  maps: first a doc comment (`//`, `#`, `--`, `/*`, `"""`; shebangs,
  license headers, preprocessor lines filtered), then exported symbols
  (`exports handleRequest, handleResponse`), then bare file names.
  Representative files are picked by name overlap with the dir
  (`auth/AuthService.ts` speaks for `auth/`). Still derived, never
  declared: no wordlists, no LLM calls.
- **Eval corpus.** `eval/repos.txt` lists eight public repos of different
  shapes (monorepo, CLI, web framework, docs site); `eval/run.sh`
  shallow-clones, scaffolds, lints, and evals each, then rewrites
  `eval/RESULTS.md`. A weekly workflow commits the refreshed table;
  corpus mean today: 84% of search-output bytes saved.
- **`eval_repo.sh` evals by composed tag.** Rows iterate as
  `tag + leaf + scope`, so a nested `orders:checkout:` is measured against
  its own scope instead of whichever `checkout:` row came first.
- **`eval_scope.sh`** resolves composed tags (`payments:checkout`), takes
  an optional explicit scope argument, refuses non-glob scope text
  instead of eval'ing it, and escapes the pattern/tag in its JSON line.
- **`check_namespaces.sh`** fails rows whose scope is not plain glob
  syntax (scope text is `eval`'d for brace expansion; it can never be
  shell now), lints a relative repo argument correctly (cd invalidated
  the root-relative map path), and treats brace lists as alternations in
  coverage checks.
- `.prefixer/.gitignore` is appended to, not overwritten, by the scripts
  that create it; the validate workflow also `bash -n`s every script.
- **`measure_search.sh` anchors at the repo root.** The log lands beside
  the map (nearest `.prefixer/` walking up, else git toplevel); running
  it from a subdirectory can no longer create a stray `.prefixer/`. Adds
  a `scope` field (`--scope`, else inferred from the command's path args,
  `root` when unscoped), `--hit`/`--miss` for agent-reported
  `first_try_hit`, and ISO-8601 UTC timestamps so same-day lines stay
  ordered.
- **`init_namespaces.sh` maps what dirs miss.** Rows now cover
  non-generated dot dirs (`.devin`, `.github`, agent tooling), the files
  at repo root (`package.json`, `vite.config.ts`, root docs; `cfg:` or
  `doc:` depending on content), and jumbo files over ~3k lines as
  per-file rows with declaration landmarks (`~10k lines:
  spawnWave@1270`). Synthetic rows reserve budget inside the 12-row cap
  so `cfg:`/`boot:` survive crowded trees.
- **`check_namespaces.sh` coverage warnings** now include dot dirs and
  uncovered root files.
- **`references/namespaces.md`**: jumbo-file convention and a
  session-start injection recipe: hook the map into the harness's
  session-start context instead of relying on agents remembering to read
  it. **`references/metrics.md`** documents `scope` and the new flags.
- SKILL.md: "session-start beats remembering" note; metrics example
  shows the ISO timestamp.

## [0.7.1] - 2026-10-26

Description and docs: better triggers, no behavior change.

- **SKILL.md description** gains "save tokens" and "cut context cost" as
  trigger phrases so agents surface the skill when users ask for cheaper
  search. First sentence unchanged; manifests still conform.
- **README + site** rewritten to plain style, no dash connector overuse;
  landing page gains a flow diagram, stat cards, and real eval output.

## [0.7.0] - 2026-10-26

Whole-repo evaluation with nothing hardcoded.

- **`eval_repo.sh`**: lints a map, then probes every namespace with its
  own name as the grep pattern (derived vocabulary probing itself, zero
  per-repo config). Prints a per-row hit/byte table and the mean
  `pct_saved`. Measured on public repos: 89-91% of search-output bytes
  eliminated on average.
- README now carries measured numbers from public repos instead of an
  illustrative before/after.

## [0.6.0] - 2026-10-26

Map linting and a real token-savings meter.

- **`check_namespaces.sh`**: lints a map: dead scopes (globs that resolve
  to nothing), duplicate tags across nesting levels, draft/TODO rows,
  generated dirs mapped, uncovered code dirs. Brace globs `{a,b}` resolve
  the way the searching shell expands them.
- **`eval_scope.sh`**: runs one grep at repo root and the same grep inside
  a namespace, reports hits/bytes/`est_tokens_saved` as JSON (`--log`
  appends to metrics.jsonl). On real repos: 98-99% of search output
  eliminated per scoped query (~0.6-0.9M est. tokens).
- `test_scaffold.sh` grew to 16 assertions covering both new scripts.

## [0.5.0] - 2026-10-26

Nested namespaces and zero-TODO scaffolds: sub-teams inside a codebase.

- **Sub-namespaces.** The scaffold descends a second level where a child
  holds sub-teams (`services/payments/{checkout,refunds}`) and emits
  indented rows that compose multi-level tags: `payments:checkout:`.
  Uniqueness is per parent level, so `checkout:` can live under both
  `payments:` and `orders:` without a composite name.
- **Zero-TODO drafts.** Empty dirs are skipped instead of mapped; prefix
  derivation always lands on a real name (short name, distinguishing
  segment, dominant file token, full name); `contains` falls back to real
  file names. Same-parent collisions qualify as `parent-name:`.
- New `scripts/test_scaffold.sh`: fixture test covering repo slugs,
  nested rows, name collisions, generated-dir and empty-dir skips;
  wired into the validate workflow.

## [0.4.0] - 2026-10-26

Derived prefixes and org-unique maps, built for the many-codebases case.

- **Prefixes are derived, not declared.** `init_namespaces.sh` dropped its
  hard-coded wordlist: a prefix now comes from the codebase's own
  vocabulary: a distinguishing dir-name segment no sibling shares, then
  the dominant file-name token, then the dir name itself, then a visible
  `todo-` marker. `contains` cells fall back to the real file names inside
  a scope instead of only agent-doc mentions.
- **`repo:` header.** Every map now declares its codebase's unique
  qualifier, derived from the git remote (dir name as fallback). Qualified
  tags (`payments:auth:`) stay unique when dozens of codebases share
  directory names, for shared indexes, org-level maps, and multi-repo
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

- New rule: map the segment you're working in, not the whole repo; partial
  maps are legal, rows get earned by real searches.
- New "Where it earns its keep" section: the sharp use cases (first session
  in a large repo, monorepos, many codebases, repeated exploration).
- Index-time prefix and cache-ordering rules moved out of the skill body;
  those playbooks stay in `references/` for pipeline and prompt authors.
- Tighter description and red-flags table tuned to search discipline.

## [0.1.0] - 2026-10-26

Initial release.

- `SKILL.md`: the prefix discipline: namespace maps, scoped-first search,
  index-time doc prefixes, cache-stable ordering, per-task metrics.
- `references/`: namespaces, index prefixes, prefix library, cache ordering,
  and metrics playbooks.
- `scripts/`: `init_namespaces.sh`, `measure_search.sh`,
  `validate-package.py`.
- Plugin manifests for Claude, Cursor, and Devin; `agents/openai.yaml`.

# The namespaces.md format: SPEC v1

The contract a `.prefixer/namespaces.md` file satisfies. Written for
tools that read or write the map; the reasoning lives in
`references/namespaces.md`. `scripts/check_namespaces.sh` is the
reference linter; `scripts/lib_scope.sh` is the reference
implementation of the scope grammar.

Status: **stable**. Rules here are additive-compatible; readers must
ignore lines they do not understand, and writers must not repurpose
existing lines.

## File

- Path: `.prefixer/namespaces.md` at the repository root.
- Encoding UTF-8, LF line endings. The file is checked into version
  control; `.prefixer/metrics.jsonl` beside it is local telemetry and
  carries its own `.gitignore`.

## Structure

1. Title line: `# namespaces`.
2. Header line: `repo: <slug>`: the codebase's unique qualifier,
   lowercase, `[a-z0-9-]`, derived from the git remote or directory
   name. Makes every tag globally unique: `payments:auth:` never
   collides with `checkout:auth:` when many codebases share one index.
3. A pipe table of rows, each `| prefix | scope | contains |`.
4. Optional footer line: `unmapped: <dir>, <dir>, … (reason)`: names
   the directories a row cap dropped. Absent means nothing was dropped.

## Rows

- **prefix**: `[a-z0-9-]+:` after trimming. 2-8 characters by
  convention, lowercase, derived from the codebase's own vocabulary
  (directory names, dominant file tokens), never an invented category.
  Unique within its parent level only.
- **Indentation is structure.** A row whose prefix cell starts with
  whitespace nests under the most recent shallower row; its full tag is the
  ancestor chain: parent `payments:` + nested `checkout:` composes
  `payments:checkout:`. Depth is bounded by need, not by the format.
- Readers ignore leading whitespace on a row line: a table nested in a
  Markdown list is still a table.
- **scope**: one or more globs, comma-separated. See grammar below.
- **contains**: one line naming what lives there, for disambiguation
  between siblings. `TODO`, `undocumented`, or a `todo-` prefix marks a
  draft row; a draft is unfinished, and linters fail it.
- Rows naming generated or vendored paths (`node_modules`, `vendor`,
  `dist`, `build`, `target`, `out`, `coverage`, `*-out`, …) are invalid.
- A row whose scope resolves to zero real paths is a **dead scope**:
  a fail, not a warning.

## Scope grammar

Repo-relative, root-anchored glob:

| Token | Meaning |
|---|---|
| `dir/**` | `dir` and every descendant |
| `dir/*` | direct children of `dir` only; `*` never crosses `/` |
| `?` | exactly one non-`/` character |
| `{a,b}/**` | brace list expands arm-wise: `a/**`, `b/**` |
| `a/**, b/**` | comma list; alternate scopes in one row |
| `/x` | leading `/` anchors at the repo root (same as `x`) |
| `file.txt` | literal path; explicit filenames are legal scopes |

Characters that make scope text invalid: `$()`, backticks, `;`, `|`,
`&`, `<`, `>`, newlines. A scope is a glob, never a shell command;
consumers must tokenize, never evaluate.

`[` and `]` are literal characters, not character classes; a scope
`src/file[1].txt` matches the file named exactly that. No glob can
produce an invalid pattern; an unmatched scope is a dead scope, never
a parse error.

## Companion artifacts

- `.prefixer/metrics.jsonl`: append-only JSONL, one line per logged
  task or search. Field vocabulary in `references/metrics.md`; writers
  emit the keys they can honestly fill.
- `.prefixer/report.html`: rendered report (`scripts/visualize.py`).
- `.prefixer/.gitignore`: covers the local artifacts above.

## Tag addressing

A tag addresses one namespace: `<repo>:<tag-chain>:`, for example
`ripgrep:crates:core:`. Readers resolving a bare leaf (`core:`) when
several rows share it must report ambiguity rather than pick silently.

## Non-goals

The map scopes *where to search*, not *what a file means*. It is not a
docs index, a dependency graph, or a code summary; it is the smallest
file that makes the first search land inside the right tree.

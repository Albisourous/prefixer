# Guide for agents

How to change prefixer without breaking its package or its prompt.

## What this repo contains

Prefixer is an agent skill written in Markdown. `SKILL.md` at the root is
the prompt agents read, and the source of truth. There is no build step.

## Layout

- `SKILL.md`: the skill: YAML frontmatter plus numbered rules.
- `SPEC.md`: the namespaces.md format contract for other tools.
- `references/`: deep dives loaded on demand (progressive disclosure).
- `scripts/`: helpers the skill calls, plus `validate-package.py`.
  `lib_scope.sh` is the single copy of the scope grammar; scripts
  source it, never re-implement expansion or glob matching inline.
- `integrations/`: snippets consumer repos drop in: session-start
  hook configs and a PR lint workflow.
- `.claude-plugin/`, `.cursor-plugin/`, `.devin-plugin/`: per-harness
  manifests. Claude's manifest points its loader at the root
  (`"skills": ["./"]`).
- `agents/openai.yaml`: display data for OpenAI-compatible agents.

## Invariants

- **Version:** the same version in `metadata.version` (SKILL.md
  frontmatter), `CHANGELOG.md`'s first heading, and every
  `*-plugin/plugin.json`.
- **Description:** plugin manifests reuse the first sentence of the SKILL.md
  description.
- **Length:** every word of SKILL.md is read on each use. Cap is 5,500
  words; additions must earn their tokens. Move bulk to `references/`.
- **Links:** every `references/…` or `scripts/…` path mentioned in SKILL.md
  must exist.
- **Portability:** no instructions that assume one agent tool.
- **Sync:** keep SKILL.md and README.md claims consistent.

## Writing style

Plain Language: lead with the point, common words, active voice, short
sentences, `must` for requirements, lists and tables where they help.

No em dashes or en dashes in user-facing text (README, CHANGELOG,
`docs/` pages, site copy, strings in generated output such as
`report.html`). Use a comma, colon, or full stop instead. Run the
`humanizer` skill ([blader/humanizer](https://github.com/blader/humanizer))
over any user-facing text before shipping; it also catches staged
openers, one-line closers, forced triads, bold-label lists, and filler.
The repo predates this rule, so sweep a file when you touch it instead
of copying its existing punctuation.

## Checks

Run `python3 scripts/validate-package.py` before publishing. Add a
CHANGELOG.md note for any behavior change.

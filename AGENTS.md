# Guide for agents

How to change prefixer without breaking its package or its prompt.

## What this repo contains

Prefixer is an agent skill written in Markdown. `SKILL.md` at the root is
the prompt agents read, and the source of truth. There is no build step.

## Layout

- `SKILL.md` — the skill: YAML frontmatter plus numbered rules.
- `references/` — deep dives loaded on demand (progressive disclosure).
- `scripts/` — helpers the skill calls, plus `validate-package.py`.
- `.claude-plugin/`, `.cursor-plugin/`, `.devin-plugin/` — per-harness
  manifests. Claude's manifest points its loader at the root
  (`"skills": ["./"]`).
- `agents/openai.yaml` — display data for OpenAI-compatible agents.

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

## Checks

Run `python3 scripts/validate-package.py` before publishing. Add a
CHANGELOG.md note for any behavior change.

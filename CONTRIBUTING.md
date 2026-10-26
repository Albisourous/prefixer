# Contributing

Prefixer is a Markdown skill: `SKILL.md` is the product, everything else
supports it. Small focused PRs win; if you're unsure whether a change fits,
open an issue first.

## Dev loop

```bash
python3 scripts/validate-package.py   # frontmatter, version sync, links
bash scripts/test_scaffold.sh         # fixture test: derivation, lint, eval
```

Both run in CI on every PR. A change that fails either one will not merge.

## Rules that keep the skill working

- **Every word of SKILL.md is read on each use.** Cap is 5,500 words;
  additions must earn their tokens. Move bulk to `references/`.
- **Version sync.** `metadata.version` in SKILL.md, the top `CHANGELOG.md`
  heading, and every `*-plugin/plugin.json` must match. The validator
  enforces it.
- **No hardcoding in scripts.** Prefixes and descriptions are derived from
  the codebase's own vocabulary: dir names, file-name tokens, agent docs.
  A change that adds a lookup table of names is the wrong direction.
- **Maps are edit-in-place.** `namespaces.md` is never regenerated
  wholesale; curated detail and prompt-cache stability depend on it.
- **Plain language.** Lead with the point, common words, active voice.
  Keep the house style consistent with `AGENTS.md`.

## Good first contributions

- More derivation heuristics that still end at a real, codebase-derived
  name, never a lookup table.
- Repo shapes the scaffold handles badly (report with the tree shape).
- Eval numbers from your repos (`eval_repo.sh`): real-world
  `pct_saved` tables help tune the rules.

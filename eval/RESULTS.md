# Eval corpus

`eval/run.sh` shallow-clones each repo in `repos.txt`, scaffolds a
map, lints it, and probes every namespace with `eval_repo.sh` — each
row's own name as the grep pattern, nothing configured per repo.
Regenerated weekly by `.github/workflows/eval.yml`.

| repo | shape | namespaces | mean saved | range | lint |
|------|-------|-----------:|-----------:|-------|------|
| [obra/superpowers](https://github.com/obra/superpowers) | skills-pack | 12 | 93% | 69–100% | warn |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | web-app | 12 | 91% | 68–100% | warn |
| [expressjs/express](https://github.com/expressjs/express) | web-framework | 6 | 80% | 11–100% | ok |
| [psf/requests](https://github.com/psf/requests) | python-library | 7 | 68% | 2–100% | ok |
| [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | rust-cli | 10 | 85% | 31–100% | warn |
| [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | monorepo | 12 | 84% | 3–100% | ok |
| [rust-lang/book](https://github.com/rust-lang/book) | docs-site | 12 | 80% | 7–100% | warn |
| [cli/cli](https://github.com/cli/cli) | go-cli | 12 | 92% | 40–99% | warn |

**Corpus mean: 84% of search-output bytes saved across 8 repos.**

Last run: 2026-10-26 (UTC)

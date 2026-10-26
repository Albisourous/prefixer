# Eval corpus

`eval/run.sh` shallow-clones each repo in `repos.txt`, scaffolds a
map, lints it, and probes every namespace with `eval_repo.sh` — each
row's own name as the grep pattern, nothing configured per repo.
Rows whose name never appears in their files report `n/a` and are
excluded — a 0-hit probe can't prove savings.
Regenerated weekly by `.github/workflows/eval.yml`.

| repo | shape | namespaces | mean saved | range | lint |
|------|-------|-----------:|-----------:|-------|------|
| [obra/superpowers](https://github.com/obra/superpowers) | skills-pack | 5 | 85% | 69–98% | warn |
| [mattpocock/skills](https://github.com/mattpocock/skills) | skills-pack | 7 | 88% | 55–97% | warn |
| [anthropics/skills](https://github.com/anthropics/skills) | skills-pack | 5 | 81% | 12–99% | warn |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | skills-pack | 10 | 87% | 65–99% | warn |
| [blader/humanizer](https://github.com/blader/humanizer) | agent-skill | 2 | 85% | 84–87% | ok |
| [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | knowledge-graph | 8 | 77% | 15–99% | warn |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | web-app | 8 | 91% | 68–99% | warn |
| [expressjs/express](https://github.com/expressjs/express) | web-framework | 4 | 70% | 11–95% | warn |
| [psf/requests](https://github.com/psf/requests) | python-library | 5 | 58% | 2–99% | warn |
| [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | rust-cli | 7 | 80% | 30–99% | warn |
| [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | monorepo | 8 | 78% | 8–99% | warn |
| [rust-lang/book](https://github.com/rust-lang/book) | docs-site | 9 | 73% | 7–99% | warn |
| [cli/cli](https://github.com/cli/cli) | go-cli | 11 | 92% | 39–99% | warn |

**Corpus mean: 80% of search-output bytes saved across 13 repos.**

Last run: 2026-10-26 (UTC)

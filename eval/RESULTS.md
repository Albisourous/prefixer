# Eval corpus

`eval/run.sh` shallow-clones each repo in `repos.txt`, scaffolds a
map, lints it, and probes every namespace with `eval_repo.sh`: each
row's own name as the grep pattern, nothing configured per repo.
Rows whose name never appears in their files report `n/a` and are
excluded; a 0-hit probe can't prove savings.
Regenerated weekly by `.github/workflows/eval.yml`.

| repo | shape | namespaces | mean saved | range | lint |
|------|-------|-----------:|-----------:|-------|------|
| [obra/superpowers](https://github.com/obra/superpowers) | skills-pack | 5 | 85% | 70-98% | warn |
| [mattpocock/skills](https://github.com/mattpocock/skills) | skills-pack | 9 | 91% | 55-99% | warn |
| [anthropics/skills](https://github.com/anthropics/skills) | skills-pack | 11 | 72% | 14-99% | ok |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | skills-pack | 8 | 85% | 66-98% | warn |
| [blader/humanizer](https://github.com/blader/humanizer) | agent-skill | 2 | 85% | 84-87% | ok |
| [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | knowledge-graph | 11 | 81% | 15-99% | warn |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | web-app | 8 | 92% | 77-99% | warn |
| [expressjs/express](https://github.com/expressjs/express) | web-framework | 8 | 80% | 12-97% | ok |
| [psf/requests](https://github.com/psf/requests) | python-library | 7 | 69% | 2-99% | ok |
| [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | rust-cli | 9 | 70% | 0-99% | warn |
| [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | monorepo | 7 | 75% | 8-99% | warn |
| [rust-lang/book](https://github.com/rust-lang/book) | docs-site | 7 | 66% | 7-99% | warn |
| [cli/cli](https://github.com/cli/cli) | go-cli | 11 | 88% | 39-99% | warn |
| [pallets/flask](https://github.com/pallets/flask) | python-web | 11 | 75% | 38-97% | warn |
| [fastapi/fastapi](https://github.com/fastapi/fastapi) | python-web | 10 | 87% | 12-99% | warn |
| [spf13/cobra](https://github.com/spf13/cobra) | go-cli-lib | 3 | 81% | 58-95% | warn |
| [tokio-rs/tokio](https://github.com/tokio-rs/tokio) | rust-async | 11 | 86% | 45-99% | warn |
| [google/gson](https://github.com/google/gson) | java-library | 11 | 57% | 3-90% | ok |

**Corpus mean: 79% of search-output bytes saved across 18 repos.**

Last run: 2026-10-26 (UTC)

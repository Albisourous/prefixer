# Eval corpus

`eval/run.sh` shallow-clones each repo in `repos.txt`, scaffolds a
map, lints it, and probes every namespace with `eval_repo.sh`: each
row's own name as the grep pattern, nothing configured per repo.
Rows whose name never appears in their files report `n/a` and are
excluded; a 0-hit probe can't prove savings.
Regenerated weekly by `.github/workflows/eval.yml`.

| repo | shape | namespaces | mean saved | range | lint |
|------|-------|-----------:|-----------:|-------|------|
| [obra/superpowers](https://github.com/obra/superpowers) | skills-pack | 8 | 77% | 59-95% | ok |
| [mattpocock/skills](https://github.com/mattpocock/skills) | skills-pack | 8 | 83% | 52-98% | ok |
| [anthropics/skills](https://github.com/anthropics/skills) | skills-pack | 9 | 55% | 4-99% | FAIL |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | skills-pack | 5 | 84% | 67-97% | FAIL |
| [blader/humanizer](https://github.com/blader/humanizer) | agent-skill | 4 | 67% | 0-94% | ok |
| [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | knowledge-graph | 10 | 78% | 0-99% | ok |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | web-app | 8 | 91% | 76-99% | ok |
| [expressjs/express](https://github.com/expressjs/express) | web-framework | 3 | 60% | 11-86% | ok |
| [psf/requests](https://github.com/psf/requests) | python-library | 5 | 74% | 40-99% | ok |
| [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | rust-cli | 10 | 65% | 17-99% | ok |
| [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | monorepo | 9 | 68% | 10-99% | ok |
| [rust-lang/book](https://github.com/rust-lang/book) | docs-site | 2 | 66% | 34-98% | ok |
| [cli/cli](https://github.com/cli/cli) | go-cli | 10 | 76% | 22-99% | warn |
| [pallets/flask](https://github.com/pallets/flask) | python-web | 11 | 77% | 29-99% | ok |
| [fastapi/fastapi](https://github.com/fastapi/fastapi) | python-web | 7 | 76% | 12-99% | FAIL |
| [spf13/cobra](https://github.com/spf13/cobra) | go-cli-lib | 4 | 85% | 67-95% | ok |
| [tokio-rs/tokio](https://github.com/tokio-rs/tokio) | rust-async | 10 | 71% | 27-99% | ok |
| [google/gson](https://github.com/google/gson) | java-library | 11 | 59% | 2-99% | ok |

**Corpus mean: 72% of search-output bytes saved across 18 repos.**

Last run: 2026-11-09 (UTC)

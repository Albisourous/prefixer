# Getting help with prefixer

Here is where to go, depending on what you need.

## Questions and usage help

- **Docs site:** https://albisourous.github.io/prefixer/ for the guided
  tour; `docs/llms.txt` is the agent-readable index.
- **README:** install paths for Devin, Claude Code, Cursor, Codex, and
  any `.agents`-compatible host.
- **Health check:** `bash <skill>/scripts/doctor.sh` in your repo prints
  the state of the map, the hook, and the install stamp. Paste its
  output into any issue where something "does not work".

Please search existing issues before opening a new one.

## Bug reports

Open a [bug report](https://github.com/Albisourous/prefixer/issues/new/choose).
To help us reproduce it quickly, include:

- what you expected and what actually happened,
- the output of `bash scripts/doctor.sh` and `bash scripts/check_namespaces.sh`,
- the repo's rough shape (language, top-level dirs, file count),
- your OS, shell, and agent host (Devin, Claude Code, Cursor, ...).

## Feature requests and eval numbers

- Ideas: [feature request form](https://github.com/Albisourous/prefixer/issues/new/choose).
- Numbers: `bash scripts/eval_repo.sh <your-repo>` prints the
  bytes-saved table; real-world `pct_saved` results are the most useful
  data you can send back. See CONTRIBUTING.md.

## Security

Do not file public issues for vulnerabilities. See
[SECURITY.md](SECURITY.md).

# eval/agent: real agent-behavior eval

`eval/run.sh` measures **search-output bytes**: the same grep at repo
root vs inside a namespace. This harness measures the thing that number
is a proxy for: **what a real agent actually does** on a fixed task,
with and without the map.

## What it measures

For each task in `tasks.txt` the harness runs a fresh agent session in a
synthetic repo (built by `build_fixture.sh`) under two arms:

- **baseline**: no `.prefixer/`; the agent searches however it wants.
- **mapped**: `.prefixer/namespaces.md` scaffolded and injected at
  session start; `search.sh`/`suggest_map.sh` installed under the
  agent's skills dir.

Every tool call is logged through a `PostToolUse` hook (same hook shape
for Devin and Claude Code). `summarize.py` reports per task and per arm:

- tool calls, searches, search-output bytes, total tool-output bytes
- **first-try scoped**: was the agent's first pattern search confined
  to the directory that holds the answer?
- **correct answer**: did the final output name the expected file and
  symbol?
- **self-init map**: did a baseline run scaffold its own map? (That's
  fair play: it pays the tool-call cost either way.)

## Run it

```sh
devin auth login        # or: claude login
bash eval/agent/run.sh --reps 3
```

Writes `eval/agent/RESULTS.md`. `--adapter devin|claude` forces an
adapter, `--dry-run` builds the fixture and hooks without calling an
agent (useful for verifying wiring).

## Honest reading

- Agents are stochastic. One run proves nothing; use `--reps` and report
  the aggregate, not a lucky run.
- The fixture is synthetic. It exists to make answers knowable and
  decoys controlled, not to mimic a real codebase. The public-repo
  corpus in `eval/run.sh` is the external-validity arm.
- The metric is tool traffic, not model quality. A baseline run that
  reads more files isn't "dumber"; it just paid more tokens to arrive.
- Prompts are identical across arms. If you change a task prompt, change
  it for both.

## Files

- `build_fixture.sh`: deterministic ~100-file repo; one unique answer
  symbol per task, decoy vocabulary spread across sibling dirs, plus a
  `dist/` dupe dir so root greps pay for generated files too.
- `tasks.txt`: `id | prompt | expected_path | expected_symbol`
- `hook_posttool.sh`: hook stdin → one JSONL line per tool call
- `adapters/{devin,claude}.sh`: binary detection, hooks wiring, and the
  headless invocation. Add another harness by writing an adapter with
  `agent_detect`, `agent_ready`, `agent_hooks`, `agent_run`.
- `adapters/devin_acp.sh` + `acp_run.py`: fallback adapter driving
  `devin acp`. Authenticates with the app-stored API key, logs tool
  calls from `session/update` notifications (workspace hooks don't
  execute under ACP), and injects the map as a prompt prefix for the
  mapped arm. Picked automatically when `devin -p` can't authenticate
  (`devin models list` fails even after `devin auth login`).
- `run.sh`: orchestrator; `summarize.py`: log → RESULTS.md

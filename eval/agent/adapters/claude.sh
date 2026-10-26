#!/usr/bin/env bash
# adapters/claude.sh — agent adapter for Claude Code.
# Sourced by run.sh; must define: agent_detect, agent_ready,
# agent_hooks FIXTURE LOG MAPPED, agent_run FIXTURE PROMPT OUTFILE.

agent_detect() { command -v claude 2>/dev/null; }

agent_ready() { agent_detect >/dev/null 2>&1 && claude --version >/dev/null 2>&1; }

# write .claude/settings.json — same hook envelope shape as devin
agent_hooks() { # FIXTURE LOG MAPPED
  local fx="$1" log="$2" mapped="$3" ss=""
  [ "$mapped" = 1 ] && ss='"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"cd '"$fx"' && bash '"$PFX_ROOT"'/scripts/session_start.sh --json"}]}],'
  mkdir -p "$fx/.claude"
  printf '{"hooks":{%s"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"bash %s/eval/agent/hook_posttool.sh %s"}]}]}}\n' \
    "$ss" "$PFX_ROOT" "$log" > "$fx/.claude/settings.json"
}

agent_run() { # FIXTURE PROMPT OUTFILE
  local fx="$1" prompt="$2" out="$3"
  # read/search tools + bash (the agent needs bash to run search.sh);
  # the fixture is synthetic and disposable
  (cd "$fx" && claude -p "$prompt" --allowedTools "Read,Grep,Glob,LS,Bash" >"$out" 2>&1)
}

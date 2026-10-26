#!/usr/bin/env bash
# adapters/devin.sh — agent adapter for the Devin CLI.
# Sourced by run.sh; must define: agent_detect, agent_ready,
# agent_hooks FIXTURE LOG MAPPED, agent_run FIXTURE PROMPT OUTFILE.

DEVIN_APP_BIN="/Applications/Devin.app/Contents/Resources/app/extensions/windsurf/devin/bin/devin"

agent_detect() {
  if [ -n "${DEVIN_BIN:-}" ] && [ -x "$DEVIN_BIN" ]; then echo "$DEVIN_BIN"; return 0; fi
  if command -v devin >/dev/null 2>&1; then command -v devin; return 0; fi
  [ -x "$DEVIN_APP_BIN" ] && { echo "$DEVIN_APP_BIN"; return 0; }
  return 1
}

agent_ready() {
  local bin out
  bin="$(agent_detect)" || return 1
  out="$("$bin" auth status 2>&1 || true)"
  case "$out" in *"Not logged in"*) return 1 ;; esac
  return 0
}

# write .devin/hooks.v1.json: PostToolUse logging always, SessionStart
# map injection only when MAPPED=1 — the only difference between arms.
# devin's file IS the hooks object (integrations/hooks.devin.json),
# unlike claude's settings.json which nests it under "hooks"
agent_hooks() { # FIXTURE LOG MAPPED
  local fx="$1" log="$2" mapped="$3" ss=""
  [ "$mapped" = 1 ] && ss='"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"cd '"$fx"' && bash '"$PFX_ROOT"'/scripts/session_start.sh --json"}]}],'
  mkdir -p "$fx/.devin"
  printf '{%s"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"bash %s/eval/agent/hook_posttool.sh %s"}]}]}\n' \
    "$ss" "$PFX_ROOT" "$log" > "$fx/.devin/hooks.v1.json"
}

agent_run() { # FIXTURE PROMPT OUTFILE
  local fx="$1" prompt="$2" out="$3" bin
  bin="$(agent_detect)" || return 1
  # print mode: read-only tasks get auto-approved; trust prompt skipped —
  # the fixture is throwaway so workspace trust is irrelevant
  (cd "$fx" && "$bin" -p --respect-workspace-trust false --permission-mode auto -- "$prompt" >"$out" 2>&1)
}

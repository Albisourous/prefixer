#!/usr/bin/env bash
# adapters/devin_acp.sh — Devin CLI via the ACP server (`devin acp`).
#
# The standalone `devin -p` path wants Devin-account credentials; the
# ACP server accepts the Windsurf API key the desktop app already stores.
# Hooks.v1.json is NOT executed under ACP, so this adapter differs from
# adapters/devin.sh in two ways: the tool log is written by acp_run.py
# from session/update notifications (same JSONL shape hook_posttool.sh
# emits), and the mapped arm injects session_start.sh's output as a
# prompt prefix instead of a SessionStart hook.
#
# Contract (sourced by run.sh): agent_detect, agent_ready,
# agent_hooks FIXTURE LOG MAPPED, agent_run FIXTURE PROMPT OUTFILE.

DEVIN_APP_BIN="/Applications/Devin.app/Contents/Resources/app/extensions/windsurf/devin/bin/devin"

agent_detect() {
  if [ -n "${DEVIN_BIN:-}" ] && [ -x "$DEVIN_BIN" ]; then echo "$DEVIN_BIN"; return 0; fi
  if command -v devin >/dev/null 2>&1; then command -v devin; return 0; fi
  [ -x "$DEVIN_APP_BIN" ] && { echo "$DEVIN_APP_BIN"; return 0; }
  return 1
}

agent_ready() {
  local bin
  bin="$(agent_detect)" || return 1
  # ACP auths with the app-stored API key (or WINDSURF_API_KEY env).
  [ -n "${WINDSURF_API_KEY:-}${DEVIN_API_KEY:-}" ] && return 0
  grep -q 'windsurf_api_key' ~/.local/share/devin/credentials.toml 2>/dev/null
}

# no hook file needed under ACP — stash arm state for agent_run
agent_hooks() { # FIXTURE LOG MAPPED
  export PFX_ACP_FIXTURE="$1" PFX_ACP_LOG="$2" PFX_ACP_MAPPED="$3"
}

agent_run() { # FIXTURE PROMPT OUTFILE
  local fx="$1" prompt="$2" out="$3" pfx=""
  if [ "${PFX_ACP_MAPPED:-0}" = 1 ]; then
    pfx="$(cd "$fx" && bash "$PFX_ROOT/scripts/session_start.sh" 2>/dev/null || true)"
  fi
  python3 "$PFX_ROOT/eval/agent/acp_run.py" --cwd "$fx" \
    --log "$PFX_ACP_LOG" --out "$out" --prefix "$pfx" -- "$prompt"
}

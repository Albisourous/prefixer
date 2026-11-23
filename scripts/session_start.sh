#!/usr/bin/env bash
# session_start.sh — emit the namespace map at session start so every
# search begins scoped with no discipline required.
#
#   session_start.sh          print the map + a one-line health verdict
#   session_start.sh --json   wrap it in the hookSpecificOutput envelope
#                             Claude Code and Devin read for injected
#                             context (SessionStart additionalContext)
#
# Wire it with install_hook.sh (writes .devin/hooks.v1.json or
# .claude/settings.json for you) or paste the command from
# integrations/ into your harness config. In a repo with no map it exits
# 0 silently — a hook must never break session start.
# usage: session_start.sh [--json] [--repo DIR]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

json="" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1 ;;
    --repo) repo="${2:?--repo needs a dir}"; shift ;;
    --repo=*) repo="${1#--repo=}" ;;
    *) shift; continue ;;
  esac
  shift
done

root="$(map_root "${repo:-$PWD}")"
map="$root/.prefixer/namespaces.md"
[ -f "$map" ] || exit 0

body="$(cat "$map")"

# the map self-reports health at the one moment every session reads it —
# a stale map is loud where silence would quietly unscope every search
health=""
if [ -x "$here/check_namespaces.sh" ] || [ -f "$here/check_namespaces.sh" ]; then
  verdict="$(cd "$root" && bash "$here/check_namespaces.sh" . 2>&1 | tail -1 || true)"
  case "$verdict" in
    *"0 failures, 0 warnings"*) health="prefixer: map is healthy, search inside these scopes first and say which tag you used, widen one level on a miss." ;;
    *) health="prefixer: map needs attention ($verdict); run check_namespaces.sh, scopes below may be stale." ;;
  esac
fi

# logged savings recap: the meter proves scoped search pays, right at
# the moment the agent decides whether to search inside the map first
recap=""
log="$root/.prefixer/metrics.jsonl"
if [ -f "$log" ]; then
  recap="$(awk '/"task":"scoped-search"/ { n++; if ($0 ~ /"first_try_hit":true/) h++ }
    END { if (n) printf "prefixer: %d scoped searches logged, %d%% hit first try.", n, h * 100 / n }' "$log")"
fi

text="$body
$health"
[ -n "$recap" ] && text="$text
$recap"

if [ -n "$json" ]; then
  esc="$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
else
  printf '%s\n' "$text"
fi
exit 0

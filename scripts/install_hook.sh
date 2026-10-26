#!/usr/bin/env bash
# install_hook.sh — wire session-start map injection into a harness's
# hooks config so the map lands in context with zero discipline.
#
#   install_hook.sh                 auto-detect: .devin/, .claude/ markers
#   install_hook.sh devin           write .devin/hooks.v1.json
#   install_hook.sh claude          merge into .claude/settings.json
#   install_hook.sh all             every detected platform
#
# The hook command points at this script's own session_start.sh — a
# repo-relative path when the skill is project-installed, absolute when
# it's global. Merging an existing config needs python3; without it the
# script prints the JSON to paste instead of clobbering your settings.
# usage: install_hook.sh [devin|claude|all] [repo-root]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

platform=auto
case "${1:-}" in
  devin|claude|all) platform="$1"; shift ;;
  auto) shift ;;
esac
case "${1:-}" in
  -*) echo "usage: install_hook.sh [devin|claude|all] [repo-root]" >&2; exit 2 ;;
esac
# map_root can return nothing (bad dir arg) or '/' (nothing repo-like up
# the tree): on bash 3.2 `cd ""` stays put and would write the hooks
# config into whatever cwd the caller happens to be in
root="$(map_root "${1:-$PWD}")"
if [ -z "$root" ] || [ "$root" = / ]; then
  echo "no repo root from '${1:-$PWD}'; run inside a repo or pass a path" >&2
  exit 1
fi
cd "$root" || exit 1

# script path the hook will call — repo-relative when possible so a
# project install travels with the repo
skilldir="$(cd "$here/.." && pwd)"
case "$skilldir" in
  "$root"/*) script="${skilldir#"$root"/}/scripts/session_start.sh" ;;
  *) script="$skilldir/scripts/session_start.sh" ;;
esac
cmd="bash $script --json 2>/dev/null || true"

targets=""
if [ "$platform" = auto ] || [ "$platform" = all ]; then
  if [ -d .devin ] || [ "$platform" = all ]; then targets="$targets devin"; fi
  if [ -d .claude ] || [ "$platform" = all ]; then targets="$targets claude"; fi
  # nothing marked: devin's file is the standalone format — start there
  [ -n "$targets" ] || targets=" devin"
else
  targets=" $platform"
fi

hook() { # event-entry JSON on one line
  printf '{"matcher":"","hooks":[{"type":"command","command":%s}]}' \
    "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
}

for p in $targets; do
  case "$p" in
    devin) f=".devin/hooks.v1.json"; wrap=whole ;;
    claude) f=".claude/settings.json"; wrap=nested ;;
  esac
  mkdir -p "$(dirname "$f")"

  if [ -f "$f" ] && grep -q 'session_start.sh' "$f"; then
    echo "$f: hook already wired"; continue
  fi

  if [ ! -f "$f" ]; then
    entry="$(hook "$cmd")"
    if [ "$wrap" = whole ]; then
      printf '{\n  "SessionStart": [\n    %s\n  ]\n}\n' "$entry" > "$f"
    else
      printf '{\n  "hooks": {\n    "SessionStart": [\n      %s\n    ]\n  }\n}\n' "$entry" > "$f"
    fi
    echo "wrote $f"; continue
  fi

  # existing config — merge needs a JSON tool; never clobber by hand
  if command -v python3 >/dev/null 2>&1; then
    F="$f" CMD="$cmd" WRAP="$wrap" python3 - <<'PY'
import json, os
f, cmd, wrap = os.environ["F"], os.environ["CMD"], os.environ["WRAP"]
try:
    cfg = json.load(open(f))
except json.JSONDecodeError:
    raise SystemExit(f"{f}: not JSON, add the hook by hand")
entry = {"matcher": "", "hooks": [{"type": "command", "command": cmd}]}
hooks = cfg if wrap == "whole" else cfg.setdefault("hooks", {})
hooks.setdefault("SessionStart", []).append(entry)
json.dump(cfg, open(f, "w"), indent=2)
open(f, "a").write("\n")
print(f"merged SessionStart hook into {f}")
PY
  else
    echo "$f exists, add this under hooks.SessionStart yourself:" >&2
    hook "$cmd" >&2
  fi
done

echo "hook runs: $cmd"
echo "verify with /hooks in the session, or: bash $script --json"

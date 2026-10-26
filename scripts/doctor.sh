#!/usr/bin/env bash
# doctor.sh — health check for a repo's prefixer setup, in one command.
# Prints one ok/warn/FAIL line per check; exits nonzero when something
# needs fixing. Run it when "the map does not seem to work" and paste
# the output into issue reports.
#
#   doctor.sh            check the repo at cwd
#   doctor.sh DIR        check another repo
#   doctor.sh --quiet      warnings and failures only
# usage: doctor.sh [--quiet] [repo-root]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

quiet=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet|-q) quiet=1 ;;
    -*) echo "usage: doctor.sh [--quiet] [repo-root]" >&2; exit 2 ;;
    *) dir="$1" ;;
  esac
  shift
done

fails=0
ok()   { [ -n "$quiet" ] || printf 'ok   %s\n' "$1"; }
warn() { printf 'warn %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

version="$(sed -n 's/^  version: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$here/../SKILL.md" | head -1)"
ok "prefixer ${version:-?} (running from $here)"

root="$(map_root "${dir:-$PWD}")"
if [ -z "$root" ] || [ "$root" = / ]; then
  bad "no repo root from '${dir:-$PWD}'; run inside a repo or pass a path"
  exit 1
fi
ok "repo root: $root"
cd "$root" || exit 1

# --- the map itself ----------------------------------------------------
map=".prefixer/namespaces.md"
if [ ! -f "$map" ]; then
  bad "no $map; scaffold one: bash scripts/init_namespaces.sh"
else
  rows="$(scope_pairs "$map" | grep -c .)"
  ok "map present, $rows rows"
  if [ "$rows" -gt 12 ]; then
    warn "map has $rows rows; the guide is 5 to 12, merge or cut"
  fi
fi

# --- lint verdict --------------------------------------------------------
if [ -f "$map" ]; then
  verdict="$(bash "$here/check_namespaces.sh" . 2>&1 | tail -1)"
  if bash "$here/check_namespaces.sh" . >/dev/null 2>&1; then
    case "$verdict" in
      *"0 failures, 0 warnings"*) ok "lint: $verdict" ;;
      *) warn "lint: $verdict" ;;
    esac
  else
    bad "lint: $verdict"
  fi
fi

# --- session-start hook --------------------------------------------------
hooked=""
for f in .devin/hooks.v1.json .claude/settings.json; do
  [ -f "$f" ] && grep -q 'session_start.sh' "$f" && hooked="$hooked $f"
done
if [ -n "$hooked" ]; then
  ok "session-start hook wired:$hooked"
else
  warn "no session-start hook; agents must remember to read the map (fix: install_hook.sh)"
fi

# --- local telemetry stays local ----------------------------------------
if [ -f .prefixer/metrics.jsonl ]; then
  n="$(grep -c . .prefixer/metrics.jsonl 2>/dev/null || echo 0)"
  if [ -f .prefixer/.gitignore ] && grep -q 'metrics.jsonl' .prefixer/.gitignore; then
    ok "metrics log: $n lines, gitignored"
  else
    warn "metrics log: $n lines, not gitignored (scaffold writes .prefixer/.gitignore)"
  fi
else
  ok "no metrics log yet; tasks append to .prefixer/metrics.jsonl"
fi

# --- stale installs ------------------------------------------------------
stamp="$version"
for d in "$root"/.devin/skills/prefixer "$root"/.claude/skills/prefixer \
         "$root"/.windsurf/skills/prefixer "$root"/.agents/skills/prefixer \
         "$HOME"/.claude/skills/prefixer "$HOME"/.agents/skills/prefixer \
         "$HOME"/.config/devin/skills/prefixer \
         "$HOME"/.codeium/windsurf/skills/prefixer; do
  [ -d "$d" ] || continue
  [ "$(cd "$d" 2>/dev/null && pwd -P)" = "$(cd "$here/.." && pwd -P)" ] && continue
  v="$(cat "$d/.prefixer_version" 2>/dev/null || echo '?')"
  if [ "$v" = "$stamp" ]; then
    ok "install at $d (v$v)"
  else
    warn "install at $d stamps v$v, this checkout is v$stamp; re-run install.sh"
  fi
done

if [ "$fails" -gt 0 ]; then
  printf 'doctor: %d problem(s) to fix\n' "$fails" >&2
  exit 1
fi
[ -z "$quiet" ] && echo "doctor: healthy"
exit 0

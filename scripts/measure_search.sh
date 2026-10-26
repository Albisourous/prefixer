#!/usr/bin/env bash
# Run a search command, count the hits, log one metrics line.
# The log lives beside the map: nearest .prefixer/ walking up, else the
# git toplevel, else the current directory — never a stray .prefixer in a
# subdirectory.
# usage: measure_search.sh [--baseline] [--hit|--miss] [--scope GLOB] <task-tag> -- <command...>
#   e.g. measure_search.sh find-expiry -- grep -rn "expire" src/auth
#        measure_search.sh --hit find-expiry --scope src/auth/** -- grep -rn "expire" src/auth
#        measure_search.sh --baseline orientation -- grep -rn "TODO" .
set -uo pipefail

baseline=false hit="" scope=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) baseline=true; shift ;;
    --hit) hit=true; shift ;;
    --miss) hit=false; shift ;;
    --scope) scope="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done

case "${1:-}" in
  --) tag="task"; shift ;;
  *) tag="${1:-task}"
     if [ "${2:-}" = "--" ]; then shift 2; else shift; fi ;;
esac
if [ "$#" -eq 0 ]; then
  echo "usage: measure_search.sh [--baseline] [--hit|--miss] [--scope GLOB] <task-tag> -- <command...>" >&2
  exit 2
fi

# capture failure honestly: a crashed probe is not a 0-hit search —
# swallowing it would pollute the baseline with phantom misses
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
out="$("$@" 2>"$errf")"; rc=$?
if [ "$rc" -ne 0 ]; then
  sed 's/^/probe stderr: /' "$errf" >&2
  echo "warn probe exited $rc; logging error:true, hits are unreliable" >&2
fi
hits="$(printf '%s' "$out" | grep -c . || true)"
bytes="$(printf '%s' "$out" | wc -c | tr -d ' ')"
est=$(( bytes / 4 ))

# scope: the --scope value, else the command's path args, else root
if [ -z "$scope" ]; then
  for a in "$@"; do
    case "$a" in -*) continue ;; esac
    if [ "$a" = "." ] || [ "$a" = "./" ]; then continue; fi
    if [ -e "$a" ]; then scope="${scope:+$scope,}$a"; continue; fi
    # glob chars only count toward a scope when the arg is path-like —
    # a bare foo.* is a grep regex, not a file pattern (issue: regex
    # patterns were being logged as scopes)
    case "$a" in */*[*?]*|*[*?]*/*) scope="${scope:+$scope,}$a" ;; esac
  done
  [ -z "$scope" ] && scope="root"
fi

# anchor at the .prefixer/ beside the map, else git toplevel, else cwd
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"
root="$(map_root "$PWD")"

mkdir -p "$root/.prefixer"
grep -qx 'metrics.jsonl' "$root/.prefixer/.gitignore" 2>/dev/null ||
  echo 'metrics.jsonl' >> "$root/.prefixer/.gitignore"

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
extra=""
[ "$baseline" = true ] && extra=',"baseline":true'
[ -n "$hit" ] && extra="$extra,\"first_try_hit\":$hit"
[ "$rc" -ne 0 ] && extra="$extra,\"error\":true,\"exit\":$rc"
printf '{"ts":"%s","task":"%s","searches":1,"scope":"%s","hits":%s,"est_tokens":%s%s}\n' \
  "$(date -u +%FT%TZ)" "$(esc "$tag")" "$(esc "$scope")" "$hits" "$est" "$extra" \
  >> "$root/.prefixer/metrics.jsonl"

printf '%s\n' "$out"
echo "logged: $hits hits in $scope (~${est} tokens) -> $root/.prefixer/metrics.jsonl" >&2

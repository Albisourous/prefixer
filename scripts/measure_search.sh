#!/usr/bin/env bash
# Run a search command, count the hits, log one metrics line.
# usage: measure_search.sh <task-tag> -- <command...>
#   e.g. measure_search.sh find-expiry -- grep -rn "expire" src/auth
set -uo pipefail

tag="${1:-task}"
if [ "${2:-}" = "--" ]; then shift 2; else shift; fi
if [ "$#" -eq 0 ]; then
  echo "usage: measure_search.sh <task-tag> -- <command...>" >&2
  exit 2
fi

out="$("$@" 2>/dev/null || true)"
hits="$(printf '%s' "$out" | grep -c . || true)"
bytes="$(printf '%s' "$out" | wc -c | tr -d ' ')"
est=$(( bytes / 4 ))

mkdir -p .prefixer
safe_tag="$(printf '%s' "$tag" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"ts":"%s","task":"%s","searches":1,"hits":%s,"est_tokens":%s}\n' \
  "$(date +%F)" "$safe_tag" "$hits" "$est" >> .prefixer/metrics.jsonl

printf '%s\n' "$out"
echo "logged: $hits hits (~${est} tokens) -> .prefixer/metrics.jsonl" >&2

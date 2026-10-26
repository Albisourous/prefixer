#!/usr/bin/env bash
# Measure the token delta of one scoped search vs a repo-root search —
# the actual thing prefixer exists to save.
# usage: eval_scope.sh [repo-root] <grep-pattern> <prefix|tag> [scope-globs] [--log]
# <prefix> may be a composed tag (payments:checkout) for nested rows;
# passing scope-globs skips the map lookup — the prefix is a label only.
# Prints a JSON line; --log also appends it to .prefixer/metrics.jsonl.
set -uo pipefail

root="${1:-.}"
pat="${2:?usage: eval_scope.sh [repo] <pattern> <prefix> [scope] [--log]}"
ns="${3:?usage: eval_scope.sh [repo] <pattern> <prefix> [scope] [--log]}"
log="" scope=""
for a in "${@:4}"; do
  case "$a" in --log) log="--log" ;; *) scope="$a" ;; esac
done
map="$root/.prefixer/namespaces.md"
here="$(cd "$(dirname "$0")" && pwd)"
# scope grammar, exclusion lists: scripts/lib_scope.sh (single copy)
. "$here/lib_scope.sh"

if [ -z "$scope" ]; then
  [ -f "$map" ] || { echo "no map at $map" >&2; exit 1; }
  if [[ "$ns" == *:* ]]; then
    scope="$(tag_scope "$ns" "$map")"
  else
    # exact-match the "name:" cell — no regex, so dots and dashes are safe
    scope="$(leaf_scope "$ns" "$map")"
  fi
  [ -n "$scope" ] || { echo "no prefix '${ns}:' in $map" >&2; exit 1; }
fi

# metachars get a clear refusal even though nothing below evals — a scope
# full of shell syntax is a mistake, not a glob
case "$scope" in
  *'$('*|*\`*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*$'\n'*)
    echo "unsafe scope: $scope" >&2; exit 1 ;;
esac

cd "$root" || exit 1
rb="$(mktemp)"; sb="$(mktemp)"; trap 'rm -f "$rb" "$sb"' EXIT

# baseline — what an unscoped-but-sane agent pays: repo-wide grep minus
# the generated dirs every map excludes anyway (a grep through
# node_modules measures a strawman, not the counterfactual). Case-
# sensitive: probes are the namespaces' own names, not fuzzy queries.
excl="$(grep_excludes)"
grep -rnI $excl -- "$pat" . > "$rb" 2>/dev/null || true

# scoped — expand the namespace's globs to concrete paths, grep only those
: > "$sb"
plist="$(mktemp)"; trap 'rm -f "$rb" "$sb" "$plist"' EXIT
scope_files "$scope" > "$plist"
while IFS= read -r f; do
  grep -nI -- "$pat" "$f" 2>/dev/null | sed "s|^|$f:|" >> "$sb"
done < "$plist"

count() { # file → hits, bytes
  local f="$1"
  h="$(grep -c . "$f" 2>/dev/null || true)"; b="$(wc -c < "$f" | tr -d ' ')"
  printf '%s %s' "${h:-0}" "$b"
}
read -r rhits rbytes <<< "$(count "$rb")"
read -r shits sbytes <<< "$(count "$sb")"
saved=$((rbytes - sbytes))
[ "$rbytes" -gt 0 ] && pct=$((saved * 100 / rbytes)) || pct=0
toks=$((saved / 4))
ts="$(date -u +%FT%TZ)"
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
line="{\"ts\":\"$ts\",\"task\":\"eval-scope\",\"ns\":\"$(jesc "$ns")\",\"pattern\":\"$(jesc "$pat")\",\"root_hits\":$rhits,\"root_bytes\":$rbytes,\"ns_hits\":$shits,\"ns_bytes\":$sbytes,\"bytes_saved\":$saved,\"pct_saved\":$pct,\"est_tokens_saved\":$toks}"
printf '%s\n' "$line"
[ "$log" = "--log" ] && printf '%s\n' "$line" >> .prefixer/metrics.jsonl
exit 0

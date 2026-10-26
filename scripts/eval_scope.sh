#!/usr/bin/env bash
# Measure the token delta of one scoped search vs a repo-root search —
# the actual thing prefixer exists to save.
# usage: eval_scope.sh [repo-root] <grep-pattern> <prefix> [--log]
# Prints a JSON line; --log also appends it to .prefixer/metrics.jsonl.
set -uo pipefail

root="${1:-.}"
pat="${2:?usage: eval_scope.sh [repo] <pattern> <prefix> [--log]}"
ns="${3:?usage: eval_scope.sh [repo] <pattern> <prefix> [--log]}"
log="${4:-}"
map="$root/.prefixer/namespaces.md"
[ -f "$map" ] || { echo "no map at $map" >&2; exit 1; }

row="$(grep -E "^\| *${ns}: *\|" "$map" | head -1)"
[ -n "$row" ] || { echo "no prefix '${ns}:' in $map" >&2; exit 1; }
scope="$(printf '%s' "$row" | cut -d'|' -f3 | sed 's/^ *//; s/ *$//')"

cd "$root" || exit 1
rb="$(mktemp)"; sb="$(mktemp)"; trap 'rm -f "$rb" "$sb"' EXIT

# baseline — what an unscoped agent pays: repo-wide grep, .git excluded
grep -rniI "$pat" . --exclude-dir=.git > "$rb" 2>/dev/null || true

# scoped — expand the namespace's globs to concrete paths, grep only those
: > "$sb"
paths=""
# eval expands {a,b} brace globs and splits commas outside braces
toks="$(eval "printf '%s\n' $scope" 2>/dev/null || printf '%s\n' "$scope")"
while IFS= read -r tok; do
  tok="${tok%,}"
  [ -z "$tok" ] && continue
  case "$tok" in */**) tok="${tok%/**}" ;; esac
  if printf '%s' "$tok" | grep -q '[*?\[]'; then
    for f in $(find . -path "./$tok" 2>/dev/null | head -200); do
      paths="$paths $f"
    done
  elif [ -e "$tok" ]; then
    paths="$paths $tok"
  fi
done <<< "$toks"
# normalize to a deduped file list — overlapping globs and dir+file pairs
# would otherwise grep the same file twice and inflate hits
plist="$(mktemp)"; trap 'rm -f "$rb" "$sb" "$plist"' EXIT
for p in $paths; do
  if [ -d "$p" ]; then
    find "$p" -type f -not -name '.*'
  else
    printf '%s\n' "$p"
  fi
done | sort -u > "$plist"
while IFS= read -r f; do
  grep -niI "$pat" "$f" 2>/dev/null | sed "s|^|$f:|" >> "$sb"
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
ts="$(date +%Y-%m-%d)"
line="{\"ts\":\"$ts\",\"task\":\"eval-scope\",\"ns\":\"$ns\",\"pattern\":\"$pat\",\"root_hits\":$rhits,\"root_bytes\":$rbytes,\"ns_hits\":$shits,\"ns_bytes\":$sbytes,\"bytes_saved\":$saved,\"pct_saved\":$pct,\"est_tokens_saved\":$toks}"
printf '%s\n' "$line"
[ "$log" = "--log" ] && printf '%s\n' "$line" >> .prefixer/metrics.jsonl
exit 0

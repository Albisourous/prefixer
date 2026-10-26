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

# rebuild ancestor tags from indentation — the same parent:child chain
# check_namespaces.sh validates
tag_scope() { # want-tag, map → scope
  awk -F'|' -v want="$1" '
    /^[[:space:]]*\|/ {
      pf=$2; sc=$3; name=pf
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); sub(/:[[:space:]]*$/, "", name)
      if (name == "" || name == "prefix" || name ~ /^-/) next
      ind = pf; sub(/[^ ].*/, "", ind); lvl = length(ind)
      for (i in t) if (i >= lvl) delete t[i]
      par = ""
      for (i = lvl - 1; i >= 0; i--) if (i in t) { par = t[i]; break }
      tag = (par == "" ? name : par ":" name); t[lvl] = tag
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sc)
      if (tag == want) { print sc; exit }
    }' "$2"
}

if [ -z "$scope" ]; then
  [ -f "$map" ] || { echo "no map at $map" >&2; exit 1; }
  if [[ "$ns" == *:* ]]; then
    scope="$(tag_scope "$ns" "$map")"
  else
    # exact-match the "name:" cell — no regex, so dots and dashes are safe
    scope="$(awk -F'|' -v n="$ns" '
      /^[[:space:]]*\|/ {
        pf = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", pf)
        if (pf == n ":") { sc = $3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sc); print sc; exit }
      }' "$map")"
  fi
  [ -n "$scope" ] || { echo "no prefix '${ns}:' in $map" >&2; exit 1; }
fi

# the scope text is eval'd for brace expansion below — refuse anything
# that is not plain glob syntax
case "$scope" in
  *'$'*|*\`*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*'('*|*')'*|*"'"*|*'"'*|*$'\n'*)
    echo "unsafe scope: $scope" >&2; exit 1 ;;
esac

cd "$root" || exit 1
rb="$(mktemp)"; sb="$(mktemp)"; trap 'rm -f "$rb" "$sb"' EXIT

# baseline — what an unscoped agent pays: repo-wide grep, .git excluded
grep -rniI --exclude-dir=.git -- "$pat" . > "$rb" 2>/dev/null || true

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
  grep -niI -- "$pat" "$f" 2>/dev/null | sed "s|^|$f:|" >> "$sb"
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

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
ns="${ns%:}" # the documented spelling ends in ':' (auth:sso:)
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
    # a bare leaf may sit under several parents — SPEC requires
    # reporting ambiguity, not first-matching (same rule search.sh runs)
    matches="$(scope_pairs "$map" | awk -F'\t' -v n="$ns" \
      '$2 == n { print $1 "\t" $3 }')"
    if [ "$(printf '%s' "$matches" | grep -c .)" -gt 1 ]; then
      echo "'${ns}:' is ambiguous; qualify it:" >&2
      printf '%s' "$matches" | awk -F'\t' '{ printf "  %s: -> %s\n", $1, $2 }' >&2
      exit 1
    fi
    scope="$(printf '%s' "$matches" | cut -f2)"
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

# baseline — what an unscoped-but-sane agent pays on a repo without
# prefixer: a repo-wide grep minus generated dirs and .prefixer itself
# (the map and metrics log would self-hit their own names and patterns).
# Case-sensitive: probes are the namespaces' own names, not fuzzy queries.
excl="$(grep_excludes)"
grep -rnI $excl -- "$pat" . > "$rb" 2>/dev/null || true

# scoped — expand the namespace's globs to concrete paths, grep only those
: > "$sb"
plist="$(mktemp)"; trap 'rm -f "$rb" "$sb" "$plist"' EXIT
scope_files "$scope" > "$plist"
# a row whose every file lives inside dirs the baseline grep skips is
# comparing two different universes — flag it instead of emitting a
# meaningless (often wildly negative) pct_saved
bex=0 have=0 allx=1
path_excluded() { # path → 0 if some component sits on the skip list
  local rest="$1"
  while :; do
    skipped_gen "${rest%%/*}" && return 0
    case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
  done
  return 1
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  have=1
  path_excluded "$f" || { allx=0; break; }
done < "$plist"
# dir/** scopes reach no files at all: scope_files prunes generated dirs
# before listing, so the excluded check above sees an empty list. Walk
# the raw tokens instead — a literal dir that exists but prunes is the
# same out-of-baseline target
if [ "$have" -eq 0 ]; then
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    case "$tok" in *'/**') tok="${tok%\*\*}" ;; esac
    case "$tok" in *'*'*|*'?'*) continue ;; esac # globs: undecidable here
    [ -e "$tok" ] || continue
    have=1
    path_excluded "$tok" || { allx=0; break; }
  done <<< "$(expand_scope "$scope")"
fi
[ "$have" -eq 1 ] && [ "$allx" -eq 1 ] && bex=1
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
pctj="$pct" bexj=""
[ "$bex" -eq 1 ] && { pctj=null; bexj=',"baseline_excluded":true'; }
line="{\"ts\":\"$ts\",\"task\":\"eval-scope\",\"ns\":\"$(jesc "$ns")\",\"pattern\":\"$(jesc "$pat")\",\"root_hits\":$rhits,\"root_bytes\":$rbytes,\"ns_hits\":$shits,\"ns_bytes\":$sbytes,\"bytes_saved\":$saved,\"pct_saved\":$pctj$bexj,\"est_tokens_saved\":$toks}"
printf '%s\n' "$line"
if [ "$log" = "--log" ]; then
  # explicit-scope runs can land in a repo with no .prefixer yet — the
  # append must not die on a missing dir
  mkdir -p .prefixer
  printf '%s\n' "$line" >> .prefixer/metrics.jsonl
fi
exit 0

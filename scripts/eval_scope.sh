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

# scope tokens without eval: expand {a,b} arm-wise, then split commas —
# spaces inside names survive and nothing ever runs as shell
expand_scope() {
  local s="$1" pre mid post arm
  case "$s" in
    *'{'*)
      pre="${s%%\{*}"; post="${s#*\}}"
      mid="${s#*\{}"; mid="${mid%%\}*}"
      local IFS=','
      for arm in $mid; do
        arm="$(printf '%s' "$arm" | sed 's/^ *//; s/ *$//')"
        expand_scope "$pre$arm$post"
      done ;;
    *) printf '%s\n' "$s" | tr ',' '\n' | sed 's/^ *//; s/ *$//' ;;
  esac
}

# glob → anchored regex with real shell-glob semantics: * stays inside
# its dir level, ** crosses, ? is one non-/ char — find -path gets this
# wrong, its * matches slashes too. scopes are repo-relative and
# root-anchored: *.md is root files only, leading / means the same
glob_re() {
  printf '%s' "$1" | sed -e 's|^/||' -e 's/[.+^$|()]/\\&/g' -e 's/\*\*/@@/g' \
    -e 's/\*/[^\/]*/g' -e 's/\?/[^\/]/g' \
    -e 's|@@/|(.*/)?|g' -e 's/@@/.*/g' -e 's/^/^/' -e 's/$/$/'
}

# real paths a glob token resolves to — dir or file, spaces preserved,
# no cap: truncating here undercounts ns_bytes and inflates pct_saved
match_scope() {
  find . | sed 's|^\./||' | grep -E "$(glob_re "$1")" 2>/dev/null
}

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
excl="--exclude-dir=*-out"
for d in .git node_modules vendor dist build target out __pycache__ \
         .next .cache venv .venv .idea .vscode coverage .turbo .output \
         .nuxt .svelte-kit storybook-static DerivedData Pods bin obj; do
  excl="$excl --exclude-dir=$d"
done
grep -rnI $excl -- "$pat" . > "$rb" 2>/dev/null || true

# scoped — expand the namespace's globs to concrete paths, grep only those
: > "$sb"
paths=""
while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  # only a literal trailing /** collapses to its dir — the glob pattern
  # */** would match any token containing / and shred src/*.ts or /*.md
  case "$tok" in *'/**') tok="${tok%\*\*}" ;; esac
  if printf '%s' "$tok" | grep -q '[*?\[]'; then
    while IFS= read -r f; do
      [ -n "$f" ] && paths="$paths$f
"
    done < <(match_scope "$tok")
  elif [ -e "$tok" ]; then
    paths="$paths$tok
"
  fi
done <<< "$(expand_scope "$scope")"
# normalize to a deduped file list — overlapping globs and dir+file pairs
# would otherwise grep the same file twice and inflate hits
plist="$(mktemp)"; trap 'rm -f "$rb" "$sb" "$plist"' EXIT
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ -d "$p" ]; then
    find "$p" -type f -not -name '.*'
  else
    printf '%s\n' "$p"
  fi
done <<< "$paths" | sort -u > "$plist"
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

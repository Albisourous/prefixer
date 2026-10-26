#!/usr/bin/env bash
# Lint .prefixer/namespaces.md — every row must resolve to real paths,
# tags must be unique, no draft rows, no generated dirs mapped.
# Exit 1 on any failure; warnings do not fail.
# usage: check_namespaces.sh [repo-root]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# scope grammar, exclusion lists: scripts/lib_scope.sh (single copy)
. "$here/lib_scope.sh"

root="${1:-.}"
# cd first: a relative $root would otherwise break every $map read below
cd "$root" 2>/dev/null || { echo "cannot cd $root" >&2; exit 1; }
map=".prefixer/namespaces.md"
[ -f "$map" ] || { echo "no map at $root/$map" >&2; exit 1; }
fails=0 warns=0 rows=0

fail() { echo "FAIL $1"; fails=$((fails+1)); }
warn() { echo "warn $1"; warns=$((warns+1)); }

grep -q '^repo:' "$map" || warn "no repo: header; add 'repo: <slug>' for multi-codebase uniqueness"

tag_seen="" recent=""
while IFS= read -r line; do
  # readers ignore leading whitespace on a row line — the same grammar
  # scope_pairs uses; a table nested in a list is still rows
  line="${line#"${line%%[![:space:]]*}"}"
  case "$line" in '|'*) ;; *) continue ;; esac
  pf="$(printf '%s' "$line" | cut -d'|' -f2)"
  scope="$(printf '%s' "$line" | cut -d'|' -f3 | sed 's/^ *//; s/ *$//')"
  cont="$(printf '%s' "$line" | cut -d'|' -f4 | sed 's/^ *//; s/ *$//')"
  # header/separator rows have empty or dashes-only prefix fields
  name="$(printf '%s' "$pf" | sed 's/^ *//; s/ *$//; s/:*$//')"
  case "$name" in ''|prefix|-*) continue ;; esac

  rows=$((rows+1))
  # whitespace, not just space: a tab-indented row nests the same way
  # scope_pairs and visualize.py read it
  indent="$(printf '%s' "$pf" | sed 's/[^[:space:]].*//')"
  lvl=${#indent}

  case "$name" in todo-*) fail "draft prefix: ${name}:" ;; esac
  case "$cont" in *TODO*|*undocumented*) fail "draft contains on ${name}: $cont" ;; esac

  # full tag = ancestor chain + name; rows arrive depth-first so the last
  # row at any shallower level is this row's parent
  pt="$(printf '%s' "$recent" | awk -F'\t' -v l="$lvl" '$1<l{t=$2} END{print t}')"
  tag="${pt:+$pt:}$name"
  case " $tag_seen " in
    *" $tag "*) fail "duplicate tag: $tag:" ;;
  esac
  tag_seen="$tag_seen $tag"
  recent="$recent$lvl	$tag
"

  # metachars get a clear fail even though nothing below evals — a scope
  # full of shell syntax is a mistake, not a glob
  case "$scope" in
    *'$('*|*\`*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*$'\n'*)
      fail "unsafe scope: ${tag}: → $scope"; continue ;;
  esac

  # brace lists expand arm-wise, commas split outside braces, spaces in
  # names survive — the same tokens a searching shell would see
  live=0 genflag=0
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    # any component on the shared generated-dir list flags the row —
    # one list (PREFIXER_SKIP) keeps lint, scaffold, and eval honest
    rest="$tok"
    while :; do
      skipped_gen "${rest%%/*}" && { genflag=1; break; }
      case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
    done
    resolve "$tok" && live=$((live+1))
  done <<< "$(expand_scope "$scope")"
  [ "$genflag" -eq 1 ] && fail "generated path mapped: ${tag}: never map vendored/generated"
  [ "$live" -eq 0 ] && fail "dead scope: ${tag}: → $scope"
done < "$map"

[ "$rows" -eq 0 ] && fail "map has no rows"

# coverage — dirs an agent might search that no row claims (warn only)
cover() { # dirname → 0 if a scope claims it, its parent, or lives inside it
  local d="$1" tok
  # read line-wise: a spaced scope token must stay one token
  while IFS= read -r tok; do
    case "$tok" in
      "$d"|"$d/"*) return 0 ;;
      # ${tok%\*\*} already ends in '/' — appending another made the
      # prefix 'src//' and no subdir ever matched
      *'/**') [ "${d#"${tok%\*\*}"}" != "$d" ] && return 0 ;;
    esac
  done <<< "$scopes_all"
  return 1
}
# coverage sees the same tokens the row lint resolved — braces expanded,
# commas split, metachar scopes dropped (they already FAILed above).
# built in-shell, not $(): bash 3.2 misparses quoted case patterns there
scopes_all=""
while IFS= read -r raw; do
  case "$raw" in ''|scope|-*) continue ;; esac
  case "$raw" in *'$('*|*\`*|*';'*|*[|]*|*'&'*|*'<'*|*'>'*) continue ;; esac
  scopes_all="$scopes_all$(expand_scope "$raw")
"
done <<EOF
$(awk -F'|' '/^[[:space:]]*\|/ { print $3 }' "$map" | sed 's/^[[:blank:]]*//; s/[[:blank:]]*$//')
EOF
for d in */ .[!.]*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  skipped_gen "$name" && continue
  [ -z "$(find "$d" -type f -not -name '.*' -print -quit 2>/dev/null)" ] && continue
  cover "$name" || warn "uncovered top dir: $name/"
done
repo_slug="$(grep -m1 '^repo:' "$map" | sed 's/^repo: *//')"
for parent in src lib app packages apps services modules libs crates cmd \
              internal pkg plugins themes components tools server $repo_slug; do
  [ -d "$parent" ] || continue
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    child="$(basename "$d")"
    skipped_gen "$child" && continue
    cover "$parent/$child" || warn "uncovered dir: $parent/$child/"
  done
done

# root files are a search intent too (config, manifests, docs) — a scope
# covers one by naming it or by a glob like *.md
ufiles=""
for f in *; do
  [ -f "$f" ] || continue
  hit=0
  # same glob_re match as match_scope — case-glob [ would read a char
  # class where the scope grammar means a literal bracket
  while IFS= read -r tok; do
    printf '%s\n' "$f" | grep -qE "$(glob_re "$tok")" && { hit=1; break; }
  done <<< "$scopes_all"
  [ "$hit" -eq 0 ] && ufiles="$ufiles $f"
done
[ -n "$ufiles" ] && warn "uncovered root files:$ufiles"

echo "checked $rows namespaces: $fails failures, $warns warnings"
[ "$fails" -gt 0 ] && exit 1
exit 0

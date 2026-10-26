#!/usr/bin/env bash
# Lint .prefixer/namespaces.md — every row must resolve to real paths,
# tags must be unique, no draft rows, no generated dirs mapped.
# Exit 1 on any failure; warnings do not fail.
# usage: check_namespaces.sh [repo-root]
set -uo pipefail

root="${1:-.}"
map="$root/.prefixer/namespaces.md"
[ -f "$map" ] || { echo "no map at $map" >&2; exit 1; }

cd "$root" || exit 1
fails=0 warns=0 rows=0
skip="node_modules vendor dist build target out .git .prefixer __pycache__ .next .cache venv .venv .idea .vscode coverage .turbo .output .nuxt .svelte-kit storybook-static DerivedData Pods bin obj"

fail() { echo "FAIL $1"; fails=$((fails+1)); }
warn() { echo "warn $1"; warns=$((warns+1)); }

skipped_gen() { case " $skip " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

# does a scope glob resolve to at least one real path under .?
# find -path treats * as matching slashes too — good enough for existence
resolve() { find . -path "./$1" -print -quit 2>/dev/null | grep -q .; }

grep -q '^repo:' "$map" || warn "no repo: header — add 'repo: <slug>' for multi-codebase uniqueness"

tag_seen="" recent=""
while IFS= read -r line; do
  case "$line" in '|'*) ;; *) continue ;; esac
  pf="$(printf '%s' "$line" | cut -d'|' -f2)"
  scope="$(printf '%s' "$line" | cut -d'|' -f3 | sed 's/^ *//; s/ *$//')"
  cont="$(printf '%s' "$line" | cut -d'|' -f4 | sed 's/^ *//; s/ *$//')"
  # header/separator rows have empty or dashes-only prefix fields
  name="$(printf '%s' "$pf" | sed 's/^ *//; s/ *$//; s/:*$//')"
  case "$name" in ''|prefix|-*) continue ;; esac

  rows=$((rows+1))
  indent="$(printf '%s' "$pf" | sed 's/[^ ].*//')"
  lvl=${#indent}

  case "$name" in todo-*) fail "draft prefix: ${name}:" ;; esac
  case "$cont" in *TODO*|*undocumented*) fail "draft contains on ${name}: — $cont" ;; esac

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

  # eval expands brace lists {a,b} the way the searching shell does, and
  # splits commas outside braces — the naive split shreds {A,B,C} rows
  live=0 genflag=0
  toks="$(eval "printf '%s\n' $scope" 2>/dev/null || printf '%s\n' "$scope")"
  while IFS= read -r tok; do
    tok="${tok%,}"
    [ -z "$tok" ] && continue
    case "$tok" in
      node_modules/*|node_modules|vendor/*|dist/*|build/*|target/*|coverage/*|*-out/*|*-out)
        genflag=1 ;;
    esac
    resolve "$tok" && live=$((live+1))
  done <<< "$toks"
  [ "$genflag" -eq 1 ] && warn "generated path mapped: ${tag}:"
  [ "$live" -eq 0 ] && fail "dead scope: ${tag}: → $scope"
done < "$map"

[ "$rows" -eq 0 ] && fail "map has no rows"

# coverage — dirs an agent might search that no row claims (warn only)
cover() { # dirname → 0 if a scope claims it, its parent, or lives inside it
  local d="$1" tok
  for tok in $scopes_all; do
    case "$tok" in
      "$d"|"$d/**"|"$d/"*) return 0 ;;
      */**) [ "${d#"${tok%/**}"}" != "$d" ] && return 0 ;;
    esac
  done
  return 1
}
scopes_all="$(grep '^|' "$map" | cut -d'|' -f3 | tr ',' ' ' | tr -s ' ' '\n' | grep -v '^ *$' | sort -u)"
for d in */ .github/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  skipped_gen "$name" && continue
  [ -z "$(find "$d" -type f -not -name '.*' -print -quit 2>/dev/null)" ] && continue
  cover "$name" || warn "uncovered top dir: $name/"
done
for parent in src lib app packages apps services modules libs; do
  [ -d "$parent" ] || continue
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    child="$(basename "$d")"
    skipped_gen "$child" && continue
    cover "$parent/$child" || warn "uncovered dir: $parent/$child/"
  done
done

echo "checked $rows namespaces: $fails failures, $warns warnings"
[ "$fails" -gt 0 ] && exit 1
exit 0

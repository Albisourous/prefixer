#!/usr/bin/env bash
# Lint .prefixer/namespaces.md — every row must resolve to real paths,
# tags must be unique, no draft rows, no generated dirs mapped.
# Exit 1 on any failure; warnings do not fail.
# usage: check_namespaces.sh [repo-root]
set -uo pipefail

root="${1:-.}"
# cd first: a relative $root would otherwise break every $map read below
cd "$root" 2>/dev/null || { echo "cannot cd $root" >&2; exit 1; }
map=".prefixer/namespaces.md"
[ -f "$map" ] || { echo "no map at $root/$map" >&2; exit 1; }
fails=0 warns=0 rows=0
skip="node_modules vendor dist build target out .git .prefixer __pycache__ .next .cache venv .venv .idea .vscode coverage .turbo .output .nuxt .svelte-kit storybook-static DerivedData Pods bin obj"

fail() { echo "FAIL $1"; fails=$((fails+1)); }
warn() { echo "warn $1"; warns=$((warns+1)); }

skipped_gen() { case " $skip " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

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
# wrong, its * matches slashes too (dead scopes would sail through).
# scopes are repo-relative and root-anchored: *.md matches root files
# only; a leading / means the same thing, not absolute path
glob_re() {
  printf '%s' "$1" | sed -e 's|^/||' -e 's/[.+^$|()]/\\&/g' -e 's/\*\*/@@/g' \
    -e 's/\*/[^\/]*/g' -e 's/\?/[^\/]/g' \
    -e 's|@@/|(.*/)?|g' -e 's/@@/.*/g' -e 's/^/^/' -e 's/$/$/'
}

# does a scope token resolve to at least one real path under .?
# grep -c, not -q: -q exits on first match, SIGPIPEs find, and pipefail
# then reports failure for a successful match
resolve() { find . | sed 's|^\./||' | grep -cE "$(glob_re "$1")" >/dev/null 2>&1; }

grep -q '^repo:' "$map" || warn "no repo: header; add 'repo: <slug>' for multi-codebase uniqueness"

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
    case "$tok" in
      node_modules/*|node_modules|vendor/*|dist/*|build/*|target/*|coverage/*|*-out/*|*-out)
        genflag=1 ;;
    esac
    resolve "$tok" && live=$((live+1))
  done <<< "$(expand_scope "$scope")"
  [ "$genflag" -eq 1 ] && fail "generated path mapped: ${tag}: — never map vendored/generated"
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
      */**) [ "${d#"${tok%/**}/"}" != "$d" ] && return 0 ;;
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
$(awk -F'|' '/^\|/ { print $3 }' "$map" | sed 's/^[ \t]*//; s/[ \t]*$//')
EOF
for d in */ .[!.]*/; do
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

# root files are a search intent too (config, manifests, docs) — a scope
# covers one by naming it or by a glob like *.md
ufiles=""
for f in *; do
  [ -f "$f" ] || continue
  hit=0
  # case patterns are never word-split, so spaced tokens match whole —
  # no eval needed
  while IFS= read -r tok; do
    case "$f" in $tok) hit=1; break ;; esac
  done <<< "$scopes_all"
  [ "$hit" -eq 0 ] && ufiles="$ufiles $f"
done
[ -n "$ufiles" ] && warn "uncovered root files:$ufiles"

echo "checked $rows namespaces: $fails failures, $warns warnings"
[ "$fails" -gt 0 ] && exit 1
exit 0

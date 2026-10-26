#!/usr/bin/env bash
# lib_scope.sh — shared scope machinery for the prefixer scripts.
# Source it, never run it: . "$(dirname "$0")/lib_scope.sh"
#
# One copy of the rules every script must agree on:
#   scope grammar  — expand_scope, glob_re, match_scope, resolve
#   map parsing    — scope_pairs, tag_scope, map_root
#   exclusion lists — PREFIXER_SKIP, skipped_gen, grep_excludes
#
# Scope semantics (the contract SPEC.md formalizes): scopes are
# repo-relative and root-anchored. `*` stays inside one directory level,
# `**` crosses levels, `?` is one non-/ char, `{a,b}` expands arm-wise,
# commas split alternates, a leading `/` anchors at the repo root — not
# the filesystem. Shell metachars are never evaluated: a scope is a glob,
# not a command.

# Directory names no map row or search should ever touch. The eval
# baseline uses the same list: its counterfactual is "this repo without
# prefixer", so .prefixer/ stays out of the root grep too — the map holds
# every namespace name as text and metrics.jsonl echoes every logged
# pattern, which would inflate the baseline against itself. Agent-
# tooling dot dirs (.devin/, .claude/) DO stay in the baseline: a real
# root grep hits them. .work is eval-corpus scratch (cloned repos):
# vendored code that is never the project being measured.
PREFIXER_SKIP="node_modules vendor dist build target out .git .prefixer .work __pycache__ .next .cache venv .venv .idea .vscode coverage .turbo .output .nuxt .svelte-kit storybook-static DerivedData Pods bin obj"

# find(1) primaries that prune every skipped dir — a scope landing on a
# parent dir (eval/) must not descend into the generated dirs inside it.
# Expand as:  find "$p" "${GEN_PRUNE[@]}" -o -type f -print
GEN_PRUNE=(\( -type d \( -name '*-out')
for _d in $PREFIXER_SKIP; do GEN_PRUNE+=(-o -name "$_d"); done
GEN_PRUNE+=(\) -prune \))
unset _d

skipped_gen() { case " $PREFIXER_SKIP " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

# scope text → one glob token per line. {a,b} expands arm-wise, commas
# split outside braces; spaces inside names survive. No eval anywhere —
# tokens are data, never shell.
expand_scope() {
  local s="$1" pre mid post arm
  case "$s" in
    *'{'*)
      pre="${s%%\{*}"; post="${s#*\}}"
      # no closing } — post is the whole string and the recursion would
      # grow forever; emit the typo'd token literally, let resolve fail it
      [ "$post" = "$s" ] && { printf '%s\n' "$s"; return; }
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
  # [ ] { } \ are literal — char classes are not scope syntax, so a glob
  # can never produce an invalid regex (unbalanced [ is just a char)
  printf '%s' "$1" | sed -e 's|^/||' -e 's/\\/\\\\/g' -e 's/[]]/\\]/g' \
    -e 's/\[/\\[/g' -e 's/[.+^$|(){}]/\\&/g' -e 's/\*\*/@@/g' \
    -e 's/\*/[^\/]*/g' -e 's/\?/[^\/]/g' \
    -e 's|@@/|(.*/)?|g' -e 's/@@/.*/g' -e 's/^/^/' -e 's/$/$/'
}

# real paths a glob token resolves to under cwd — run from repo root.
# Generated dirs are pruned first: a glob like eval/**/*.ts would
# otherwise "resolve" into vendored clones living under eval/.work
match_scope() { find . "${GEN_PRUNE[@]}" -o -print | sed 's|^\./||' | grep -E "$(glob_re "$1")" 2>/dev/null; }

# does a scope token resolve to at least one real path under .?
# grep -c, not -q: -q exits on first match, SIGPIPEs find, and pipefail
# then reports failure for a successful match
resolve() { find . "${GEN_PRUNE[@]}" -o -print | sed 's|^\./||' | grep -cE "$(glob_re "$1")" >/dev/null 2>&1; }

# one line per map row: composed tag, leaf name, scope — tab-separated.
# Ancestor tags rebuild from indentation: rows arrive depth-first, so the
# last row seen at any shallower level is this row's parent. Any leading
# whitespace indents — a tab nests the same as spaces, matching
# visualize.py's lstrip() so every tool reads one tag.
scope_pairs() { # map-file
  awk -F'|' '
    /^[[:space:]]*\|/ {
      pf=$2; sc=$3; name=pf
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); sub(/:[[:space:]]*$/, "", name)
      if (name == "" || name == "prefix" || name ~ /^-/) next
      ind = pf; sub(/[^[:space:]].*/, "", ind); lvl = length(ind)
      for (i in t) if (i >= lvl) delete t[i]
      par = ""
      for (i = lvl - 1; i >= 0; i--) if (i in t) { par = t[i]; break }
      tag = (par == "" ? name : par ":" name); t[lvl] = tag
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sc)
      print tag "\t" name "\t" sc
    }' "$1"
}

# composed tag or leaf prefix → its scope. A bare leaf matches the first
# row carrying it; ambiguity is the caller's problem (scope_pairs lists
# every candidate).
tag_scope() { # want-tag, map → scope
  awk -F'|' -v want="$1" '
    /^[[:space:]]*\|/ {
      pf=$2; sc=$3; name=pf
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); sub(/:[[:space:]]*$/, "", name)
      if (name == "" || name == "prefix" || name ~ /^-/) next
      ind = pf; sub(/[^[:space:]].*/, "", ind); lvl = length(ind)
      for (i in t) if (i >= lvl) delete t[i]
      par = ""
      for (i = lvl - 1; i >= 0; i--) if (i in t) { par = t[i]; break }
      tag = (par == "" ? name : par ":" name); t[lvl] = tag
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sc)
      if (tag == want) { print sc; exit }
    }' "$2"
}

# deduped file list a scope covers: globs resolve, dirs expand to files,
# overlapping globs and dir+file pairs collapse — grepping the same file
# twice would double-count hits
scope_files() { # scope → file list, one per line (cwd = repo root)
  local tok paths="" p
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
  done <<< "$(expand_scope "$1")"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ -d "$p" ]; then
      find "$p" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -print
    else
      printf '%s\n' "$p"
    fi
  done <<< "$paths" | sort -u
}

# --exclude-dir args for the counterfactual root grep: the generated,
# vendored, and prefixer-owned dirs a map excludes anyway (a grep
# through node_modules measures a strawman, and a hit on the map or the
# metrics log measures prefixer, not the repo)
grep_excludes() {
  printf -- "--exclude-dir=*-out"
  for d in $PREFIXER_SKIP; do printf ' --exclude-dir=%s' "$d"; done
  printf '\n'
}

# walk up from $1 for the dir holding .prefixer/, else git toplevel,
# else $1 — every tool anchors state beside the map, never a stray
# .prefixer in a subdirectory
map_root() { # start-dir → repo root holding .prefixer/
  local up
  up="$(cd "$1" 2>/dev/null && pwd)" || return 1
  until [ -d "$up/.prefixer" ] || [ "$up" = "/" ]; do up="$(dirname "$up")"; done
  if [ -d "$up/.prefixer" ]; then printf '%s\n' "$up"
  elif cd "$1" 2>/dev/null && git rev-parse --show-toplevel >/dev/null 2>&1; then
    (cd "$1" && git rev-parse --show-toplevel)
  else printf '%s\n' "$up"
  fi
}

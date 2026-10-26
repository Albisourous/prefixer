#!/usr/bin/env bash
# suggest_map.sh — close the loop. Reads .prefixer/metrics.jsonl, the
# map, and the tree; proposes concrete row edits. The map stays
# hand-curated — this prints a review list, it never rewrites the file
# (update, never regenerate).
#
# Signals, strongest first:
#   ADD   — searched scopes / widened-hit dirs no row claims
#   CHECK — uncovered dirs the linter flags, drift since the map changed
#   CUT   — rows that never scoped a logged search
#   HEALTH — check_namespaces.sh verdict, restated
#
# usage: suggest_map.sh [repo-root]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

root="$(map_root "${1:-$PWD}")"
map="$root/.prefixer/namespaces.md"
log="$root/.prefixer/metrics.jsonl"
[ -f "$map" ] || { echo "no map at $map; run init_namespaces.sh first" >&2; exit 1; }
cd "$root" || exit 1

pairs="$(scope_pairs "$map")"
lines=0; [ -f "$log" ] && lines="$(grep -c . "$log" 2>/dev/null || true)"

echo "prefixer map review: $(grep -m1 '^repo:' "$map" | sed 's/^repo: *//')"
echo "log: $lines line(s) in .prefixer/metrics.jsonl"
echo

# does a searched path sit inside some row's scope? row scope `src/**`
# covers `src/auth`; `*.md` covers nothing here — path-prefix logic only
covered() { # searched-dir, tab-separated tag/name/scope lines → 0 if a row contains it
  local d="$1" _t _l sc tok rowdir
  while IFS=$'\t' read -r _t _l sc; do
    while IFS= read -r tok; do
      case "$tok" in
        */**) rowdir="${tok%/**}" ;;
        *) rowdir="${tok%/*}" ;;
      esac
      [ -z "$rowdir" ] && continue
      case "$d/" in "$rowdir/"*) return 0 ;; esac
    done <<< "$(expand_scope "$sc")"
  done <<< "$2"
  return 1
}

# a suggested ADD row: slug from the dir's own name (a generic basename
# like src/ defers to its parent — `crates/cli/src` wants `cli`, not
# `src`), contains from the file names inside — derived, never declared
add_row() { # dir, why
  local d="$1" slug names
  slug="$(basename "$d")"
  case "$slug" in src|lib|app|include|source|test|tests|code)
    slug="$(basename "$(dirname "$d")")" ;; esac
  slug="$(printf '%s' "$slug" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-8)"
  [ -n "$slug" ] || slug="new"
  names="$(find "$d" -maxdepth 2 -type f -not -name '.*' 2>/dev/null |
    sed 's|.*/||; s/\.[^.]*$//' | sort -u | head -3 | paste -sd, - | sed 's/,/, /g')"
  printf '  | %s: | %s/** | files like %s |   <- %s\n' "$slug" "$d" "${names:-?}" "$2"
}

# --- ADD: searched scopes no row claims -------------------------------
adds=""
# scopes agents actually searched (measure_search path args, search.sh
# scope cells) — normalize to a dir prefix, keep unmapped ones
if [ -f "$log" ]; then
  searched="$(sed -n 's/.*"scope":"\([^"]*\)".*/\1/p' "$log" | sort | uniq -c | sort -rn)"
  while IFS= read -r line; do
    n="$(printf '%s' "$line" | awk '{print $1}')"
    sc="$(printf '%s' "$line" | sed 's/^ *[0-9]* *//')"
    [ "$sc" = root ] && continue
    # multi-token scope cells: check each
    while IFS= read -r tok; do
      d="${tok%/\*\*}"; d="${d%/\*}"; d="${d%/}"
      case "$d" in ''|'*'*|.) continue ;; esac
      [ -d "$d" ] || continue
      if ! covered "$d" "$pairs"; then
        adds="$adds$d	searched ${n}x in the log
"
      fi
    done <<< "$(expand_scope "$sc")"
  done <<< "$searched"

  # widened hits that clustered outside the tried scope — the strongest
  # "this namespace is missing" signal the log produces
  while IFS= read -r hd; do
    [ -n "$hd" ] || continue
    while IFS=, read -ra pair; do
      for kv in "${pair[@]}"; do
        d="${kv%%:*}"; d="${d# }"
        case "$d" in ''|.) continue ;; esac
        [ -d "$d" ] || continue
        covered "$d" "$pairs" ||
          adds="$adds$d	misses widened into here
"
      done
    done <<< "$hd"
  done <<< "$(sed -n 's/.*"hit_dirs":"\([^"]*\)".*/\1/p' "$log")"
fi

if [ -n "$adds" ]; then
  echo "ADD: rows real searches asked for:"
  printf '%s' "$adds" | sort -u | while IFS=$'\t' read -r d why; do
    add_row "$d" "$why"
  done
  echo
fi

# --- CHECK: coverage warnings from the linter, with drift --------------
lint="$(bash "$here/check_namespaces.sh" "$root" 2>&1 || true)"
unc="$(printf '%s\n' "$lint" | sed -n 's/^warn uncovered \(top dir\|dir\): \(.*\)\/$/\2/p')"
if [ -n "$unc" ]; then
  echo "CHECK: uncovered dirs, and whether they changed after the map:"
  printf '%s\n' "$unc" | while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -d "$d" ] && [ -n "$(find "$d" -newer "$map" -type f -print -quit 2>/dev/null)" ]; then
      echo "  $d/  : touched after the map last changed"
    else
      echo "  $d/  : pre-dates the map; likely a scope fix"
    fi
  done
  echo
fi

# --- CUT: rows that never scoped a logged search -----------------------
if [ "$lines" -ge 10 ]; then
  cold=""
  while IFS=$'\t' read -r tag leaf sc; do
    [ -n "$tag" ] || continue
    grep -qF "\"ns\":\"$tag\"" "$log" 2>/dev/null && continue
    # also count rows whose scope cell was searched verbatim
    grep -qF "\"scope\":\"$sc\"" "$log" 2>/dev/null && continue
    cold="$cold  $tag:  ($sc)
"
  done <<< "$pairs"
  if [ -n "$cold" ]; then
    echo "CUT: rows that scoped 0 of $lines logged searches (keep if new):"
    printf '%s' "$cold"
    echo
  fi
fi

# --- root searches: the unscoped habit, counted ------------------------
if [ -f "$log" ]; then
  roots="$(grep -c '"scope":"root"' "$log" 2>/dev/null || true)"
  if [ "${roots:-0}" -gt 0 ]; then
    echo "ROOT: $roots logged search(es) ran unscoped."
    echo "  route searches through search.sh <ns> <pattern>; it logs and widens itself"
    echo
  fi
fi

# --- HEALTH: the lint verdict, restated --------------------------------
echo "HEALTH: $(printf '%s\n' "$lint" | tail -1)"
[ "$lines" -eq 0 ] &&
  echo "(no log yet; searches run via search.sh or measure_search.sh start the flywheel)"
exit 0

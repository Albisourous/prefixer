#!/usr/bin/env bash
# Evaluate every namespace in a repo's map — lint it, then measure the
# token delta of a scoped search vs a root search per row. The probe
# pattern is the namespace's own name: derived vocabulary probing itself,
# no per-repo config. Rows eval by their composed tag, so a nested
# orders:checkout: is measured against its own scope, not a sibling's.
# usage: eval_repo.sh [repo-root]
set -uo pipefail

root="${1:-.}"
map="$root/.prefixer/namespaces.md"
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$map" ] || { echo "no map at $map; run init_namespaces.sh first" >&2; exit 1; }

repo="$(grep -m1 '^repo:' "$map" | sed 's/^repo: *//')"
printf 'repo: %s\n\n' "${repo:-$(basename "$(cd "$root" && pwd)")}"

bash "$here/check_namespaces.sh" "$root" || true
echo

# one line per row: composed tag, leaf name, scope — tags rebuilt from
# indentation the same way check_namespaces.sh validates them
. "$here/lib_scope.sh"
pairs="$(scope_pairs "$map")"

printf '%-24s %9s %11s %9s %11s %7s\n' "tag" "root_hits" "root_bytes" "ns_hits" "ns_bytes" "pct"
tot=0; n=0; skipped=0; excl=0
while IFS=$'\t' read -r tag leaf scope; do
  [ -n "$tag" ] || continue
  out="$(bash "$here/eval_scope.sh" "$root" "$leaf" "$tag" "$scope" 2>/dev/null)"
  [ -n "$out" ] || continue
  rh="$(printf '%s' "$out" | sed -n 's/.*"root_hits":\([0-9]*\).*/\1/p')"
  rb="$(printf '%s' "$out" | sed -n 's/.*"root_bytes":\([0-9]*\).*/\1/p')"
  sh="$(printf '%s' "$out" | sed -n 's/.*"ns_hits":\([0-9]*\).*/\1/p')"
  sb="$(printf '%s' "$out" | sed -n 's/.*"ns_bytes":\([0-9]*\).*/\1/p')"
  pc="$(printf '%s' "$out" | sed -n 's/.*"pct_saved":\(-\{0,1\}[0-9]*\).*/\1/p')"
  # a scope that lives entirely inside dirs the baseline grep skips
  # compares two different universes — mark it, don't fake a number
  if printf '%s' "$out" | grep -q '"baseline_excluded":true'; then
    printf '%-24s %9s %11s %9s %11s %7s\n' "$tag:" "$rh" "$rb" "$sh" "$sb" "n/a"
    excl=$((excl + 1)); continue
  fi
  # a namespace whose own name never appears in its files can't prove
  # savings — 0 scoped hits is a probe blind spot, not a perfect score
  if [ "$sh" = "0" ]; then
    printf '%-24s %9s %11s %9s %11s %7s\n' "$tag:" "$rh" "$rb" "$sh" "$sb" "n/a"
    skipped=$((skipped + 1)); continue
  fi
  printf '%-24s %9s %11s %9s %11s %6s%%\n' "$tag:" "$rh" "$rb" "$sh" "$sb" "$pc"
  tot=$((tot + pc)); n=$((n + 1))
done <<< "$pairs"
echo
[ "$n" -gt 0 ] && echo "mean pct_saved: $((tot / n))% across $n namespaces"
[ "$skipped" -gt 0 ] && echo "($skipped namespaces n/a: 0 hits for their own name; probe them with real query patterns)"
[ "$excl" -gt 0 ] && echo "($excl namespaces n/a: scope lives inside dirs the baseline excludes)"
exit 0

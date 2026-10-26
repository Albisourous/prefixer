#!/usr/bin/env bash
# Evaluate every namespace in a repo's map — lint it, then measure the
# token delta of a scoped search vs a root search per row. The probe
# pattern is the namespace's own name: derived vocabulary probing itself,
# no per-repo config.
# usage: eval_repo.sh [repo-root]
set -uo pipefail

root="${1:-.}"
map="$root/.prefixer/namespaces.md"
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$map" ] || { echo "no map at $map — run init_namespaces.sh first" >&2; exit 1; }

repo="$(grep -m1 '^repo:' "$map" | sed 's/^repo: *//')"
printf 'repo: %s\n\n' "${repo:-$(basename "$(cd "$root" && pwd)")}"

bash "$here/check_namespaces.sh" "$root" || true
echo

printf '%-16s %9s %11s %9s %11s %7s\n' "prefix" "root_hits" "root_bytes" "ns_hits" "ns_bytes" "pct"
tot=0; n=0
for ns in $(grep -oE '^\| *[a-zA-Z0-9_.-]+:' "$map" | sed 's/[| :]//g'); do
  [ "$ns" = "prefix" ] && continue
  out="$(bash "$here/eval_scope.sh" "$root" "$ns" "$ns" 2>/dev/null)"
  [ -n "$out" ] || continue
  rh="$(printf '%s' "$out" | sed -n 's/.*"root_hits":\([0-9]*\).*/\1/p')"
  rb="$(printf '%s' "$out" | sed -n 's/.*"root_bytes":\([0-9]*\).*/\1/p')"
  sh="$(printf '%s' "$out" | sed -n 's/.*"ns_hits":\([0-9]*\).*/\1/p')"
  sb="$(printf '%s' "$out" | sed -n 's/.*"ns_bytes":\([0-9]*\).*/\1/p')"
  pc="$(printf '%s' "$out" | sed -n 's/.*"pct_saved":\([0-9]*\).*/\1/p')"
  printf '%-16s %9s %11s %9s %11s %6s%%\n' "$ns:" "$rh" "$rb" "$sh" "$sb" "$pc"
  tot=$((tot + pc)); n=$((n + 1))
done
echo
[ "$n" -gt 0 ] && echo "mean pct_saved: $((tot / n))% across $n namespaces"

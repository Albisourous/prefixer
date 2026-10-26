#!/usr/bin/env bash
# Corpus evidence: shallow-clone every repo in repos.txt, scaffold a map,
# lint it, eval it, rewrite RESULTS.md. Nothing is configured per repo —
# if the scaffold degrades on a new repo shape, the table shows it.
# usage: eval/run.sh [--work DIR]   (clones cached in eval/.work)
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
work="$here/.work"
out="$here/RESULTS.md"
if [ "${1:-}" = "--work" ]; then work="${2:?--work needs a dir}"; fi
mkdir -p "$work"

rows="" tot=0 n=0
while read -r repo shape _; do
  case "$repo" in ''|'#'*) continue ;; esac
  dir="$work/${repo//\//__}"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull -q --ff-only 2>/dev/null || true
  else
    echo "cloning $repo" >&2
    git clone -q --depth 1 "https://github.com/$repo" "$dir" 2>/dev/null || {
      echo "clone failed: $repo" >&2; continue; }
  fi
  # the map is disposable eval data, not a curated repo file — refresh it
  # or weekly CI measures the first-run map against a moving repo
  rm -f "$dir/.prefixer/namespaces.md"
  bash "$root/scripts/init_namespaces.sh" "$dir" >/dev/null 2>&1 || true
  lint="$(bash "$root/scripts/check_namespaces.sh" "$dir" 2>&1 | tail -1)"
  table="$(bash "$root/scripts/eval_repo.sh" "$dir" 2>/dev/null)"
  # per-row pct column → count, mean, min, max; lint summary → ok/warn/fail
  stats="$(printf '%s' "$table" | awk '$NF ~ /^[0-9]+%$/ { gsub(/%/, "", $NF); print $NF }' |
    sort -n | awk '{ a[NR]=$1; s+=$1 } END { if (NR) printf "%d %d %d %d", NR, s/NR, a[1], a[NR] }')"
  fails="$(printf '%s' "$lint" | sed -n 's/.*: \([0-9]*\) failures.*/\1/p')"
  warns="$(printf '%s' "$lint" | sed -n 's/.*, \([0-9]*\) warnings.*/\1/p')"
  mark="ok"; [ "${warns:-0}" -gt 0 ] && mark="warn"; [ "${fails:-1}" -gt 0 ] && mark="FAIL"
  if [ -n "$stats" ]; then
    set -- $stats
    rows="$rows| [$repo](https://github.com/$repo) | $shape | $1 | $2% | $3-$4% | $mark |
"
    tot=$((tot + $2)); n=$((n + 1))
    echo "  $repo: $1 namespaces, mean $2%, lint $mark" >&2
  else
    rows="$rows| [$repo](https://github.com/$repo) | $shape | - | - | - | $mark |
"
    echo "  $repo: no evaluable rows, lint $mark" >&2
  fi
done < "$here/repos.txt"

{
  echo "# Eval corpus"
  echo
  echo "\`eval/run.sh\` shallow-clones each repo in \`repos.txt\`, scaffolds a"
  echo "map, lints it, and probes every namespace with \`eval_repo.sh\`: each"
  echo "row's own name as the grep pattern, nothing configured per repo."
  echo "Rows whose name never appears in their files report \`n/a\` and are"
  echo "excluded; a 0-hit probe can't prove savings."
  echo "Regenerated weekly by \`.github/workflows/eval.yml\`."
  echo
  echo "| repo | shape | namespaces | mean saved | range | lint |"
  echo "|------|-------|-----------:|-----------:|-------|------|"
  printf '%s' "$rows"
  echo
  if [ "$n" -gt 0 ]; then
    echo "**Corpus mean: $((tot / n))% of search-output bytes saved across $n repos.**"
    echo
  fi
  echo "Last run: $(date -u +%F) (UTC)"
} > "$out"
echo "wrote $out" >&2

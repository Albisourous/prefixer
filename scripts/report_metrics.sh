#!/usr/bin/env bash
# report_metrics.sh — the reader half of metrics.jsonl. The writers
# append (search.sh, measure_search.sh, eval_scope.sh --log, hand-written
# task lines); this aggregates them: searches and est tokens spent,
# first-try hit rate, scoped-vs-baseline delta, eval-row savings,
# per-scope spend, and the searches that still went unscoped.
# usage: report_metrics.sh [repo-root]
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

root="$(map_root "${1:-$PWD}")"
log="$root/.prefixer/metrics.jsonl"
[ -f "$log" ] || {
  echo "no metrics log at $log" >&2
  echo "run searches through search.sh or measure_search.sh to start it" >&2
  exit 1
}

repo="$(grep -m1 '^repo:' "$root/.prefixer/namespaces.md" 2>/dev/null | sed 's/^repo: *//')"
lines="$(grep -c . "$log" || true)"

# JSON field extractors shared by both passes — naive on purpose (stops
# at the first inner quote), the same tolerance suggest_map.sh uses.
# eval-scope lines summarize separately; per-search delta compares only
# lines that carry a hit count (search-level entries)
AWKLIB='
function sfield(l, k,   s) {
  if (match(l, "\"" k "\":\"")) {
    s = substr(l, RSTART + length(k) + 4)
    return substr(s, 1, index(s, "\"") - 1)
  }
  return ""
}
function nfield(l, k) {
  if (match(l, "\"" k "\":-?[0-9]+"))
    return substr(l, RSTART + length(k) + 3, RLENGTH - length(k) - 3) + 0
  return ""
}
'

eval "$(awk "$AWKLIB"'
{
  if ($0 ~ /"task":"eval-scope"/) {
    ev++; evs += nfield($0, "est_tokens_saved")
    if (match($0, /"pct_saved":-?[0-9]+/)) { pn++; pt += nfield($0, "pct_saved") }
    next
  }
  est = nfield($0, "est_tokens"); tok += est
  s = nfield($0, "searches"); ns += (s == "" ? 1 : s)
  calls += nfield($0, "tool_calls")
  tasks[sfield($0, "task")] = 1
  if ($0 ~ /"baseline":true/) { bn++; bt += est }
  else if ($0 ~ /"hits":/ && sfield($0, "scope") != "root") { sn++; st += est }
  if ($0 ~ /"first_try_hit":true/) fh++
  else if ($0 ~ /"first_try_hit":false/) fm++
  if (sfield($0, "scope") == "root" && $0 !~ /"baseline":true/) roots++
}
END {
  print "v_searches=" ns+0, "v_tasks=" length(tasks), "v_est=" tok+0, "v_calls=" calls+0
  print "v_first=" fh+0, "v_misses=" fm+0
  print "v_base_n=" bn+0, "v_base_est=" bt+0, "v_scoped_n=" sn+0, "v_scoped_est=" st+0
  print "v_eval_n=" ev+0, "v_eval_saved=" evs+0, "v_pct_n=" pn+0, "v_pct_sum=" pt+0, "v_roots=" roots+0
}' "$log")"

echo "metrics: ${repo:-$(basename "$root")} ($lines logged lines)"
echo

printf 'searches:   %s across %s tasks, ~%s est tokens' "$v_searches" "$v_tasks" "$v_est"
[ "$v_calls" -gt 0 ] && printf ', %s tool calls' "$v_calls"
printf '\n'
ftot=$((v_first + v_misses))
[ "$ftot" -gt 0 ] && printf 'first-try:  %s/%s scoped searches hit first try (%s%%)\n' \
  "$v_first" "$ftot" "$((v_first * 100 / ftot))"
[ "$v_base_n" -gt 0 ] &&
  printf 'baseline:   %s probes, ~%s est tokens mean\n' "$v_base_n" "$((v_base_est / v_base_n))"
if [ "$v_base_n" -gt 0 ] && [ "$v_scoped_n" -gt 0 ] && [ "$v_base_est" -ge "$v_base_n" ]; then
  printf 'delta:      scoped searches use ~%s%% of baseline est tokens\n' \
    "$((v_scoped_est * 100 / (v_scoped_n * (v_base_est / v_base_n))))"
fi
if [ "$v_eval_n" -gt 0 ]; then
  printf 'eval rows:  %s measured, ~%s est tokens saved total' "$v_eval_n" "$v_eval_saved"
  [ "$v_pct_n" -gt 0 ] && printf ', mean %s%% per row' "$((v_pct_sum / v_pct_n))"
  printf '\n'
fi

# per-scope spend, most-searched first — misses are first_try_hit:false
table="$(awk "$AWKLIB"'
/"task":"eval-scope"/ { next }
{
  sc = sfield($0, "scope"); if (sc == "") sc = sfield($0, "ns")
  if (sc == "") sc = "(task)"
  cnt[sc]++; tk[sc] += nfield($0, "est_tokens")
  if ($0 ~ /"first_try_hit":false/) ms[sc]++
  if ($0 ~ /"widened_to":/) wd[sc]++
}
END { for (s in cnt) printf "%d\t%d\t%d\t%d\t%s\n", cnt[s], tk[s], ms[s], wd[s], s }
' "$log" | sort -t$'\t' -k1,1nr -k2,2nr | head -10)"

if [ -n "$table" ]; then
  echo
  printf '%-28s %4s %10s %6s %7s\n' "scope" "n" "est_tokens" "miss" "widened"
  printf '%s\n' "$table" | while IFS=$'\t' read -r n tok miss wide sc; do
    printf '%-28s %4s %10s %6s %7s\n' "$sc" "$n" "$tok" "$miss" "$wide"
  done
fi

[ "$v_roots" -gt 0 ] && {
  echo
  echo "unscoped: $v_roots search(es) ran at root, route them through search.sh <ns>"
}
exit 0

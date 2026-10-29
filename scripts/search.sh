#!/usr/bin/env bash
# search.sh — the discipline as a command, not a reminder.
#
#   search.sh auth expire         grep "expire" inside the auth: scope;
#                                 on a miss widen one level (parent
#                                 namespace, then the repo minus generated
#                                 dirs) and say where hits landed
#   search.sh --scope auth        print auth:'s glob list — the map as an
#                                 index another command can query:
#                                 grep -rn x $(search.sh --paths auth)
#   search.sh --paths auth        print the scope's resolved files/dirs
#   search.sh --list              print every tag with its scope
#
# Output is budgeted: at most --max hits print (default 40, env
# PREFIXER_MAX_HITS), each cut to 240 chars; past the cap the rest is
# summarized by dir so the next search can narrow instead of paging.
#   search.sh -l auth expire      files with hit counts, not lines
#
# Every search logs one metrics.jsonl line (scope, hits, printed tokens,
# first_try_hit; hit_dirs on a widened hit): §4 to §8 of the skill run
# themselves. Flags: --repo DIR, --no-widen, --no-log, -i, -w, -F,
# -l, --max N, --all (no cap).
# Exit: 0 hits found, 1 none found even widened, 2 usage.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib_scope.sh"

repo="" widen=1 nolog="" ign="" gflags=() files_mode=0
max="${PREFIXER_MAX_HITS:-40}"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?--repo needs a dir}"; shift ;;
    --no-widen) widen=0 ;;
    --no-log) nolog=1 ;;
    -i|--ignore-case) ign="-i" ;;
    -w|-F) gflags+=("$1") ;;
    -l|--files) files_mode=1 ;;
    --max) max="${2:?--max needs a number}"; shift ;;
    --all) max=0 ;;
    --scope|--paths|--list) mode="${1#--}" ;;
    --) shift; break ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
mode="${mode:-search}"

root="$(map_root "${repo:-$PWD}")"
map="$root/.prefixer/namespaces.md"
if [ ! -f "$map" ]; then
  echo "no map at $root/.prefixer/namespaces.md" >&2
  echo "run bash <skill>/scripts/init_namespaces.sh $root first" >&2
  exit 2
fi

if [ "$mode" = list ]; then
  scope_pairs "$map" | while IFS=$'\t' read -r tag _ sc; do
    printf '%-16s %s\n' "$tag:" "$sc"
  done
  exit 0
fi

ns="${1:?usage: search.sh [--repo DIR] [--scope|--paths|--list] [--no-widen] [--no-log] [-i] <ns> [pattern]}"
pat="${2:-}"

# a bare leaf may sit under several parents — ambiguity is reported, not
# resolved by first-match
matches="$(scope_pairs "$map" | awk -F'\t' -v n="$ns" \
  '$1 == n || $2 == n { print $1 "\t" $3 }')"
case "$(printf '%s' "$matches" | grep -c .)" in
  0) echo "no namespace '${ns}:' in $map; tags:" >&2
     scope_pairs "$map" | awk -F'\t' '{ printf "  %s:\n", $1 }' >&2
     exit 2 ;;
  *) if [ "$(printf '%s' "$matches" | grep -c .)" -gt 1 ] &&
        ! printf '%s' "$matches" | awk -F'\t' -v n="$ns" '$1 == n' | grep -q .; then
       echo "'${ns}:' is ambiguous; qualify it:" >&2
       printf '%s' "$matches" | awk -F'\t' '{ printf "  %s: -> %s\n", $1, $2 }' >&2
       exit 2
     fi ;;
esac
# an exact composed-tag match wins over leaf matches under other parents
exact="$(printf '%s' "$matches" | awk -F'\t' -v n="$ns" '$1 == n')"
[ -n "$exact" ] && matches="$exact"
scope="$(printf '%s' "$matches" | head -1 | cut -f2)"
tag="$(printf '%s' "$matches" | head -1 | cut -f1)"

# the scope cell is data, never shell — a metachar scope is a mistake,
# not a glob (same rule check_namespaces.sh enforces)
case "$scope" in
  *'$('*|*\`*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*$'\n'*)
    echo "unsafe scope on ${tag}: → $scope" >&2; exit 2 ;;
esac

cd "$root" || exit 2
px_index

case "$mode" in
  scope) printf '%s\n' "$scope"; exit 0 ;;
  paths) scope_files "$scope"; exit 0 ;;
esac

[ -n "$pat" ] || { echo "usage: search.sh <ns> <pattern>  (or --scope/--paths/--list)" >&2; exit 2; }

# scoped pass — the namespace's globs to files, one grep over the list.
# an empty file list must not reach xargs: grep with no file operands
# would read stdin and can hang an interactive caller
run_scoped() { # scope → hits on stdout
  local files
  files="$(scope_files "$1")"
  [ -n "$files" ] || return 0
  printf '%s' "$files" | tr '\n' '\0' |
    xargs -0 grep -nIH $ign ${gflags[@]+"${gflags[@]}"} -- "$pat" 2>/dev/null
}
hits="$(run_scoped "$scope")"

# widen one level on a miss: nested tag → parent scope, then the repo
# minus generated dirs. Never a jump straight to vendor.
found_in="" level=""
if [ -n "$hits" ]; then found_in="$tag"; level="$tag:"
else
  if [ "$widen" -eq 1 ]; then
    if [[ "$tag" == *:* ]]; then
      ptag="${tag%:*}"
      pscope="$(tag_scope "$ptag" "$map")"
      if [ -n "$pscope" ]; then
        hits="$(run_scoped "$pscope")"
        [ -n "$hits" ] && { found_in="$ptag"; level="$ptag:"; }
      fi
    fi
    if [ -z "$hits" ]; then
      # the repo index: git-aware, generated dirs and .prefixer dropped
      # (the log echoes every pattern, a widened search would self-hit)
      hits="$(repo_files | tr '\n' '\0' |
        xargs -0 grep -nIH $ign ${gflags[@]+"${gflags[@]}"} -- "$pat" 2>/dev/null)"
      [ -n "$hits" ] && { found_in="root"; level=""; }
    fi
  fi
fi

n="$(printf '%s' "$hits" | grep -c . || true)"
# what reaches the caller is the token cost: -l folds lines to files,
# the cap and the line cut bound the rest
if [ "$files_mode" -eq 1 ]; then
  shown_txt="$(printf '%s\n' "$hits" | awk 'NF { f = $0; sub(/:[0-9]+:.*/, "", f)
      c[f]++ } END { for (f in c) print c[f] "\t" f }' | sort -t "$(printf '\t')" -k1,1nr -k2,2 |
    awk -F'\t' -v m="$max" '{ if (m > 0 && NR > m) { r++; next } print $2 ":" $1 }
      END { if (r) print "(+" r " more files)" }')"
else
  shown_txt="$(printf '%s\n' "$hits" | awk -v m="$max" 'NF { if (m > 0 && ++k > m) exit
      if (length($0) > 240) $0 = substr($0, 1, 240) " [...]"; print }')"
fi
[ -n "$shown_txt" ] && printf '%s\n' "$shown_txt"
shown="$(printf '%s' "$shown_txt" | grep -c . || true)"
bytes="$(printf '%s' "$shown_txt" | wc -c | tr -d ' ')"
est=$((bytes / 4))
if [ "$files_mode" -eq 0 ] && [ "$max" -gt 0 ] && [ "$n" -gt "$max" ]; then
  dense="$(printf '%s\n' "$hits" | sed -n "$((max + 1)),\$p" | cut -d: -f1 |
    awk '{ if (!sub(/\/[^\/]*$/, "")) $0 = "." } { c[$0]++ } END { for (d in c) print c[d] "\t" d }' |
    sort -rn | head -5 | awk -F'\t' '{ printf "%s%s/:%s", sep, $2, $1; sep = ", " }')"
  echo "$((n - max)) more hits not shown; densest: $dense" >&2
  echo "narrow: a child tag (search.sh --list), -w, a sharper pattern; or -l / --all" >&2
fi

# where widened hits clustered — the map-gap signal a review (or
# suggest_map.sh) can act on
hit_dirs=""
if [ -n "$hits" ] && [ "$found_in" != "$tag" ]; then
  hit_dirs="$(printf '%s\n' "$hits" | cut -d: -f1 |
    awk '{ if (sub(/\/[^\/]*$/, "")) print; else print "." }' |
    sort | uniq -c | sort -rn | head -3 |
    awk '{ d=$2; for (i=3; i<=NF; i++) d=d" "$i; printf "%s%s:%s", sep, d, $1; sep="," }')"
fi

first=true
[ "$found_in" != "$tag" ] && first=false
if [ "$found_in" = "$tag" ]; then
  echo "searched ${tag}: → $n hits, $shown shown (~$est tokens)" >&2
elif [ -n "$found_in" ]; then
  echo "miss in ${tag}:, widened to $found_in → $n hits, $shown shown (~$est tokens)" >&2
  [ -n "$hit_dirs" ] && echo "hits landed under: $hit_dirs, possible map gap" >&2
else
  msg="miss in ${tag}:"
  [ "$widen" -eq 1 ] && msg="$msg, none repo-wide either"
  echo "$msg (~$est tokens)" >&2
fi

if [ -z "$nolog" ]; then
  mkdir -p "$root/.prefixer"
  grep -qx 'metrics.jsonl' "$root/.prefixer/.gitignore" 2>/dev/null ||
    echo 'metrics.jsonl' >> "$root/.prefixer/.gitignore"
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  extra=""
  [ "$found_in" != "$tag" ] && extra=",\"widened_to\":\"${found_in:-none}\""
  [ -n "$hit_dirs" ] && extra="$extra,\"hit_dirs\":\"$(esc "$hit_dirs")\""
  printf '{"ts":"%s","task":"scoped-search","ns":"%s","pattern":"%s","scope":"%s","searches":1,"hits":%s,"shown":%s,"est_tokens":%s,"first_try_hit":%s%s}\n' \
    "$(date -u +%FT%TZ)" "$(esc "$tag")" "$(esc "$pat")" "$(esc "$scope")" \
    "$n" "$shown" "$est" "$first" "$extra" >> "$root/.prefixer/metrics.jsonl"
fi

[ -n "$hits" ] && exit 0
exit 1

#!/usr/bin/env bash
# Scaffold .prefixer/namespaces.md from a repo's layout.
# Rows are picked by size, not by alphabet: every dir is weighted by the
# text files a grep would read (binary files count 1/8), then a greedy
# pass gives rows to the heaviest dirs up to three levels deep, skipping
# a dir that is nearly all of a row already taken and collapsing
# single-child chains (src/pkg/ maps as pkg:). Rows nest under the row
# that contains them, so widen-on-miss climbs the real tree. Inventory is
# git-aware: .gitignore'd output never earns a row. Prefixes come from
# dir names; contains cells come from agent docs that name the dir, the
# dir's own README or manifest, its entry/name-sharing files, then
# exported symbols, plus a file count and the biggest subdirs. Also maps
# the files at repo root, jumbo source files (>3k lines), entry points.
# usage: init_namespaces.sh [repo-root]
# no pipefail: head-capped pipelines SIGPIPE their producers by design
set -eu

root="${1:-.}"
out="$root/.prefixer/namespaces.md"

if [ -f "$out" ]; then
  echo "$out already exists; edit the stale rows, never regenerate" >&2
  exit 1
fi
[ -d "$root" ] || { echo "no such dir: $root" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
# exclusion list, repo_files, skipped_gen: scripts/lib_scope.sh (single copy)
. "$here/lib_scope.sh"

root="$(cd "$root" && pwd)"
out="$root/.prefixer/namespaces.md"
cd "$root"
mkdir -p .prefixer
grep -qx 'metrics.jsonl' .prefixer/.gitignore 2>/dev/null ||
  echo 'metrics.jsonl' >> .prefixer/.gitignore

# non-semantic words that appear in every repo — never a prefix
stop_re='^(index|main|mod|init|utils?|helpers?|common|shared|base|file|code|misc|tmp|temp|readme|license|package)$'

max_rows=12 rows=0
# source extensions: what symbol sampling and jumbo rows look at
code_re='\.(c|cc|cpp|cxx|h|hh|hpp|hxx|m|mm|swift|kt|kts|java|scala|go|rs|py|rb|php|js|jsx|ts|tsx|mjs|cjs|vue|svelte|lua|luau|cs|fs|ex|exs|erl|hs|ml|clj|dart|jl|sh|bash|zsh|ps1|sql|pl|gd|zig|nim|sol|r)$'

# --- inventory: one git-aware file list, split text vs binary ---------
px_index
allf="$(repo_files)"
nfiles="$(printf '%s' "$allf" | grep -c . || true)"
nul_list() { printf '%s\n' "$1" | awk 'NF' | tr '\n' '\0'; }
# grep -l '' lists non-empty files; -I drops binaries. Empty files weigh 0
textf="" nonempty=""
if [ -n "$allf" ]; then
  textf="$(nul_list "$allf" | xargs -0 grep -lI -e '' -- 2>/dev/null || true)"
  nonempty="$(nul_list "$allf" | xargs -0 grep -l -e '' -- 2>/dev/null || true)"
fi
ntext="$(printf '%s' "$textf" | grep -c . || true)"

# weight per dir (depth <= 4): text files + binary/8, min 1 when non-empty
# columns: weight, text, binary, depth, path
wts="$( { printf '%s\n' "$textf" | awk 'NF { print "T " $0 }'
          printf '%s\n' "$nonempty" | awk 'NF { print "A " $0 }'; } |
  awk '{ k = substr($0, 1, 1); p = substr($0, 3); n = split(p, s, "/"); d = ""
         for (i = 1; i < n && i <= 4; i++) {
           d = (i == 1 ? s[i] : d "/" s[i]); seen[d] = i
           if (k == "T") t[d]++; else a[d]++ } }
       END { for (d in seen) { b = a[d] - t[d]; if (b < 0) b = 0
               w = t[d] + int(b / 8); if (w < 1) w = 1
               print w "\t" t[d] + 0 "\t" b "\t" seen[d] "\t" d } }' |
  sort -t "$(printf '\t')" -k1,1nr -k4,4nr -k5,5)"

wcol() { # path, column → that dir's weight-table field
  printf '%s\n' "$wts" | awk -F'\t' -v p="$1" -v c="$2" '$5 == p { print $c; exit }'
}
# child dir names of a dir (biggest first); "" means repo root
kids_of() {
  printf '%s\n' "$wts" | awk -F'\t' -v p="$1" '
    NF { q = $5; if (!sub(/\/[^\/]*$/, "", q)) q = ""
         if (q == p) { n = $5; sub(/.*\//, "", n); print n } }'
}

# camelCase/kebab/snake dir name → words
dir_parts() {
  basename "$1" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g; s/[-_.]/ /g' | tr 'A-Z' 'a-z'
}

# derived, not declared: short dir name, distinguishing segment, then a
# deterministic shortening of the name itself. A dominant file token
# mislabels the scope — undici: for .changeset/ is a map that lies
pfx() { # dirname, dirpath, sibling-names...
  local name="$1" sib w n short
  shift 2
  [ "${#name}" -le 8 ] && { printf '%s' "$name"; return; }
  for w in $(dir_parts "$name"); do
    [ "${#w}" -lt 3 ] || [ "${#w}" -gt 8 ] || printf '%s' "$w" | grep -qE "$stop_re" && continue
    n=0
    for sib in "$@"; do
      case " $(dir_parts "$sib") " in *" $w "*) n=$((n+1)) ;; esac
    done
    [ "$n" -le 1 ] && { printf '%s' "$w"; return; }
  done
  [ "${#name}" -le 12 ] && { printf '%s' "$name"; return; }
  # very long name: keep the first char, drop vowels — still the real name
  short="$(printf '%s' "$name" | cut -c1)$(printf '%s' "$name" | cut -c2- | tr -d 'aeiou' | cut -c1-11)"
  printf '%s' "$short"
}

# first meaningful comment line in a file — the module's own doc text.
# comment lines only: strips //, --, #, /*, *, """, ; markers, then drops
# shebangs, preprocessor lines, license headers, and one-word noise
doc_line() {
  grep -qI . "$1" 2>/dev/null || return 0
  head -20 "$1" 2>/dev/null | awk '
    /^[[:space:]]*#!/ { next }
    /^[[:space:]]*#(include|define|if|ifdef|ifndef|elif|else|endif|pragma|error|warning|import|using|region|endregion)/ { next }
    /^[[:space:]]*(\/\/|--|#|\*|\/\*|"""|;)/ {
      line = $0
      sub(/^[[:space:]]*(\/\/+|--+|#+|\*+|\/\*+|"""+|;+)[[:space:]]*/, "", line)
      sub(/[[:space:]]*(\*+\/|"""+)[[:space:]]*$/, "", line)
      low = tolower(line)
      if (low ~ /copyright|licen[cs]e|spdx|vim:|coding[:=]|@file|@brief|@author|generated|do not edit/) next
      an = gsub(/[A-Za-z0-9]/, "&", line)
      if (split(line, w, /[[:space:]]+/) >= 3 && length(line) >= 15 &&
          an >= length(line) * 0.45) { print line; exit }
    }'
}

# names a file advertises: export/pub targets, then defs of any kind —
# real identifiers, no wordlists
syms() {
  { grep -hEo '(local[[:space:]]+)?(async[[:space:]]+)?(function|def|func|fn|sub|class|struct|interface|enum|trait|const|let|var|type|impl)[[:space:]]+[A-Za-z_][A-Za-z0-9_.:]*' "$@"
    grep -hEo '(export|pub)[[:space:]]+(default[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*' "$@"
  } 2>/dev/null | sed -E 's/^.*[[:space:]]//' |
    grep -vE '^(default|async|function|def|func|fn|sub|class|struct|interface|enum|trait|const|let|var|type|impl|export|pub)$' |
    awk '!seen[$0]++' | head -3 | paste -sd, - | sed 's/,/, /g'
}

# a line in an agent doc whose subject is this dir: "- `src/api/`: REST
# handlers", "| `docs/` | guides |". A bare word deep in a line
# (github.com, docs/specs/ui.md) is a mention in passing, never a cell
doc_subject() { # rel, name, doc
  sed -E 's/!?\[([^]]*)\]\([^)]*\)/\1/g' "$3" 2>/dev/null |
  awk -v rel="$1" -v name="$2" '
    { line = $0
      sub(/^[[:space:]]*([-*+>|#]+|[0-9]+[.)])?[[:space:]]*/, "", line)
      wrapped = match(line, /^[*_`]+/); sub(/^[*_`]+/, "", line); sub(/^\.\//, "", line)
      for (k = 1; k <= 2; k++) {
        cand = (k == 1 ? rel : name)
        if (k == 2 && (cand == rel || index(rel, "/") == 0)) break
        if (index(line, cand) != 1) continue
        rest = substr(line, length(cand) + 1); slash = 0
        if (substr(rest, 1, 1) == "/") { slash = 1; rest = substr(rest, 2) }
        if (k == 2 && !slash) continue
        if (substr(rest, 1, 1) ~ /[A-Za-z0-9_.\/-]/) continue
        if (!slash && !wrapped) continue
        sub(/^[*_`]+/, "", rest)
        sub(/^[[:space:]]*((—|–|-|:|\||->|=>)[[:space:]]*)*/, "", rest)
        gsub(/[[:space:]]*\|[[:space:]]*/, ", ", rest)
        # "docs/ the guides, tests/ the suites": stop at the next path
        sub(/[,;][[:space:]]*`?[A-Za-z0-9_.-]+\/.*$/, "", rest); sub(/[[:space:],]+$/, "", rest)
        if (length(rest) >= 8) { print rest; exit }
      }
    }' | head -1
}

# the dir's own words: README first prose line, then a manifest
# description (package.json, pyproject.toml, Cargo.toml)
dir_blurb() { # rel
  local f line
  for f in "$1/README.md" "$1/readme.md" "$1/README"; do
    [ -f "$f" ] || continue
    line="$(sed -E 's/!?\[([^]]*)\]\([^)]*\)/\1/g' "$f" | awk '
      /^[[:space:]]*```/ { fence = !fence; next } fence { next }
      /^[[:space:]]*(#|<|\||!|=|-{3,}|\[)/ { next }
      { sub(/^[[:space:]]*[-*>][[:space:]]*/, "")
        an = gsub(/[A-Za-z0-9]/, "&")
        if (split($0, w, /[[:space:]]+/) >= 3 && an >= length($0) * 0.5) { print; exit } }')"
    [ -n "$line" ] && { printf '%s' "$line"; return; }
  done
  if [ -f "$1/package.json" ]; then
    line="$(sed -n 's/^[[:space:]]*"description"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p' "$1/package.json" | head -1)"
    [ -n "$line" ] && { printf '%s' "$line"; return; }
  fi
  for f in "$1/pyproject.toml" "$1/Cargo.toml"; do
    [ -f "$f" ] || continue
    line="$(sed -n 's/^description[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$f" | head -1)"
    [ -n "$line" ] && { printf '%s' "$line"; return; }
  done
  return 0
}

# seed the 'contains' cell, every step in the codebase's own words:
# agent-doc subject line, the dir's README/manifest, a doc comment from
# a file that speaks for the dir (shares its name, or is its entry
# file), exported symbols, any doc comment, then bare file names
desc_for() { # name, rel
  local name="$1" rel="$2" doc line list pref f sample symtext names
  for doc in AGENTS.md CLAUDE.md README.md; do
    [ -f "$doc" ] || continue
    line="$(doc_subject "$rel" "$name" "$doc")"
    [ -n "$line" ] && { printf '%s' "$line"; return; }
  done
  line="$(dir_blurb "$rel")"
  [ -n "$line" ] && { printf '%s' "$line"; return; }
  # text files under the dir, shallow first so the dir's own files speak
  # before deep leaves; line-wise so a spaced path stays one name
  list="$(printf '%s\n' "$textf" | awk -v p="$rel/" 'index($0, p) == 1 && $0 !~ /\.min\./ {
      x = $0; print gsub(/\//, "/", x) "\t" $0 }' | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2- | head -200)"
  pref="$(printf '%s\n' "$list" | awk -v n="$(printf '%s' "$name" | tr 'A-Z' 'a-z')" '
      NF { b = $0; sub(/.*\//, "", b); lb = tolower(b)
           if (index(lb, n) || lb ~ /^(index|main|mod|lib|init|__init__)\./) print }' | head -6)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sample="$(doc_line "$f" | cut -c1-72)"
    if [ -n "$sample" ]; then printf '%s' "$sample"; return; fi
  done <<EOF
$pref
EOF
  sfiles=()
  while IFS= read -r f; do [ -n "$f" ] && sfiles+=("$f"); done <<EOF
$(printf '%s\n' "$pref" "$list" | awk 'NF' | grep -E "$code_re" | awk '!seen[$0]++' | head -8)
EOF
  symtext=""
  [ "${#sfiles[@]}" -gt 0 ] && symtext="$(syms "${sfiles[@]}" 2>/dev/null | head -1)"
  if [ -n "$symtext" ]; then printf 'exports %s' "$symtext"; return; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sample="$(doc_line "$f" | cut -c1-72)"
    if [ -n "$sample" ]; then printf '%s' "$sample"; return; fi
  done <<EOF
$(printf '%s\n' "$list" | head -6)
EOF
  names="$(printf '%s\n' "$allf" | awk -v p="$rel/" 'index($0, p) == 1' | head -60 |
    sed 's|.*/||; s/\.[^.]*$//' | sort -u | head -3 | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$names" ]; then printf 'files like %s' "$names"; return; fi
  printf 'undocumented: what lives here'
}

# newline lists matched literally — a case-glob test would let the * and
# ** inside a stored scope match other entries and silently drop rows
listed() { printf '%s' "$1" | grep -Fxq -- "$2"; }

cell() { tr -d '|\r' | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//'; }

used_pfx="" ptag=()
emit() { # depth, rel
  local lvl="$1" rel="$2" name p key parent="" indent="" i t b n subs cont names
  name="$(basename "$rel")"; name="${name#.}"
  [ "$lvl" -gt 0 ] && parent="${ptag[$((lvl - 1))]}"
  i=0; while [ "$i" -lt "$lvl" ]; do indent="$indent  "; i=$((i + 1)); done
  sibs=()
  while IFS= read -r n; do [ -n "$n" ] && sibs+=("${n#.}"); done <<EOF
$(kids_of "$(case "$rel" in */*) printf '%s' "${rel%/*}" ;; esac)")
EOF
  p="$(pfx "$name" "$rel" ${sibs[@]+"${sibs[@]}"})"
  p="$(printf '%s' "$p" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//')"
  [ -n "$p" ] || p="dir"
  # prefixes need only be unique within their parent level: nested
  # checkout: under payments: and orders: reads orders:checkout: vs
  # payments:checkout:. A same-named top-level pair (src/core, lib/core)
  # qualifies with its top dir instead of a draft todo- prefix
  key="${parent:-top}:$p"
  if listed "$used_pfx" "$key"; then
    case "$rel" in */*) p="$(printf '%s' "${rel%%/*}" | tr 'A-Z' 'a-z' | sed 's/^\.//')-$p" ;; esac
  fi
  listed "$used_pfx" "${parent:-top}:$p" && p="todo-$p"
  used_pfx="$used_pfx${parent:-top}:$p
"
  ptag[$lvl]="${parent:+$parent:}$p"
  rows=$((rows + 1))
  t="$(wcol "$rel" 2)"; b="$(wcol "$rel" 3)"
  n=$((t + b))
  if [ "$b" -gt "$t" ]; then
    names="$(printf '%s\n' "$allf" | awk -v p="$rel/" 'index($0, p) == 1' | head -40 |
      sed 's|.*/||; s/\.[^.]*$//' | sort -u | head -3 | paste -sd, - | sed 's/,/, /g' | cell)"
    printf '| %s%s: | %s/** | names only, binary assets: %s |\n' "$indent" "$p" "$rel" "${names:-files}"
    return
  fi
  cont="$(desc_for "$name" "$rel" | cell | cut -c1-80)"
  # size and the biggest subdirs without a row: what a search here will
  # cost, and where inside it to look next
  if [ "$n" -ge 10 ]; then
    subs="$(kids_of "$rel" | while IFS= read -r k; do
        listed "$selected" "$rel/$k" || printf '%s/\n' "$k"; done | head -3 |
      paste -sd, - | sed 's/,/, /g' | cell)"
    cont="$cont ($n files${subs:+; $subs})"
  fi
  printf '| %s%s: | %s/** | %s |\n' "$indent" "$p" "$rel" "$cont"
}

# unique repo qualifier for multi-codebase contexts: from the git remote,
# else the directory name
remote="$(git remote get-url origin 2>/dev/null || true)"
slug="$(basename "${remote:-$root}" .git | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"

# files at repo root are a distinct intent: config, manifests, docs,
# except lockfiles, which are generated output and search-poison
rf="$(printf '%s\n' "$allf" | awk 'NF && index($0, "/") == 0 && substr($0, 1, 1) != "."' | sort)"
rlist=""
while IFS= read -r f; do
  case "$f" in
    ''|package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|go.sum|uv.lock|Gemfile.lock|composer.lock|bun.lockb|*.lock) continue ;;
  esac
  rlist="$rlist$f
"
done <<< "$rf"

entries=""
for f in src/main.* src/index.* src/cli.* main.* index.* cli.*; do
  [ -f "$f" ] || continue
  entries="${entries:+$entries, }$f"
done

# jumbo source files: a >3k-line file is too big to read even when the
# namespace scoped correctly; it earns a row with declaration landmarks.
# Source extensions only: notices, data dumps, scene files, and docs are
# not navigation targets, and neither are test files
jumbos=""
cand="$(printf '%s\n' "$textf" | grep -E "$code_re" |
  grep -vE '\.min\.[^.]+$|(__snapshots__|(^|/)snapshots?/|(^|/)baselines?/|(^|/)fixtures?/|\.baseline)' |
  grep -vE '(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*$|[._-](test|spec)\.[^/]*$' || true)"
if [ -n "$cand" ]; then
  jumbos="$(nul_list "$cand" | xargs -0 wc -l 2>/dev/null | sort -rn |
    awk '$2 != "total" && $1 > 3000 { c = $1; $1 = ""; sub(/^ +/, ""); print c "\t" $0 }' | head -2)" || true
fi

reserve=0
[ -n "$rlist" ] && reserve=$((reserve + 1))
[ -n "$entries" ] && reserve=$((reserve + 1))
njumbo=0
[ -n "$jumbos" ] && njumbo="$(printf '%s\n' "$jumbos" | grep -c .)"
reserve=$((reserve + njumbo))
dir_budget=$((max_rows - reserve))

# --- greedy row selection --------------------------------------------
# heaviest first. A dir earns a row when it is top-level or holds at
# least 2% of the repo's text files. It is skipped when it is >=90% of
# the row that already contains it (no new scoping power), when it sits
# in a binary-asset row (names-only rows never split), or when one child
# holds >=90% of it: that chain collapses and the child takes the row.
thr=$((ntext / 50)); [ "$thr" -ge 1 ] || thr=1
cont_re='^(src|lib|libs|app|apps|packages|services|modules|crates|cmd|internal|pkg|plugins|components|server)$'
plan="$(printf '%s\n' "$wts" | awk -F'\t' -v budget="$dir_budget" -v thr="$thr" -v cont="$cont_re" '
  function par(p,   q) { q = p; if (sub(/\/[^\/]*$/, "", q)) return q; return "" }
  function anc(p,   q) { q = par(p); while (q != "") { if (q in sel) return q; q = par(q) } return "" }
  # a container dir (src/, services/, packages/) is plumbing, not a
  # subject: its child rows sit beside it, so tags read auth:, not
  # src:auth:, and the container row still covers its loose files
  function dfs(node, lvl,   i, c) {
    for (i = 1; i <= n; i++) { c = o[i]
      if ((c in sel) && sa[c] == node) { print lvl "\t" c
        dfs(c, (d[c] == 1 && c ~ cont && haskid(c)) ? lvl : lvl + 1) } } }
  function haskid(p,   s) { for (s in sel) if (sa[s] == p) return 1; return 0 }
  NF { w[$5] = $1; t[$5] = $2; b[$5] = $3; d[$5] = $4; o[++n] = $5
       q = par($5); if (q != "" && $1 + 0 > mk[q] + 0) mk[q] = $1 + 0 }
  function run(budget,   i, j, c, a, cnt) {
    delete sel; delete promo; cnt = 0
    for (i = 1; i <= n; i++) { c = o[i]
      if (d[c] > 3) continue
      if (d[c] > 1 && w[c] < thr && !(c in promo)) continue
      a = anc(c)
      if (a != "" && (b[a] > t[a] || w[c] >= 0.9 * w[a])) continue
      if (d[c] < 3 && b[c] <= t[c] && mk[c] >= 0.9 * w[c] && w[c] > 2 * thr) {
        for (j = 1; j <= n; j++) if (par(o[j]) == c && w[o[j]] >= 0.9 * w[c]) promo[o[j]]
        continue
      }
      if (cnt >= budget) continue
      sel[c]; cnt++
    }
    nu = 0
    for (i = 1; i <= n; i++) { c = o[i]; if (d[c] != 1 || (c in sel)) continue
      cov = 0; for (s in sel) if (index(s, c "/") == 1) { cov = 1; break }
      if (!cov) un[++nu] = c }
  }
  END {
    # top dirs left without a row share one misc row, so a root search
    # is never the only way in; that row costs a dir row
    run(budget); if (nu > 0) run(budget - 1)
    for (c in sel) sa[c] = anc(c)
    dfs("", 0)
    for (i = 1; i <= nu; i++) print "U\t" un[i]
  }')"
selected="$(printf '%s\n' "$plan" | awk -F'\t' '$1 != "U" { print $2 }')"
unmapped="$(printf '%s\n' "$plan" | awk -F'\t' '$1 == "U" { print $2 }')"

{
  echo '# namespaces'
  echo "repo: $slug"
  echo
  echo '| prefix | scope | contains |'
  echo '|--------|-------|----------|'

  while IFS=$'\t' read -r lvl rel; do
    [ -n "${rel:-}" ] && [ "$lvl" != U ] || continue
    emit "$lvl" "$rel"
  done <<< "$plan"

  # small top dirs without a row share one row, biggest first; past 12
  # scopes the rest go to the unmapped footer
  rest=""
  if [ -n "$unmapped" ]; then
    mp=misc
    listed "$used_pfx" "top:$mp" && mp=other
    listed "$used_pfx" "top:$mp" && mp=todo-misc
    used_pfx="$used_pfx
top:$mp"
    mscope="$(printf '%s\n' "$unmapped" | head -12 | sed 's|$|/**|' | paste -sd, - | sed 's/,/, /g')"
    mn=0
    while IFS= read -r u; do
      [ -n "$u" ] && mn=$((mn + $(wcol "$u" 2) + $(wcol "$u" 3)))
    done <<< "$(printf '%s\n' "$unmapped" | head -12)"
    rest="$(printf '%s\n' "$unmapped" | sed -n '13,$p')"
    rows=$((rows + 1))
    printf '| %s: | %s | smaller top-level dirs, no row of their own (%s files): search one by path |\n' "$mp" "$mscope" "$mn"
  fi

  # root files, one row. Compress to *.ext when 3+ share an extension
  # and no lockfile shares it; the row is read in every session
  if [ -n "$rlist" ]; then
    rscope="$( { printf '%s\n' "$rf" | sed 's/^/A /'; printf '%s' "$rlist" | sed 's/^/K /'; } | awk '
      function ext(f,   e) { e = f; if (index(f, ".") > 1 && sub(/^.*\./, "", e)) return e; return "" }
      { k = substr($0, 1, 1); f = substr($0, 3); if (f == "") next; e = ext(f)
        if (k == "A") { if (e != "") tot[e]++; next }
        m++; fs[m] = f; ex[m] = e; if (e != "") kk[e]++ }
      END { for (i = 1; i <= m; i++) { e = ex[i]
              if (e != "" && kk[e] >= (m > 8 ? 2 : 3) && kk[e] == tot[e]) {
                if (!(e in done)) { done[e]; out = out (out != "" ? ", " : "") "*." e } }
              else out = out (out != "" ? ", " : "") fs[i] }
            print out }')"
    alldoc=1
    while IFS= read -r f; do
      case "$f" in ''|*.md|*.txt|*.rst|*.adoc|LICENSE*|COPYING*) ;; *) alldoc=0 ;; esac
    done <<< "$rlist"
    [ "$alldoc" -eq 1 ] && rp="doc" || rp="cfg"
    listed "$used_pfx" "top:$rp" && rp="root"
    listed "$used_pfx" "top:$rp" && rp="todo-$rp"
    used_pfx="$used_pfx
top:$rp"
    rows=$((rows + 1))
    if [ "$alldoc" -eq 1 ]; then
      printf '| %s: | %s | docs at repo root |\n' "$rp" "$rscope"
    else
      printf '| %s: | %s | config, manifests, docs at repo root |\n' "$rp" "$rscope"
    fi
  fi

  # jumbo files get their own rows with declaration landmarks. Line
  # numbers drift, so they are entry points, not gospel
  if [ -n "$jumbos" ]; then
    while IFS=$'\t' read -r cnt jf; do
      [ -n "${jf:-}" ] || continue
      stem="$(basename "$jf")"; stem="$(printf '%s' "${stem%.*}" | tr 'A-Z' 'a-z')"
      jp="$(pfx "$stem" "$jf" || true)"
      jp="$(printf '%s' "$jp" | tr -c 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//')"
      [ -n "$jp" ] || jp="file"
      if listed "$used_pfx" "top:$jp"; then
        jp="$(printf '%s' "$stem" | tr -c 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-24)"
        listed "$used_pfx" "top:$jp" && continue
      fi
      used_pfx="$used_pfx
top:$jp"
      marks="$(grep -nE '^[[:space:]]*((export|async|pub|local|static|final|private|public)[[:space:]]+)*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+[A-Za-z_]' "$jf" 2>/dev/null |
        sed -nE 's/^([0-9]+):.*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3@\1/p' |
        head -5 | paste -sd, - | sed 's/,/, /g')" || true
      cont="~$((cnt / 1000))k lines"
      [ -n "$marks" ] && cont="$cont: $marks" || true
      rows=$((rows + 1))
      printf '| %s: | %s | %s |\n' "$jp" "$jf" "$cont"
    done <<< "$jumbos"
  fi

  # well-known entry files are a distinct search intent: a real boot/
  # dir claims boot: first, entry: is the fallback
  if [ -n "$entries" ]; then
    bp=""
    for c in boot entry; do
      listed "$used_pfx" "top:$c" || { bp="$c"; break; }
    done
    [ -n "$bp" ] || bp="todo-boot"
    rows=$((rows + 1))
    echo "| $bp: | $entries | entry points, boot wiring |"
  fi

  # the row cap must be visible: silent truncation looks like a complete
  # map. Biggest first, capped, since the footer rides in every session
  if [ -n "$rest" ]; then
    nun="$(printf '%s\n' "$rest" | grep -c .)"
    shown="$(printf '%s\n' "$rest" | head -8 | paste -sd, - | sed 's/,/, /g')"
    [ "$nun" -gt 8 ] && shown="$shown, +$((nun - 8)) more"
    echo
    echo "unmapped: $shown (capped at $max_rows rows: raise the cap or fold into a parent scope)"
  fi
} > "$out"

if [ -n "$rest" ]; then
  echo "note: capped at $max_rows rows; unmapped dirs: $(sed -n 's/^unmapped: \(.*\) (capped.*/\1/p' "$out")" >&2
fi

drafts=$(grep -cE 'todo-|undocumented' "$out" || true)
echo "wrote $out · $rows namespaces, $drafts rows needing a human pass" >&2
if [ "$nfiles" -lt 100 ]; then
  echo "note: ~$nfiles files; under ~100 the map is marginal; scope by dir names" >&2
fi

#!/usr/bin/env bash
# Scaffold .prefixer/namespaces.md from a repo's layout.
# Prefixes are derived from the codebase's own vocabulary (distinguishing
# dir-name segments, dominant file-name tokens); contains cells come from
# agent docs, then a sample of real file contents (doc comments, exported
# symbols), then bare file names. Descends into code-bearing dirs
# (src/lib/app/monorepo parents) and one level deeper where a child holds
# sub-teams; nested rows compose parent:child: tags. Also maps
# non-generated dot dirs, the files at repo root, and jumbo files
# (>3k lines) that defeat directory scoping.
# usage: init_namespaces.sh [repo-root]
set -euo pipefail

root="${1:-.}"
out="$root/.prefixer/namespaces.md"

if [ -f "$out" ]; then
  echo "$out already exists; edit the stale rows, never regenerate" >&2
  exit 1
fi

mkdir -p "$root/.prefixer"
grep -qx 'metrics.jsonl' "$root/.prefixer/.gitignore" 2>/dev/null ||
  echo 'metrics.jsonl' >> "$root/.prefixer/.gitignore"

here="$(cd "$(dirname "$0")" && pwd)"
# exclusion list + skipped_gen: scripts/lib_scope.sh (single copy)
. "$here/lib_scope.sh"

# generated dirs inflate this count and misjudge the marginal-map note —
# prune them, plus dot dirs, before counting real files
nameargs=()
for s in $PREFIXER_SKIP; do nameargs+=(-o -name "$s"); done
files=$(find "$root" \( -type d \( "${nameargs[@]:1}" \) -prune \) -o \
  -type f -not -path '*/.*' -print 2>/dev/null | wc -l | tr -d ' ')

# non-semantic words that appear in every repo — never a prefix
stop_re='^(index|main|mod|init|utils?|helpers?|common|shared|base|file|code|misc|tmp|temp|readme|license|package)$'

max_rows=12 rows=0

# an empty dir scopes nothing — skip it rather than emit a dead row
has_files() { find "$1" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -print -quit 2>/dev/null | grep -q .; }

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

# asset dirs hold mostly binary content — a content grep there is noise;
# the useful search is names/inventory, and the map should say so
is_binary_dir() { # dirpath → 0 if at least half the files are binary
  local files total text
  files="$(find "$1" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -print0 2>/dev/null |
    tr '\0' '\n' | head -40 || true)"
  [ -n "$files" ] || return 1
  total="$(printf '%s\n' "$files" | grep -c .)"
  text="$(printf '%s\n' "$files" | tr '\n' '\0' |
    xargs -0 grep -lI '' 2>/dev/null | grep -c . || true)"
  [ "${text:-0}" -le $((total / 2)) ]
}

# seed the 'contains' cell: agent-doc mention, then a sample of real file
# contents (doc comment, exported symbols), then the bare file names —
# every step derived from the codebase's own words
desc_for() { # dirname, dirpath
  local doc line names sample symtext list pref f
  for doc in AGENTS.md CLAUDE.md README.md; do
    [ -f "$root/$doc" ] || continue
    # the first whole-word hit is usually a badge, a link, or ASCII art —
    # skip link markup and lines that are mostly punctuation. Then rank:
    # a 'name/' path mention early in the line is the dir being described;
    # a bare word deep in a line (github.com, public/sprites/) is a
    # mention in passing — prefer subject lines, fall back to earliest hit
    line="$(grep -F -- "$1" "$root/$doc" 2>/dev/null |
      grep -vF '](' |
      awk '{ an=gsub(/[A-Za-z0-9]/,"&"); if (an >= length($0)*0.45) print }' |
      awk -v n="$1" '
        { p = index($0, n "/")
          if (p) { print "0", p, $0; next }
          p = index($0, n)
          if (p) print "1", p, $0 }' |
      sort -k1,1n -k2,2n | head -1 | cut -d' ' -f3- |
      sed 's/^[#*|> 	-]*//' | cut -c1-72)"
    if [ -n "$line" ]; then printf '%s' "$line"; return; fi
  done
  # representative files: name-sharing first (auth/AuthService.ts speaks
  # for auth/), then the rest — deterministic order for a stable map.
  # line-wise reads throughout: a spaced path must stay one filename
  list="$(find "$2" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -not -name '*.min.*' -print 2>/dev/null | sort | head -60)"
  pref="$(printf '%s\n' "$list" | grep -iF -- "$1" 2>/dev/null | head -6)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sample="$(doc_line "$f" | cut -c1-72)"
    if [ -n "$sample" ]; then printf '%s' "$sample"; return; fi
  done <<EOF
$(printf '%s\n' "$pref"; printf '%s\n' "$list" | grep -ivF -- "$1" 2>/dev/null | head -6)
EOF
  sfiles=()
  while IFS= read -r f; do [ -n "$f" ] && sfiles+=("$f"); done <<EOF
$(printf '%s\n' "$pref" "$list" | awk 'NF' | awk '!seen[$0]++')
EOF
  symtext=""
  [ "${#sfiles[@]}" -gt 0 ] &&
    symtext="$(syms "${sfiles[@]:0:8}" 2>/dev/null | head -1)"
  if [ -n "$symtext" ]; then printf 'exports %s' "$symtext"; return; fi
  names="$(printf '%s\n' "$list" | head -60 | sed 's|.*/||; s/\.[^.]*$//' |
    sort -u | head -3 | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$names" ]; then printf 'files like %s' "$names"; return; fi
  printf 'undocumented: what lives here'
}

# newline lists matched literally — a case-glob test would let the * and
# ** inside a stored scope match other entries and silently drop rows
listed() { printf '%s' "$1" | grep -Fxq -- "$2"; }

seen="" used_pfx="" last_pfx=""
emit() { # dirname, scope, dirpath, parent-prefix, indent, sibling-names...
  local name="$1" scope="$2" path="$3" parent="$4" indent="$5" p names
  shift 5
  # scopes repeat across parents — dedupe by scope, not name
  listed "$seen" "$scope" && return
  has_files "$path" || return 0
  seen="$seen$scope
"
  rows=$((rows + 1))
  p="$(pfx "$name" "$path" "$@")"
  p="${p// /-}"   # prefixes are tags, not display names — no spaces
  # prefixes need only be unique within their parent level — a nested
  # checkout: under payments: and orders: reads orders:checkout: vs
  # payments:checkout:, already distinct. Flat rows all share the top
  # level though, so a same-named child under two parents collides on
  # display — qualify it with its parent dir (plugins/claude-api →
  # plugins-claude-api) rather than emitting a draft todo- prefix
  key="${parent:-top}:$p"
  if listed "$used_pfx" "$key"; then
    stem="${scope%/\*\*}"
    case "$stem" in
      */*) p="${stem%%/*}-$name" ;;
      *)   p="$stem" ;;
    esac
  fi
  listed "$used_pfx" "${parent:-top}:$p" && p="todo-$name"
  used_pfx="$used_pfx${parent:-top}:$p
"
  last_pfx="$p"
  if is_binary_dir "$path"; then
    names="$(find "$path" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -print 2>/dev/null | head -40 |
      sed 's|.*/||; s/\.[^.]*$//' | sort -u | head -3 | paste -sd, - |
      sed 's/,/, /g' | tr -d '|\r')"
    printf '| %s%s: | %s | names only, binary assets: %s |\n' "$indent" "$p" "$scope" "${names:-files}"
    return
  fi
  # contains goes into a table cell — pipes make phantom cells, CRs make
  # phantom line breaks; both corrupt the map for every consumer
  printf '| %s%s: | %s | %s |\n' "$indent" "$p" "$scope" "$(desc_for "$name" "$path" |
    tr -d '|\r' | tr '\n' ' ' | sed 's/  */ /g; s/ *$//')"
}

# unique repo qualifier for multi-codebase contexts — from the git remote,
# else the directory name
remote="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
slug="$(basename "${remote:-$(cd "$root" && pwd)}" .git | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"

# synthetic rows below reserve budget inside the 12-row cap — they are
# high-intent (config, entry points, jumbo navigation), so dir rows give
# way before these do
rf="$(find "$root" -maxdepth 1 -type f -not -name '.*' 2>/dev/null | sort)"

entries=""
for f in "$root"/src/main.* "$root"/src/index.* "$root"/src/cli.* \
         "$root"/main.* "$root"/index.* "$root"/cli.*; do
  [ -f "$f" ] || continue
  entries="${entries:+$entries, }${f#"$root"/}"
done

# jumbo files: a >3k-line file is too big to read even when the namespace
# scoped correctly — it earns its own row with declaration landmarks.
# data/generated heavies (lockfiles, snapshots, baselines, docs, dumps)
# crowd out real jumbo source, so they are excluded before ranking
jumbos=""
cand="$(find "$root" -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null |
  grep -vE '/(dist|build|target|coverage|out|__pycache__|venv|bin|obj|storybook-static|DerivedData|Pods)/|/[^/]+-out/' |
  grep -vEi '\.(lock|sum|txt|json|jsonc|ya?ml|toml|csv|tsv|xml|html?|css|svg|map|snap|out|log|diff|patch|bin|dat|db|sqlite|ico|png|jpe?g|gif|webp|woff2?|ttf|eot|pdf|zip|gz|tar)$|\.min\.[^.]+$|(__snapshots__|/snapshots?/|/baselines?/|/fixtures?/|\.baseline)' || true)"
# the extension list can't name every binary — a .wasm or atlas full of
# 0x0A bytes fakes a huge line count; grep -I keeps candidates to text
if [ -n "$cand" ]; then
  cand="$(printf '%s\n' "$cand" | tr '\n' '\0' | xargs -0 grep -lI '' 2>/dev/null || true)"
fi
if [ -n "$cand" ]; then
  jumbos="$(printf '%s\n' "$cand" | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null | sort -rn |
    awk '$2 != "total" && $1 > 3000 { c=$1; $1=""; sub(/^ +/,""); print c "\t" $0 }')" || true
fi

reserve=0
[ -n "$rf" ] && reserve=$((reserve + 1))
[ -n "$entries" ] && reserve=$((reserve + 1))
njumbo=0
[ -n "$jumbos" ] && njumbo="$(printf '%s\n' "$jumbos" | grep -c .)"
[ "$njumbo" -gt 2 ] && njumbo=2
reserve=$((reserve + njumbo))
dir_budget=$((max_rows - reserve))

{
  echo '# namespaces'
  echo "repo: $slug"
  echo
  echo '| prefix | scope | contains |'
  echo '|--------|-------|----------|'

  # top level includes non-generated dot dirs (.github, .devin, tooling
  # dirs are real search intents); the leading dot is stripped for the
  # prefix, kept in the scope. Names are arrays — a spaced dir name must
  # stay one name, not two tokens.
  topnames=()
  for d in "$root"/*/ "$root"/.[!.]*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    skipped_gen "$name" && continue
    topnames+=("$name")
  done
  # descend into dirs that hold most of a repo's code, then one level
  # deeper where a child holds sub-teams (payments → checkout, refunds).
  # parents: the usual code homes, the project-named dir (django/django),
  # and any top dir holding >=3 code-bearing child dirs (workspaces like
  # crates/, Go layouts like cmd/+internal/+pkg/, plugin trees)
  parents="src lib app packages apps services modules libs crates cmd internal pkg plugins themes components tools server"
  case " $parents " in *" $slug "*) ;; *) parents="$parents $slug" ;; esac
  for name in ${topnames[@]+"${topnames[@]}"}; do
    case " $parents " in *" $name "*) continue ;; esac
    kc=0
    for d in "$root/$name"/*/; do
      [ -d "$d" ] || continue
      skipped_gen "$(basename "$d")" && continue
      has_files "$d" && kc=$((kc+1))
    done
    [ "$kc" -ge 3 ] && parents="$parents $name"
  done

  # children of code-bearing parents get a guaranteed share of the row
  # budget — a top-dirs-only pass starved exactly the split a searcher
  # needs most (src/core losing its row to .playwright-cli). Parents go
  # biggest-first so the dir holding most code subdivides first;
  # round-robin across parents keeps one fat parent from taking every
  # child slot.
  kids_of() { # dir — eligible child dir names, one per line
    local d
    for d in "$root/$1"/*/; do
      [ -d "$d" ] || continue
      skipped_gen "$(basename "$d")" && continue
      basename "$d"
    done
  }
  nkids=0 plist=""
  for parent in $parents; do
    [ -d "$root/$parent" ] || continue
    plist="$plist$(find "$root/$parent" "${GEN_PRUNE[@]}" -o -type f -not -name '.*' -print 2>/dev/null | grep -c .) $parent
"
    while IFS= read -r kn; do
      [ -n "$kn" ] && has_files "$root/$parent/$kn" && nkids=$((nkids+1))
    done <<< "$(kids_of "$parent")"
  done
  child_budget=$((dir_budget / 2))
  [ "$child_budget" -gt "$nkids" ] && child_budget=$nkids
  top_budget=$((dir_budget - child_budget))

  # top dirs that miss their share are decided after the child pass —
  # a child row covers part of the dir, so "unmapped" would lie
  unmapped="" tdefer=""
  for name in ${topnames[@]+"${topnames[@]}"}; do
    if [ "$rows" -ge "$top_budget" ]; then
      tdefer="$tdefer$name
"; continue
    fi
    emit "${name#.}" "$name/**" "$root/$name" "" "" ${topnames[@]+"${topnames[@]}"}
  done

  psorted="$(printf '%s' "$plist" | sort -rn | sed 's/^[0-9]* //')"
  while [ "$rows" -lt "$dir_budget" ]; do
    progress=0
    for parent in $psorted; do
      [ "$rows" -ge "$dir_budget" ] && break
      kids=()
      while IFS= read -r kn; do [ -n "$kn" ] && kids+=("$kn"); done <<< "$(kids_of "$parent")"
      child=""
      for kn in ${kids[@]+"${kids[@]}"}; do
        listed "$seen" "$parent/$kn/**" && continue
        has_files "$root/$parent/$kn" || continue
        child="$kn"; break
      done
      [ -n "$child" ] || continue
      emit "$child" "$parent/$child/**" "$root/$parent/$child" "" "" ${kids[@]+"${kids[@]}"}
      progress=1
      cp="$last_pfx"
      gkids=()
      while IFS= read -r gn; do [ -n "$gn" ] && gkids+=("$gn"); done <<< "$(kids_of "$parent/$child")"
      [ "${#gkids[@]}" -ge 2 ] || continue
      for g in ${gkids[@]+"${gkids[@]}"}; do
        [ "$rows" -ge "$dir_budget" ] && break
        emit "$g" "$parent/$child/$g/**" "$root/$parent/$child/$g" "$cp" "  " ${gkids[@]+"${gkids[@]}"}
      done
    done
    [ "$progress" -eq 0 ] && break
  done

  # eligible rows the budget skipped get named, never silently dropped —
  # a lone gkid never earns a row, so only 2+-gkid children list theirs.
  # a dir whose descendants earned rows is covered, not unmapped
  nl='
'
  mark_unmapped() { # scope path relative to root
    listed "$seen" "$1/**" && return 0
    case "$seen" in "$1/"* | *"$nl$1/"*) return 0 ;; esac
    has_files "$root/$1" || return 0
    unmapped="${unmapped:+$unmapped, }$1"
  }
  while IFS= read -r name; do
    [ -n "$name" ] && mark_unmapped "$name"
  done <<< "$tdefer"
  for parent in $psorted; do
    while IFS= read -r kn; do
      [ -n "$kn" ] || continue
      mark_unmapped "$parent/$kn"
      [ "$(kids_of "$parent/$kn" | grep -c .)" -lt 2 ] && continue
      while IFS= read -r gn; do
        [ -n "$gn" ] || continue
        mark_unmapped "$parent/$kn/$gn"
      done <<< "$(kids_of "$parent/$kn")"
    done <<< "$(kids_of "$parent")"
  done

  # files at repo root are a distinct intent: config, manifests, docs —
  # except lockfiles, which are generated output and search-poison
  if [ -n "$rf" ]; then
    rscope="" alldoc=1
    while IFS= read -r f; do
      rel="${f#"$root"/}"
      case "$rel" in
        package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Pipfile.lock|go.sum|uv.lock|Gemfile.lock|composer.lock|*.lock) continue ;;
      esac
      case "$rel" in *.md|*.txt|*.rst|*.adoc) ;; *) alldoc=0 ;; esac
      rscope="${rscope:+$rscope, }$rel"
    done <<< "$rf"
    [ "$alldoc" -eq 1 ] && rp="doc" || rp="cfg"
    listed "$used_pfx" "top:$rp" && rp="todo-$rp"
    used_pfx="$used_pfx
top:$rp"
    if [ -n "$rscope" ]; then
      rows=$((rows + 1))
      if [ "$alldoc" -eq 1 ]; then
        printf '| %s: | %s | docs at repo root |\n' "$rp" "$rscope"
      else
        printf '| %s: | %s | config, manifests, docs at repo root |\n' "$rp" "$rscope"
      fi
    fi
  fi

  # jumbo files get their own rows with declaration landmarks — line
  # numbers drift, so they are entry points, not gospel
  if [ -n "$jumbos" ]; then
    n=0
    while IFS=$'\t' read -r cnt jf; do
      [ "$n" -ge 2 ] && break
      rel="${jf#"$root"/}"
      stem="$(basename "$jf")"; stem="$(printf '%s' "${stem%.*}" | tr 'A-Z' 'a-z')"
      jp="$(pfx "$stem" "$jf" || true)"; [ -n "$jp" ] || jp="file"
      listed "$used_pfx" "top:$jp" && continue
      used_pfx="$used_pfx
top:$jp"
      marks="$(grep -nE '^[[:space:]]*((export|async|pub|local|static|final|private|public)[[:space:]]+)*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+[A-Za-z_]' "$jf" 2>/dev/null |
        sed -nE 's/^([0-9]+):.*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3@\1/p' |
        head -5 | paste -sd, - | sed 's/,/, /g')" || true
      cont="~$((cnt / 1000))k lines"
      [ -n "$marks" ] && cont="$cont: $marks" || true
      rows=$((rows + 1)); n=$((n + 1))
      printf '| %s: | %s | %s |\n' "$jp" "$rel" "$cont"
    done <<< "$jumbos"
  fi

  # well-known entry files are a distinct search intent — dedupe the tag
  # like the cfg row does: a real boot/ dir claims boot: first, entry: is
  # the fallback, and only a double collision stays a draft
  if [ -n "$entries" ]; then
    bp=""
    for cand in boot entry; do
      listed "$used_pfx" "top:$cand" || { bp="$cand"; break; }
    done
    [ -n "$bp" ] || bp="todo-boot"
    used_pfx="$used_pfx
top:$bp"
    rows=$((rows + 1))
    echo "| $bp: | $entries | entry points, boot wiring |"
  fi
} > "$out"

# the 12-row cap must be visible — silent truncation looks like a
# complete map and hides the draft work a human still owes
if [ -n "$unmapped" ]; then
  echo >> "$out"
  echo "unmapped: $unmapped (capped at $max_rows rows: raise the cap or fold into a parent scope)" >> "$out"
  echo "note: capped at $max_rows rows; unmapped dirs: $unmapped" >&2
fi

drafts=$(grep -cE 'todo-|undocumented' "$out" || true)
echo "wrote $out · $rows namespaces, $drafts rows needing a human pass" >&2
if [ "$files" -lt 100 ]; then
  echo "note: ~$files files; under ~100 the map is marginal; scope by dir names" >&2
fi

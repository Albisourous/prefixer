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

files=$(find "$root" -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null | wc -l | tr -d ' ')

skip="node_modules vendor dist build target out .git .prefixer __pycache__ .next .cache venv .venv .idea .vscode coverage .turbo .output .nuxt .svelte-kit storybook-static DerivedData Pods bin obj"

# non-semantic words that appear in every repo — never a prefix
stop_re='^(index|main|mod|init|utils?|helpers?|common|shared|base|file|code|misc|tmp|temp|readme|license|package)$'

max_rows=12 rows=0

skipped_gen() { case " $skip " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

# an empty dir scopes nothing — skip it rather than emit a dead row
has_files() { find "$1" -type f -not -name '.*' -print -quit 2>/dev/null | grep -q .; }

# camelCase/kebab/snake dir name → words
dir_parts() {
  basename "$1" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g; s/[-_.]/ /g' | tr 'A-Z' 'a-z'
}

# most frequent meaningful word in the file basenames under $1
file_token() {
  find "$1" -type f -not -name '.*' 2>/dev/null | head -400 | xargs -n1 basename 2>/dev/null |
    sed 's/\.[^.]*$//; s/\([a-z0-9]\)\([A-Z]\)/\1 \2/g; s/[-_.]/ /g' |
    tr 'A-Z' 'a-z' | tr ' ' '\n' |
    grep -vE "$stop_re" | awk 'length($0)>=3' |
    sort | uniq -c | sort -rn | awk 'NR==1{print $2}'
}

# derived, not declared: short dir name, distinguishing segment, dominant
# file token, then the full name — there is always a real name to propose
pfx() { # dirname, dirpath, sibling-names...
  local name="$1" path="$2" sib w n tok
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
  tok="$(file_token "$path" || true)"
  [ -n "$tok" ] && { printf '%s' "$tok" | cut -c1-8; return; }
  printf '%s' "$name"
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
      if (split(line, w, /[[:space:]]+/) >= 3 && length(line) >= 15) { print line; exit }
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

# seed the 'contains' cell: agent-doc mention, then a sample of real file
# contents (doc comment, exported symbols), then the bare file names —
# every step derived from the codebase's own words
desc_for() { # dirname, dirpath
  local doc line names sample symtext list pref f
  for doc in AGENTS.md CLAUDE.md README.md; do
    [ -f "$root/$doc" ] || continue
    line="$(grep -iwFm1 -- "$1" "$root/$doc" 2>/dev/null | sed 's/^[#*|> 	-]*//' | cut -c1-72)"
    if [ -n "$line" ]; then printf '%s' "$line"; return; fi
  done
  # representative files: name-sharing first (auth/AuthService.ts speaks
  # for auth/), then the rest — deterministic order for a stable map
  list="$(find "$2" -type f -not -name '.*' -not -name '*.min.*' 2>/dev/null | sort | head -60)"
  pref="$(printf '%s\n' "$list" | grep -iF -- "$1" 2>/dev/null | head -6)"
  for f in $pref $(printf '%s\n' "$list" | grep -ivF -- "$1" 2>/dev/null | head -6); do
    sample="$(doc_line "$f" | cut -c1-72)"
    if [ -n "$sample" ]; then printf '%s' "$sample"; return; fi
  done
  symtext="$(syms $(printf '%s\n' $pref $list | head -8) 2>/dev/null | head -1)"
  if [ -n "$symtext" ]; then printf 'exports %s' "$symtext"; return; fi
  names="$(printf '%s\n' "$list" | head -60 | xargs -n1 basename 2>/dev/null |
    sed 's/\.[^.]*$//' | sort -u | head -3 | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$names" ]; then printf 'files like %s' "$names"; return; fi
  printf 'undocumented: what lives here'
}

seen="" used_pfx="" last_pfx=""
emit() { # dirname, scope, dirpath, parent-prefix, indent, sibling-names...
  local name="$1" scope="$2" path="$3" parent="$4" indent="$5" p
  shift 5
  # scopes repeat across parents — dedupe by scope, not name
  case " $seen " in *" $scope "*) return ;; esac
  has_files "$path" || return 0
  seen="$seen $scope"
  rows=$((rows + 1))
  p="$(pfx "$name" "$path" "$@")"
  # prefixes need only be unique within their parent level — a nested
  # checkout: under payments: and orders: reads orders:checkout: vs
  # payments:checkout:, already distinct
  key="${parent:-top}:$p"
  case " $used_pfx " in *" $key "*)
    [ -n "$parent" ] && p="$parent-$name" || p="todo-$name" ;;
  esac
  case " $used_pfx " in *" ${parent:-top}:$p "*) p="todo-$name" ;; esac
  used_pfx="$used_pfx ${parent:-top}:$p"
  last_pfx="$p"
  printf '| %s%s: | %s | %s |\n' "$indent" "$p" "$scope" "$(desc_for "$name" "$path")"
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
# scoped correctly — it earns its own row with declaration landmarks
jumbos=""
cand="$(find "$root" -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null |
  grep -vE '/(dist|build|target|coverage|out|__pycache__|venv|bin|obj|storybook-static|DerivedData|Pods)/|/[^/]+-out/' || true)"
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
  # prefix, kept in the scope
  topnames=""
  for d in "$root"/*/ "$root"/.[!.]*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    skipped_gen "$name" && continue
    topnames="$topnames $name"
  done
  for name in $topnames; do
    [ "$rows" -ge "$dir_budget" ] && break
    emit "${name#.}" "$name/**" "$root/$name" "" "" $topnames
  done

  # descend into dirs that hold most of a repo's code, then one level
  # deeper where a child holds sub-teams (payments → checkout, refunds)
  for parent in src lib app packages apps services modules libs; do
    [ -d "$root/$parent" ] || continue
    kids=""
    for d in "$root/$parent"/*/; do
      [ -d "$d" ] || continue
      child="$(basename "$d")"
      skipped_gen "$child" && continue
      kids="$kids $child"
    done
    for child in $kids; do
      [ "$rows" -ge "$dir_budget" ] && break 2
      emit "$child" "$parent/$child/**" "$root/$parent/$child" "" "" $kids
      cp="$last_pfx"
      gkids=""
      for d in "$root/$parent/$child"/*/; do
        [ -d "$d" ] || continue
        g="$(basename "$d")"
        skipped_gen "$g" && continue
        gkids="$gkids $g"
      done
      [ "$(echo $gkids | wc -w)" -ge 2 ] || continue
      for g in $gkids; do
        [ "$rows" -ge "$dir_budget" ] && break 3
        emit "$g" "$parent/$child/$g/**" "$root/$parent/$child/$g" "$cp" "  " $gkids
      done
    done
  done

  # files at repo root are a distinct intent: config, manifests, docs
  if [ -n "$rf" ]; then
    rscope="" alldoc=1
    while IFS= read -r f; do
      rel="${f#"$root"/}"
      case "$rel" in *.md|*.txt|*.rst|*.adoc) ;; *) alldoc=0 ;; esac
      rscope="${rscope:+$rscope, }$rel"
    done <<< "$rf"
    [ "$alldoc" -eq 1 ] && rp="doc" || rp="cfg"
    case " $used_pfx " in *" top:$rp "*) rp="todo-$rp" ;; esac
    used_pfx="$used_pfx top:$rp"
    rows=$((rows + 1))
    if [ "$alldoc" -eq 1 ]; then
      printf '| %s: | %s | docs at repo root |\n' "$rp" "$rscope"
    else
      printf '| %s: | %s | config, manifests, docs at repo root |\n' "$rp" "$rscope"
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
      case " $used_pfx " in *" top:$jp "*) continue ;; esac
      used_pfx="$used_pfx top:$jp"
      marks="$(grep -nE '^[[:space:]]*((export|async|pub|local|static|final|private|public)[[:space:]]+)*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+[A-Za-z_]' "$jf" 2>/dev/null |
        sed -nE 's/^([0-9]+):.*(function|class|interface|struct|impl|func|def|fn)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3@\1/p' |
        head -5 | paste -sd, - | sed 's/,/, /g')" || true
      cont="~$((cnt / 1000))k lines"
      [ -n "$marks" ] && cont="$cont: $marks" || true
      rows=$((rows + 1)); n=$((n + 1))
      printf '| %s: | %s | %s |\n' "$jp" "$rel" "$cont"
    done <<< "$jumbos"
  fi

  # well-known entry files are a distinct search intent
  if [ -n "$entries" ]; then
    rows=$((rows + 1))
    echo "| boot: | $entries | entry points, boot wiring |"
  fi
} > "$out"

drafts=$(grep -cE 'todo-|undocumented' "$out" || true)
echo "wrote $out · $rows namespaces, $drafts rows needing a human pass" >&2
if [ "$files" -lt 100 ]; then
  echo "note: ~$files files; under ~100 the map is marginal; scope by dir names" >&2
fi

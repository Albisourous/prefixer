#!/usr/bin/env bash
# Scaffold .prefixer/namespaces.md from a repo's layout.
# Descends one level into code-bearing dirs (src/lib/app/monorepo parents),
# seeds 'contains' from existing agent docs, and flags unfinished rows.
# usage: init_namespaces.sh [repo-root]
set -euo pipefail

root="${1:-.}"
out="$root/.prefixer/namespaces.md"

if [ -f "$out" ]; then
  echo "$out already exists; edit the stale rows, never regenerate" >&2
  exit 1
fi

mkdir -p "$root/.prefixer"
echo 'metrics.jsonl' > "$root/.prefixer/.gitignore"

files=$(find "$root" -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null | wc -l | tr -d ' ')

skip="node_modules vendor dist build target out .git .prefixer __pycache__ .next .cache venv .venv .idea .vscode coverage .turbo .output .nuxt .svelte-kit storybook-static DerivedData Pods bin obj"

# non-semantic words that appear in every repo — never a prefix
stop_re='^(index|main|mod|init|utils?|helpers?|common|shared|base|file|code|misc|tmp|temp|readme|license|package)$'

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

# derived, not declared: distinguishing dir-name segment, then the dominant
# file-name token, then the full name if short, else a visible todo
pfx() { # dirname, dirpath, sibling-names...
  local name="$1" path="$2" sib w n tok
  shift 2
  # short dir names are already the word a searcher says
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
  if [ -n "$tok" ]; then printf '%s' "$tok" | cut -c1-8; return; fi
  if [ "${#name}" -le 8 ]; then printf '%s' "$name"; else printf 'todo-%s' "$(printf '%s' "$name" | cut -c1-5)"; fi
}

# seed the 'contains' cell: agent-doc mention, else the real files inside,
# else a visible TODO
desc_for() { # dirname, dirpath
  local doc line names
  for doc in AGENTS.md CLAUDE.md README.md; do
    [ -f "$root/$doc" ] || continue
    line="$(grep -iwm1 "$1" "$root/$doc" 2>/dev/null | sed 's/^[#*|> 	-]*//' | cut -c1-72)"
    if [ -n "$line" ]; then printf '%s' "$line"; return; fi
  done
  names="$(find "$2" -type f -not -name '.*' 2>/dev/null | head -60 | xargs -n1 basename 2>/dev/null |
    sed 's/\.[^.]*$//' | sort -u | head -3 | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$names" ]; then printf 'files like %s' "$names"; return; fi
  printf 'TODO: what lives here'
}

seen="" used_pfx=""
emit() { # dirname, scope, dirpath, sibling-names...
  local name="$1" scope="$2" path="$3" p
  shift 3
  case " $seen " in *" $name "*) return ;; esac
  seen="$seen $name"
  p="$(pfx "$name" "$path" "$@")"
  # prefixes must be unique — two rows with one name scope nothing
  case " $used_pfx " in *" $p "*) p="todo-$(printf '%s' "$name" | cut -c1-5)" ;; esac
  used_pfx="$used_pfx $p"
  printf '| %s: | %s | %s |\n' "$p" "$scope" "$(desc_for "$name" "$path")"
}

# unique repo qualifier for multi-codebase contexts — from the git remote,
# else the directory name
remote="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
slug="$(basename "${remote:-$(cd "$root" && pwd)}" .git | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"

skipped_gen() { case " $skip " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

{
  echo '# namespaces'
  echo "repo: $slug"
  echo
  echo '| prefix | scope | contains |'
  echo '|--------|-------|----------|'

  topnames=""
  for d in "$root"/*/ "$root"/.github/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    skipped_gen "$name" && continue
    topnames="$topnames $name"
  done
  for name in $topnames; do
    emit "$name" "$name/**" "$root/$name" $topnames
  done

  # descend one level into dirs that hold most of a repo's code
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
      emit "$child" "$parent/$child/**" "$root/$parent/$child" $kids
    done
  done

  # well-known entry files are a distinct search intent
  entries=""
  for f in "$root"/src/main.* "$root"/src/index.* "$root"/src/cli.* \
           "$root"/main.* "$root"/index.* "$root"/cli.*; do
    [ -f "$f" ] || continue
    entries="${entries:+$entries, }${f#"$root"/}"
  done
  [ -n "$entries" ] && echo "| boot: | $entries | entry points, boot wiring |"
} > "$out"

todos=$(grep -c 'TODO:' "$out" || true)
echo "wrote $out — $todos draft rows (a map with TODO rows is a draft, not a map)" >&2
if [ "$files" -lt 100 ]; then
  echo "note: ~$files files — under ~100 the map is marginal; scope by dir names" >&2
fi

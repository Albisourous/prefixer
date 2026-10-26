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

# word the searcher would say — wordlist first, full name if short,
# todo-<stub> otherwise so unfinished rows stay visible
pfx() {
  case "$1" in
    src|lib|app|api|auth|core|game|data) echo "$1" ;;
    docs|doc) echo doc ;;
    test|tests|spec|specs|e2e) echo test ;;
    scripts|tools) echo tools ;;
    public|static) echo pub ;;
    assets) echo asset ;;
    ui|ux) echo ui ;;
    server) echo srv ;;
    client) echo cli ;;
    web|www) echo web ;;
    config|configs) echo cfg ;;
    infra|deploy|ci) echo inf ;;
    examples|example|demo|demos) echo ex ;;
    bench|benches) echo bench ;;
    models|model) echo model ;;
    migrations) echo mig ;;
    *) return 1 ;;
  esac
}

# seed the 'contains' cell from existing agent docs that mention the dir
desc_for() {
  local doc line
  for doc in AGENTS.md CLAUDE.md README.md; do
    [ -f "$root/$doc" ] || continue
    line="$(grep -iwm1 "$1" "$root/$doc" 2>/dev/null | sed 's/^[#*|> 	-]*//' | cut -c1-72)"
    if [ -n "$line" ]; then printf '%s' "$line"; return; fi
  done
  printf 'TODO: what lives here'
}

seen=""
emit() { # dirname, scope
  local p
  case " $seen " in *" $1 "*) return ;; esac
  seen="$seen $1"
  p="$(pfx "$1" || true)"
  if [ -z "$p" ]; then
    if [ "${#1}" -le 8 ]; then p="$1"; else p="todo-$(printf '%s' "$1" | cut -c1-5)"; fi
  fi
  printf '| %s: | %s | %s |\n' "$p" "$2" "$(desc_for "$1")"
}

skipped_gen() { case " $skip " in *" $1 "*) return 0 ;; esac; case "$1" in *-out) return 0 ;; esac; return 1; }

{
  echo '# namespaces'
  echo
  echo '| prefix | scope | contains |'
  echo '|--------|-------|----------|'

  for d in "$root"/*/ "$root"/.github/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    skipped_gen "$name" && continue
    emit "$name" "$name/**"
  done

  # descend one level into dirs that hold most of a repo's code
  for parent in src lib app packages apps services modules libs; do
    [ -d "$root/$parent" ] || continue
    for d in "$root/$parent"/*/; do
      [ -d "$d" ] || continue
      child="$(basename "$d")"
      skipped_gen "$child" && continue
      emit "$child" "$parent/$child/**"
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

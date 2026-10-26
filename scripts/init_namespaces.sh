#!/usr/bin/env bash
# Scaffold .prefixer/namespaces.md from a repo's top-level layout.
# The output is a draft: fill in each 'contains' line before trusting it.
# usage: init_namespaces.sh [repo-root]
set -euo pipefail

root="${1:-.}"
out="$root/.prefixer/namespaces.md"

if [ -f "$out" ]; then
  echo "$out already exists; edit the stale rows, never regenerate" >&2
  exit 1
fi

mkdir -p "$root/.prefixer"

skip="node_modules vendor dist build target out .git .prefixer __pycache__ .next .cache venv .venv .idea .vscode"

{
  echo '# namespaces'
  echo
  echo '| prefix | scope | contains |'
  echo '|--------|-------|----------|'

  for d in "$root"/*/ "$root"/.github/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case " $skip " in *" $name "*) continue ;; esac
    short="$(printf '%s' "$name" | cut -c1-4)"
    echo "| $short: | $name/** | TODO: what lives here |"
  done

  for parent in packages apps services modules libs; do
    [ -d "$root/$parent" ] || continue
    for d in "$root/$parent"/*/; do
      [ -d "$d" ] || continue
      echo "| ${parent:0:3}-$(basename "$d"): | $parent/$(basename "$d")/** | TODO: what lives here |"
    done
  done
} > "$out"

echo "wrote $out — fill in each 'contains' line before relying on it" >&2

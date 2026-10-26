#!/usr/bin/env bash
# Install the prefixer skill into an agent's skills directory.
# Detects the host the way graphify's installer does: marker dirs in the
# project or the home dir pick the destination, no questions asked.
#
#   bash scripts/install.sh                auto-detect, project if marked, else global
#   bash scripts/install.sh --global       user-level install for detected hosts
#   bash scripts/install.sh --project      into ./.<host>/skills/prefixer/
#   bash scripts/install.sh --platform devin|claude|agents|all [--project|--global]
#
# Copies SKILL.md + SPEC.md + references/ + scripts/ and stamps
# .prefixer_version beside them so stale installs are detectable.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$(cd "$here/.." && pwd)"
[ -f "$src/SKILL.md" ] || { echo "run me from a prefixer checkout" >&2; exit 1; }

scope="" platform=""
while [ $# -gt 0 ]; do
  case "$1" in
    --global|-g) scope=global ;;
    --project|-p) scope=project ;;
    --platform) platform="${2:?--platform needs a name}"; shift ;;
    --platform=*) platform="${1#--platform=}" ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

version="$(sed -n 's/^  version: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$src/SKILL.md" | head -1)"

# platform → (project dest, global dest). .agents/skills is the cross-
# framework path — Codex, Copilot CLI, Gemini, Cursor all read it.
dest() {
  case "$1" in
    claude) [ "$2" = global ] && echo "$HOME/.claude/skills/prefixer" || echo ".claude/skills/prefixer" ;;
    devin)  [ "$2" = global ] && echo "$HOME/.config/devin/skills/prefixer" || echo ".devin/skills/prefixer" ;;
    agents) [ "$2" = global ] && echo "$HOME/.agents/skills/prefixer" || echo ".agents/skills/prefixer" ;;
  esac
}

# marker dir in project or home → platform detected
detected() {
  for p in $platforms; do
    case "$p" in
      claude) [ -d .claude ] || [ -d "$HOME/.claude" ] && echo "$p" ;;
      devin)  [ -d .devin ] || [ -d "$HOME/.config/devin" ] && echo "$p" ;;
      agents) [ -d .agents ] || [ -d "$HOME/.agents" ] && echo "$p" ;;
    esac
  done
}

platforms="claude devin agents"
case "$platform" in
  "") targets="$(detected)" ;;
  all) targets="$platforms" ;;
  claude|devin|agents) targets="$platform" ;;
  *) echo "unknown platform: $platform (want claude|devin|agents|all)" >&2; exit 2 ;;
esac

# nothing detected: default to the spec path so the install still lands
# somewhere every skills-aware agent can read
[ -n "$targets" ] || targets="agents"

# project or global: explicit flag wins, else project when the detected
# marker lives in the cwd, else global
resolve_scope() {
  [ -n "$scope" ] && { echo "$scope"; return; }
  case "$1" in
    claude) [ -d .claude ] && echo project || echo global ;;
    devin)  [ -d .devin ] && echo project || echo global ;;
    agents) [ -d .agents ] && echo project || echo global ;;
  esac
}

installed=""
for p in $targets; do
  sc="$(resolve_scope "$p")"
  d="$(dest "$p" "$sc")"
  [ -n "$d" ] || continue
  mkdir -p "$d"
  # a detected target can resolve to this checkout itself (the installed
  # skill re-run from a marked project) — copying onto itself errors
  # under set -e after earlier targets already landed
  if [ "$(cd "$d" && pwd -P)" = "$(cd "$src" && pwd -P)" ]; then
    installed="$installed  $d ($sc) skipped, already this checkout
"
    continue
  fi
  cp "$src/SKILL.md" "$src/SPEC.md" "$d/"
  rm -rf "$d/references" "$d/scripts"
  cp -R "$src/references" "$d/references"
  cp -R "$src/scripts" "$d/scripts"
  # repo-side dev tooling is not part of the skill
  rm -rf "$d/scripts/__pycache__"
  rm -f "$d/scripts/test_scaffold.sh" "$d/scripts/validate-package.py"
  printf '%s\n' "${version:-unknown}" > "$d/.prefixer_version"
  installed="$installed  $d ($sc)
"
done

printf 'installed prefixer %s:\n%s' "${version:-?}" "$installed"
echo "next: run bash <dest>/scripts/init_namespaces.sh at your repo root,"
echo "then read .prefixer/namespaces.md before searching."
case "$installed" in *" ."*) echo "tip: 'git add' the skills dir to share it with the team" ;; esac

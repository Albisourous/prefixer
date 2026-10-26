#!/usr/bin/env bash
# eval/agent/run.sh — the real agent-behavior eval. Runs the task suite
# twice per task: baseline (no map) vs mapped (.prefixer/namespaces.md +
# session-start injection), logging every tool call through a PostToolUse
# hook. Output: eval/agent/RESULTS.md.
#
#   run.sh [--adapter devin|claude|auto] [--reps N] [--dry-run]
#          [--fixture DIR] [--runs DIR]
#
# Needs a logged-in agent CLI. Honest reading: agents are stochastic —
# run --reps N and report distributions; this measures tool traffic, not
# model intelligence. The prefixer skill is installed in BOTH arms; the
# only difference is the map, so a baseline run that scaffolds its own
# map pays for it in tool calls — all visible in the log.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export PFX_ROOT="$(cd "$here/../.." && pwd)"

adapter="" reps=1 dry="" fixture="" runs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --adapter) adapter="${2:?}"; shift ;;
    --adapter=*) adapter="${1#*=}" ;;
    --reps) reps="${2:?--reps needs a number}"; shift ;;
    --reps=*) reps="${1#*=}" ;;
    --fixture) fixture="${2:?--fixture needs a dir}"; shift ;;
    --runs) runs="${2:?--runs needs a dir}"; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '1,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

fixture="${fixture:-$here/.fixture}"
runs="${runs:-$here/.runs}"
tasks="$here/tasks.txt"
mkdir -p "$runs"

# --- pick an adapter ----------------------------------------------------
pick_adapter() {
  local want="$1" a first=""
  for a in ${want:-devin claude devin_acp}; do
    [ -f "$here/adapters/$a.sh" ] || continue
    ( . "$here/adapters/$a.sh"; agent_detect >/dev/null ) || continue
    [ -z "$first" ] && first="$a"
    ( . "$here/adapters/$a.sh"; agent_ready >/dev/null 2>&1 ) && { echo "$a"; return 0; }
  done
  [ -n "$first" ] && { echo "$first"; return 0; }   # none ready — dry-run path
  return 1
}
adapter="$(pick_adapter "$adapter")" || {
  echo "no agent CLI found; looked for devin, claude, devin_acp" >&2
  echo "install one, or point DEVIN_BIN at a binary" >&2; exit 1; }
. "$here/adapters/$adapter.sh"
export -f agent_run agent_detect   # timeout_run execs via bash -c
echo "adapter: $adapter ($(agent_detect))"

# --- build the fixture, scaffold its map, then install the skill ------
# Order matters: the map must describe the repo, not the harness. Skill
# dirs (.devin/skills etc.) land AFTER init so they can't eat map rows.
# Baseline deletes .prefixer before its arm; mapped keeps this map.
bash "$here/build_fixture.sh" "$fixture" >/dev/null
bash "$PFX_ROOT/scripts/init_namespaces.sh" "$fixture" >/dev/null 2>&1 || true
cp "$fixture/.prefixer/namespaces.md" "$runs/fixture.map.md" 2>/dev/null || true
( cd "$fixture" && bash "$PFX_ROOT/scripts/install.sh" --platform all --project >/dev/null )

if ! agent_ready; then
  echo "$adapter is installed but not authenticated; log in first:" >&2
  case "$adapter" in devin) echo "  devin auth login" >&2 ;; claude) echo "  claude login" >&2 ;; esac
  [ -n "$dry" ] || exit 1
fi

# timeout wrapper: gtimeout if present, else perl's alarm (stock macOS)
timeout_run() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; fi
}

task_rows() { grep -vE '^[[:space:]]*(#|$)' "$tasks"; }

plan="$(task_rows | wc -l | tr -d ' ') tasks x 2 arms x $reps reps"
[ -n "$dry" ] && echo "dry-run: $plan, no agent calls"

[ -f "$runs/fixture.map.md" ] || {
  echo "no fixture map at $runs/fixture.map.md; scaffold failed" >&2; exit 1; }

for cond in baseline mapped; do
  [ "$cond" = mapped ] && m=1 || m=0
  agent_hooks "$fixture" "$runs/.active.jsonl" "$m"

  while IFS='|' read -r tid prompt epath esym; do
    tid="${tid// /}"; [ -n "$tid" ] || continue
    for rep in $(seq 1 "$reps"); do
      base="$runs/${cond}__${tid}__r${rep}"
      # every run starts from the same repo state: baseline gets no
      # .prefixer at all, mapped restores the fixture map. A run that
      # scaffolds or edits the map must not leak into the next run.
      rm -rf "$fixture/.prefixer"
      if [ "$cond" = mapped ]; then
        mkdir -p "$fixture/.prefixer"
        cp "$runs/fixture.map.md" "$fixture/.prefixer/namespaces.md"
      fi
      rm -f "$runs/.active.jsonl"
      [ -n "$dry" ] && { echo "would run: $cond/$tid rep$rep"; continue; }
      echo "run: $cond/$tid rep$rep"
      timeout_run 900 bash -c 'agent_run "$@"' _ "$fixture" "$prompt" "$base.out.txt" || true
      [ -f "$runs/.active.jsonl" ] && mv "$runs/.active.jsonl" "$base.jsonl" || : > "$base.jsonl"
      [ -f "$fixture/.prefixer/namespaces.md" ] && cp "$fixture/.prefixer/namespaces.md" "$base.map.md" || true
    done
  done < <(task_rows)
done

[ -n "$dry" ] && { echo "dry-run done; fixture and hooks written under $here"; exit 0; }

python3 "$here/summarize.py" "$runs" "$tasks" > "$here/RESULTS.md"
echo "wrote $here/RESULTS.md"

#!/usr/bin/env bash
# Self-check for init_namespaces.sh — builds a nested fixture and asserts
# the derived map. usage: bash scripts/test_scaffold.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # description, grep-pattern, file
  if grep -q "$2" "$3" 2>/dev/null; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
nocheck() { # description, grep-pattern, file
  if grep -q "$2" "$3" 2>/dev/null; then echo "FAIL $1"; fail=1; else echo "ok   $1"; fi
}

# --- fixture: payments repo with sub-teams, collision, empty + gen dirs ---
repo="$tmp/payments"
mkdir -p "$repo/src"/{auth,api,db} \
         "$repo/services/payments"/{checkout,refunds} \
         "$repo/services/orders"/{checkout,tracking} \
         "$repo/graphify-out" "$repo/emptydir"
for d in auth api db; do echo "$d code here" > "$repo/src/$d/${d}Handler.ts"; done
echo "checkout code" > "$repo/services/payments/checkout/CartFlow.ts"
echo "refunds code" > "$repo/services/payments/refunds/RefundFlow.ts"
echo "checkout code" > "$repo/services/orders/checkout/OrderCart.ts"
echo "tracking code" > "$repo/services/orders/tracking/ShipTrack.ts"
echo x > "$repo/graphify-out/graph.json"
( cd "$repo" && git init -q && git remote add origin git@github.com:acme/payments-platform.git )

bash "$here/init_namespaces.sh" "$repo" >/dev/null 2>&1
map="$repo/.prefixer/namespaces.md"

check "repo slug from git remote"      'repo: payments-platform' "$map"
check "first-level namespace"          '| auth: | src/auth/\*\*' "$map"
check "nested sub-team indented"       '|   checkout: | services/payments/checkout/\*\*' "$map"
check "second sub-team"                '|   refunds: | services/payments/refunds/\*\*' "$map"
if [ "$(grep -c 'checkout:' "$map")" -eq 2 ]; then
  echo "ok   same name under two parents stays nested"
else
  echo "FAIL same name under two parents stays nested"; fail=1
fi
nocheck "graphify-out skipped"         'graph' "$map"
nocheck "empty dir skipped"            'emptydir' "$map"
nocheck "no leftover todo markers"     'todo-' "$map"
nocheck "no undocumented cells"        'undocumented' "$map"

# --- fixture: camelCase siblings derive distinguishing segments ---
repo2="$tmp/ballgame"
mkdir -p "$repo2/src"/{GameServer,GameClient}
echo x > "$repo2/src/GameServer/SaveService.luau"
echo x > "$repo2/src/GameClient/BeatPulse.client.luau"
bash "$here/init_namespaces.sh" "$repo2" >/dev/null 2>&1
map2="$repo2/.prefixer/namespaces.md"

check "repo slug from dir name"        'repo: ballgame' "$map2"
check "client segment derived"         'client: | src/GameClient/\*\*' "$map2"
check "server segment derived"         'server: | src/GameServer/\*\*' "$map2"

# --- refuses to regenerate an existing map ---
if bash "$here/init_namespaces.sh" "$repo2" >/dev/null 2>&1; then
  echo "FAIL regeneration refused"; fail=1
else
  echo "ok   regeneration refused"
fi

# --- check_namespaces.sh: scaffolded map passes, broken map fails ---
if bash "$here/check_namespaces.sh" "$repo" >/dev/null 2>&1; then
  echo "ok   check passes on scaffolded map"
else
  echo "FAIL check passes on scaffolded map"; fail=1
fi

bad="$tmp/broken"
mkdir -p "$bad/src" "$bad/.prefixer"
echo x > "$bad/src/a.ts"
cat > "$bad/.prefixer/namespaces.md" <<'EOF'
# namespaces
| prefix | scope | contains |
|--------|-------|----------|
| api: | src/** | handlers |
| api: | src/nope/** | dup and dead |
| todo-x: | nowhere/** | TODO: unfinished |
EOF
if bash "$here/check_namespaces.sh" "$bad" >/dev/null 2>&1; then
  echo "FAIL check catches broken map"; fail=1
else
  echo "ok   check catches broken map"
fi

# --- eval_scope.sh emits a metrics JSON line ---
out="$(bash "$here/eval_scope.sh" "$repo" "x" api)"
case "$out" in
  *'"est_tokens_saved"'*) echo "ok   eval emits metrics" ;;
  *) echo "FAIL eval emits metrics"; fail=1 ;;
esac

# --- eval_repo.sh aggregates the whole map ---
out="$(bash "$here/eval_repo.sh" "$repo")"
case "$out" in
  *"mean pct_saved"*) echo "ok   repo eval aggregates" ;;
  *) echo "FAIL repo eval aggregates"; fail=1 ;;
esac

# nested rows eval under their composed tag — orders:checkout must not
# be measured against the payments:checkout scope
case "$out" in
  *"payments:checkout:"*"orders:checkout:"*|*"orders:checkout:"*"payments:checkout:"*)
    echo "ok   nested rows eval by composed tag" ;;
  *) echo "FAIL nested rows eval by composed tag"; fail=1 ;;
esac

# --- a namespace whose own name never appears in its files is a probe
# blind spot — n/a, not a meaningless 100% (issue #15) ---
blind="$tmp/blind"; mkdir -p "$blind/src/core" "$blind/.prefixer"
echo "vec rng loop" > "$blind/src/core/engine.ts"
cat > "$blind/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: blind
| prefix | scope | contains |
|--------|-------|----------|
| core: | src/core/** | engine |
EOF
out="$(bash "$here/eval_repo.sh" "$blind" 2>/dev/null)"
case "$out" in
  *n/a*) echo "ok   0-hit namespace reports n/a" ;;
  *) echo "FAIL 0-hit namespace reports n/a"; fail=1 ;;
esac

# --- contains sampling: doc comment, then exports, then file names ---
repo3="$tmp/docsrc"
mkdir -p "$repo3/src"/{auth,api,notes}
cat > "$repo3/src/auth/AuthService.ts" <<'EOF'
// Handles session tokens, expiry, and refresh for the auth namespace
export class AuthService {}
EOF
cat > "$repo3/src/api/apiHandlers.ts" <<'EOF'
export function handleRequest() {}
export function handleResponse() {}
EOF
echo 'plain text, no comment markers' > "$repo3/src/notes/notes.txt"
bash "$here/init_namespaces.sh" "$repo3" >/dev/null 2>&1
map3="$repo3/.prefixer/namespaces.md"

check "contains from doc comment"   'Handles session tokens, expiry' "$map3"
check "contains from exports"       'exports handleRequest' "$map3"
check "contains falls to file names" 'files like notes' "$map3"

# --- a scope that is not glob syntax fails the lint, not the shell ---
evil="$tmp/evil"
mkdir -p "$evil/src" "$evil/.prefixer"
echo x > "$evil/src/a.ts"
cat > "$evil/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: evil
| prefix | scope | contains |
|--------|-------|----------|
| api: | src/** | handlers |
| pwn: | $(touch /tmp/prefixer-pwned)/** | injected |
EOF
rm -f /tmp/prefixer-pwned
if bash "$here/check_namespaces.sh" "$evil" >/dev/null 2>&1; then
  echo "FAIL unsafe scope rejected"; fail=1
else
  echo "ok   unsafe scope rejected"
fi
[ -e /tmp/prefixer-pwned ] && { echo "FAIL scope executed as shell"; fail=1; } || echo "ok   scope never reached the shell"

# --- spaced dir names: scaffold slugs the prefix, lint and eval honour
# the spaced scope (issue: spaces silently broke both) ---
repo4="$tmp/spaced"
mkdir -p "$repo4/my dir" "$repo4/src"
echo "token here" > "$repo4/my dir/code.ts"; echo x > "$repo4/src/a.ts"
bash "$here/init_namespaces.sh" "$repo4" >/dev/null 2>&1
map4="$repo4/.prefixer/namespaces.md"
check "spaced dir gets slugged prefix" 'my-dir: | my dir/\*\*' "$map4"
if bash "$here/check_namespaces.sh" "$repo4" >/dev/null 2>&1; then
  echo "ok   spaced scope lints live"
else
  echo "FAIL spaced scope lints live"; fail=1
fi
out="$(bash "$here/eval_scope.sh" "$repo4" token my-dir 2>/dev/null)"
case "$out" in
  *'"ns_hits":0'*) echo "FAIL spaced scope measured"; fail=1 ;;
  *ns_hits*) echo "ok   spaced scope measured" ;;
  *) echo "FAIL spaced scope measured"; fail=1 ;;
esac

# --- brace scopes count for coverage (issue: {src,lib}/** warned
# "uncovered" on both arms) ---
br="$tmp/braced"; mkdir -p "$br/src" "$br/lib" "$br/.prefixer"
echo x > "$br/src/a.ts"; echo x > "$br/lib/b.ts"
cat > "$br/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: braced
| prefix | scope | contains |
|--------|-------|----------|
| app: | {src,lib}/** | app code |
EOF
if bash "$here/check_namespaces.sh" "$br" 2>&1 | grep -q uncovered; then
  echo "FAIL brace scopes count for coverage"; fail=1
else
  echo "ok   brace scopes count for coverage"
fi

# --- single-star scopes don't cross directories (issue: find -path let
# dead scopes sail through) ---
star="$tmp/star"; mkdir -p "$star/deep/nest" "$star/.prefixer"
echo x > "$star/deep/nest/only.luau"
cat > "$star/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: star
| prefix | scope | contains |
|--------|-------|----------|
| luau: | deep/*.luau | deep files |
EOF
if bash "$here/check_namespaces.sh" "$star" >/dev/null 2>&1; then
  echo "FAIL single-star dead scope caught"; fail=1
else
  echo "ok   single-star dead scope caught"
fi

# --- the eval baseline excludes generated dirs (issue: grep through
# node_modules inflated pct_saved) ---
repo5="$tmp/straw"; mkdir -p "$repo5/src" "$repo5/node_modules/big" "$repo5/.prefixer"
echo "token" > "$repo5/src/a.ts"
for i in $(seq 20); do echo "token filler $i"; done > "$repo5/node_modules/big/b.js"
cat > "$repo5/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: straw
| prefix | scope | contains |
|--------|-------|----------|
| api: | src/** | handlers |
EOF
out="$(bash "$here/eval_scope.sh" "$repo5" token api 2>/dev/null)"
case "$out" in
  *'"root_hits":1'*) echo "ok   baseline excludes generated dirs" ;;
  *) echo "FAIL baseline excludes generated dirs"; fail=1 ;;
esac

# --- fixture: dot dirs, root files, jumbo files all earn rows ---
repo3="$tmp/tinyts"
mkdir -p "$repo3/src/game" "$repo3/src/core" "$repo3/.devin/hooks"
{ for i in $(seq 1 3100); do echo "line $i"; done; } > "$repo3/src/game/battle.ts"
echo 'export function spawnWave() {}' >> "$repo3/src/game/battle.ts"
echo x > "$repo3/src/core/engine.ts"
echo '# session hook' > "$repo3/.devin/hooks/session-start.sh"
echo '{}' > "$repo3/package.json"
echo x > "$repo3/vite.config.ts"
echo x > "$repo3/TRACKER.md"
bash "$here/init_namespaces.sh" "$repo3" >/dev/null 2>&1
map3="$repo3/.prefixer/namespaces.md"

check "dot dir gets a row"          '| devin: | \.devin/\*\*' "$map3"
check "root files get a row"        '| cfg: | .*package\.json' "$map3"
check "jumbo file gets a row"       '| battle: | src/game/battle.ts |' "$map3"
check "jumbo carries landmarks"     'spawnWave@' "$map3"
if bash "$here/check_namespaces.sh" "$repo3" >/dev/null 2>&1; then
  echo "ok   check passes on dot/root/jumbo rows"
else
  echo "FAIL check passes on dot/root/jumbo rows"; fail=1
fi

# --- measure_search.sh: anchors at repo root, logs scope + verdict ---
( cd "$repo/src" && bash "$here/measure_search.sh" --scope src/auth --hit t-sub -- grep -rn x auth ) >/dev/null 2>&1
mfile="$repo/.prefixer/metrics.jsonl"
check "logs at repo root"            '"task":"t-sub"' "$mfile"
if [ -e "$repo/src/.prefixer" ]; then
  echo "FAIL no stray .prefixer in subdir"; fail=1
else
  echo "ok   no stray .prefixer in subdir"
fi
check "scope recorded"               '"scope":"src/auth"' "$mfile"
check "hit verdict recorded"         '"first_try_hit":true' "$mfile"
check "iso-8601 timestamp"           '"ts":"[0-9-]*T[0-9:]*Z"' "$mfile"

# walk-up fallback: repo2 has no git, .prefixer lives at its root
( cd "$repo2/src" && bash "$here/measure_search.sh" t-inf -- grep -rn x GameServer ) >/dev/null 2>&1
mfile2="$repo2/.prefixer/metrics.jsonl"
check "walk-up anchor without git"   '"task":"t-inf"' "$mfile2"
check "scope inferred from path arg" '"scope":"GameServer"' "$mfile2"

# --- a leading slash means root-anchored, not absolute — /*.md must
# resolve like *.md (issue #13) ---
anchor="$tmp/anchor"; mkdir -p "$anchor/docs/deep" "$anchor/.prefixer"
echo x > "$anchor/TOP.md"; echo x > "$anchor/docs/deep/inner.md"
cat > "$anchor/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: anchor
| prefix | scope | contains |
|--------|-------|----------|
| tops: | /*.md | root markdown |
| allmd: | docs/**, *.md | docs plus root md |
EOF
bash "$here/check_namespaces.sh" "$anchor" >/dev/null 2>&1 &&
  echo "ok   leading-slash scope lints live" ||
  { echo "FAIL leading-slash scope lints live"; fail=1; }
out="$(cd "$anchor" && bash "$here/eval_scope.sh" . x tops 2>/dev/null)"
case "$out" in
  *'"ns_hits":1'*) echo "ok   leading-slash scope is root-only" ;;
  *) echo "FAIL leading-slash scope is root-only"; fail=1 ;;
esac

# --- a mapped generated dir is a fail, not a warn — the doc says never
# (issue #17) ---
genmap="$tmp/genmap"; mkdir -p "$genmap/src" "$genmap/dist" "$genmap/.prefixer"
echo x > "$genmap/src/a.ts"; echo x > "$genmap/dist/b.js"
cat > "$genmap/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: genmap
| prefix | scope | contains |
|--------|-------|----------|
| api: | src/** | handlers |
| dist: | dist/** | built output |
EOF
genout="$(bash "$here/check_namespaces.sh" "$genmap" 2>&1 || true)"
case "$genout" in
  *'FAIL generated path mapped'*) echo "ok   generated dir mapping fails" ;;
  *) echo "FAIL generated dir mapping fails"; fail=1 ;;
esac

# --- a crashed probe is logged as an error, not a phantom 0-hit
# (issue #19) ---
( cd "$repo" && bash "$here/measure_search.sh" t-bad -- nonexistent_cmd_xyz foo ) >/dev/null 2>&1
check "failed probe logs error"      '"error":true' "$repo/.prefixer/metrics.jsonl"
check "failed probe records exit"    '"exit":127' "$repo/.prefixer/metrics.jsonl"

# --- scaffold truncation at the row cap says so, with names
# (issue #20) ---
wide="$tmp/wide"; mkdir -p "$wide"
for i in $(seq 1 15); do mkdir -p "$wide/team$i"; echo x > "$wide/team$i/f.ts"; done
out="$(bash "$here/init_namespaces.sh" "$wide" 2>&1)"
case "$out" in
  *"unmapped"*) echo "ok   row cap notes unmapped dirs" ;;
  *) echo "FAIL row cap notes unmapped dirs"; fail=1 ;;
esac
check "unmapped note lands in map"   '^unmapped:' "$wide/.prefixer/namespaces.md"

# --- a mostly-binary dir is marked names-only — a content grep there
# is noise (issue #16) ---
binrepo="$tmp/binrepo"; mkdir -p "$binrepo/public/sprites" "$binrepo/src"
printf 'x\0y\0z' > "$binrepo/public/sprites/atlas.png"
printf '\0\1\2\3' > "$binrepo/public/sprites/sheet.webp"
echo "code here" > "$binrepo/src/a.ts"
bash "$here/init_namespaces.sh" "$binrepo" >/dev/null 2>&1
check "binary dir marked names-only" 'names only — binary assets' "$binrepo/.prefixer/namespaces.md"

# --- an unbalanced '{' in a scope must not hang the linter
# (issue #24 — the brace expander recursed forever) ---
hangr="$tmp/hang"; mkdir -p "$hangr/src" "$hangr/.prefixer"
echo x > "$hangr/src/a.ts"
cat > "$hangr/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: hang
| prefix | scope | contains |
|--------|-------|----------|
| api: | src/{a,b | malformed |
EOF
out="$(
  bash "$here/check_namespaces.sh" "$hangr" 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 40 ] && kill -0 "$pid" 2>/dev/null; do i=$((i+1)); sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; echo HUNG
  else
    wait "$pid" || true
  fi
)"
case "$out" in
  *HUNG*) echo "FAIL unbalanced brace hangs"; fail=1 ;;
  *"dead scope"*) echo "ok   unbalanced brace fails, no hang" ;;
  *) echo "FAIL unbalanced brace fails, no hang"; fail=1 ;;
esac

# --- BSD sed [ \t] strips literal 't' — a tools/** scope must stay
# tools/** (issue #26) ---
tre="$tmp/tscope"; mkdir -p "$tre/tools" "$tre/.prefixer"
echo x > "$tre/tools/t.ts"
cat > "$tre/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: tscope
| prefix | scope | contains |
|--------|-------|----------|
| tools: | tools/** | tooling |
EOF
tout="$(bash "$here/check_namespaces.sh" "$tre" 2>&1 || true)"
case "$tout" in
  *uncovered* | *"dead scope"*) echo "FAIL t-leading scope corrupted"; fail=1 ;;
  *) echo "ok   t-leading scope intact" ;;
esac

# --- contains never carries '|' or '\r' into the table (issue #27) ---
pipe="$tmp/pipecell"; mkdir -p "$pipe/src/api" "$pipe/src/other"
printf '// see table | col2 for the api layout\nvoid api() {}\n' > "$pipe/src/api/a.ts"
printf 'plain code\n' > "$pipe/src/other/b.ts"
bash "$here/init_namespaces.sh" "$pipe" >/dev/null 2>&1
if [ -n "$(awk -F'|' 'NF>5' "$pipe/.prefixer/namespaces.md")" ]; then
  echo "FAIL pipe char in contains cells"; fail=1
else
  echo "ok   no pipe char in contains cells"
fi
if grep -q $'\r' "$pipe/.prefixer/namespaces.md"; then
  echo "FAIL carriage return in map"; fail=1
else
  echo "ok   no carriage returns in map"
fi

# --- badge/link lines are not contains (issue #28) ---
badge="$tmp/badge"; mkdir -p "$badge/ci"
cat > "$badge/README.md" <<'EOF'
# BadgeRepo
[![Build status](https://img.shields.io/ci/badge.svg)](https://ci.example.com)
The ci directory runs the release pipeline and nightly matrix.
EOF
echo x > "$badge/ci/run.sh"
bash "$here/init_namespaces.sh" "$badge" >/dev/null 2>&1
nocheck "badge line not picked as contains" 'Build status\|img.shields' "$badge/.prefixer/namespaces.md"

# --- incidental doc mentions lose to descriptive path mentions
# (issue #34: a trailing 'docs/...' path beat the real description) ---
inc="$tmp/incidental"; mkdir -p "$inc/docs"
cat > "$inc/README.md" <<'EOF'
# Game
src/game/ui.ts draws the menu; spec lives at docs/specs/ui.md path.
- `docs/` holds all project documentation and design specs.
EOF
echo x > "$inc/docs/guide.md"
bash "$here/init_namespaces.sh" "$inc" >/dev/null 2>&1
check "subject mention beats incidental" 'project documentation' "$inc/.prefixer/namespaces.md"

# --- long dir names stay name-derived, not a random file token
# (issue #29: .changeset -> undici:, acceptance/ -> create:) ---
longn="$tmp/longnames"; mkdir -p "$longn/acceptance" "$longn/src"
echo 'create flow' > "$longn/acceptance/create_user.ts"
echo x > "$longn/src/a.ts"
bash "$here/init_namespaces.sh" "$longn" >/dev/null 2>&1
check "dir name beats file token"       'acceptance: | acceptance/\*\*' "$longn/.prefixer/namespaces.md"

# --- workspace parents descend: crates/ children get rows (issue #30) ---
ws="$tmp/workspace"; mkdir -p "$ws/crates/parser" "$ws/crates/lexer" "$ws/crates/fmt"
echo x > "$ws/crates/parser/p.rs"; echo x > "$ws/crates/lexer/l.rs"; echo x > "$ws/crates/fmt/f.rs"
bash "$here/init_namespaces.sh" "$ws" >/dev/null 2>&1
check "crates children get rows"        'parser: | crates/parser/\*\*' "$ws/.prefixer/namespaces.md"

# --- lockfiles stay out of the root-file scope; data files don't take
# jumbo rows (issue #31) ---
lk="$tmp/locks"; mkdir -p "$lk/src"
echo x > "$lk/package.json"; echo x > "$lk/package-lock.json"; echo x > "$lk/Cargo.lock"
{ for i in $(seq 1 3100); do echo "row $i"; done; } > "$lk/src/bigdata.txt"
echo x > "$lk/src/a.ts"
bash "$here/init_namespaces.sh" "$lk" >/dev/null 2>&1
nocheck "lockfiles out of cfg scope"   'package-lock.json\|Cargo.lock' "$lk/.prefixer/namespaces.md"
nocheck "data .txt not a jumbo row"    'src/bigdata.txt' "$lk/.prefixer/namespaces.md"

# --- search.sh: scoped hit, widen-on-miss, ambiguity, map-as-index ---
srch="$tmp/srch"; mkdir -p "$srch/src/auth" "$srch/src/api" "$srch/.prefixer"
echo 'fn checkSession() { expire() }' > "$srch/src/auth/session.ts"
echo 'fn handle() {}' > "$srch/src/api/route.ts"
cat > "$srch/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: srch

| prefix | scope | contains |
|--------|-------|----------|
| auth: | src/auth/** | sessions, tokens |
| api: | src/api/** | handlers |
EOF

out="$(cd "$srch" && bash "$here/search.sh" auth expire 2>/dev/null)"
case "$out" in
  *"src/auth/session.ts"*) echo "ok   scoped search hits" ;;
  *) echo "FAIL scoped search hits"; fail=1 ;;
esac

out="$(cd "$srch" && bash "$here/search.sh" api expire 2>/dev/null)"
case "$out" in
  *"src/auth/session.ts"*) echo "ok   miss widens to root and finds" ;;
  *) echo "FAIL miss widens to root and finds"; fail=1 ;;
esac
check "widen logged"    '"widened_to":"root"' "$srch/.prefixer/metrics.jsonl"
check "hit_dirs logged" '"hit_dirs":"src/auth:1"' "$srch/.prefixer/metrics.jsonl"
check "not first-try"   '"first_try_hit":false' "$srch/.prefixer/metrics.jsonl"

if (cd "$srch" && bash "$here/search.sh" auth no_such_symbol_qzx >/dev/null 2>&1); then
  echo "FAIL total miss exits 1"; fail=1
else
  echo "ok   total miss exits 1"
fi

out="$(cd "$srch" && bash "$here/search.sh" --scope auth)"
[ "$out" = "src/auth/**" ] && echo "ok   --scope prints globs" || { echo "FAIL --scope prints globs"; fail=1; }
out="$(cd "$srch" && bash "$here/search.sh" --paths auth)"
case "$out" in
  *"src/auth/session.ts"*) echo "ok   --paths resolves files" ;;
  *) echo "FAIL --paths resolves files"; fail=1 ;;
esac
out="$(cd "$srch" && bash "$here/search.sh" --list)"
case "$out" in
  *"auth:"*"api:"*) echo "ok   --list prints tags" ;;
  *) echo "FAIL --list prints tags"; fail=1 ;;
esac

# a leaf under two parents is ambiguous — report, don't first-match
if (cd "$repo" && bash "$here/search.sh" checkout x >/dev/null 2>&1); then
  echo "FAIL ambiguous leaf refused"; fail=1
else
  echo "ok   ambiguous leaf refused"
fi

# a widened search must not self-hit its own metrics log
(cd "$srch" && bash "$here/search.sh" --no-log api widened_marker_qzx) >/dev/null 2>&1 || true
out="$(cd "$srch" && bash "$here/search.sh" --no-log api widened_marker_qzx 2>/dev/null)" || true
case "$out" in
  *metrics.jsonl*) echo "FAIL widened search self-hits the log"; fail=1 ;;
  *) echo "ok   widened search skips .prefixer" ;;
esac

# --- suggest_map.sh: log + tree → proposed rows -----------------------
sg="$tmp/suggest"; mkdir -p "$sg/src/api" "$sg/src/core" "$sg/.prefixer"
echo x > "$sg/src/api/a.ts"; echo 'engine loop' > "$sg/src/core/engine.ts"
cat > "$sg/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: sg

| prefix | scope | contains |
|--------|-------|----------|
| api: | src/api/** | handlers |
EOF
cat > "$sg/.prefixer/metrics.jsonl" <<'EOF'
{"ts":"2026-10-26T10:00:00Z","task":"scoped-search","ns":"api","pattern":"x","scope":"src/api/**","searches":1,"hits":0,"est_tokens":0,"first_try_hit":false,"widened_to":"root","hit_dirs":"src/core:3"}
{"ts":"2026-10-26T10:01:00Z","task":"t","pattern":"y","scope":"root","searches":1,"hits":9,"est_tokens":800}
EOF
out="$(bash "$here/suggest_map.sh" "$sg" 2>/dev/null)"
case "$out" in
  *"core: | src/core/"*) echo "ok   suggests a row for widened-hit dir" ;;
  *) echo "FAIL suggests a row for widened-hit dir"; fail=1 ;;
esac
case "$out" in
  *"ROOT"*) echo "ok   counts unscoped root searches" ;;
  *) echo "FAIL counts unscoped root searches"; fail=1 ;;
esac
case "$out" in
  *"HEALTH"*) echo "ok   restates lint health" ;;
  *) echo "FAIL restates lint health"; fail=1 ;;
esac
# a mapped scope is never suggested as ADD
nocheck "mapped scope not re-suggested" 'api:.*<-' <(printf '%s' "$out")

# --- session_start.sh: silent without a map, envelope with one --------
nostart="$tmp/nostart"; mkdir -p "$nostart"
out="$(cd "$nostart" && bash "$here/session_start.sh" 2>/dev/null)"
[ -z "$out" ] && echo "ok   session_start silent without map" || { echo "FAIL session_start silent without map"; fail=1; }
out="$(cd "$srch" && bash "$here/session_start.sh" --json)"
case "$out" in
  *'"hookSpecificOutput"'*'"SessionStart"'*'auth:'*) echo "ok   session_start emits hook envelope" ;;
  *) echo "FAIL session_start emits hook envelope"; fail=1 ;;
esac

# --- install_hook.sh: writes hooks.v1.json, idempotent ----------------
hk="$tmp/hooked"; mkdir -p "$hk/.devin" "$hk/.prefixer"
echo x > "$hk/f.ts"
cp "$srch/.prefixer/namespaces.md" "$hk/.prefixer/namespaces.md"
( cd "$hk" && bash "$here/install_hook.sh" devin ) >/dev/null 2>&1
check "hooks.v1.json written"   'SessionStart' "$hk/.devin/hooks.v1.json"
check "hook calls session_start" 'session_start.sh' "$hk/.devin/hooks.v1.json"
out="$(cd "$hk" && bash "$here/install_hook.sh" devin 2>&1)"
case "$out" in
  *"already wired"*) echo "ok   hook install is idempotent" ;;
  *) echo "FAIL hook install is idempotent"; fail=1 ;;
esac
out="$(cd "$hk" && bash "$here/session_start.sh" --json)"
case "$out" in
  *hookSpecificOutput*) echo "ok   wired hook script resolves" ;;
  *) echo "FAIL wired hook script resolves"; fail=1 ;;
esac

# --- literal [ ] { } in scopes: file[1].txt is a filename, not a class -
br="$tmp/brack"; mkdir -p "$br/src" "$br/.prefixer"
echo needle > "$br/src/file[1].txt"; echo decoy > "$br/src/file1.txt"
cat > "$br/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: br

| prefix | scope | contains |
|--------|-------|----------|
| f: | src/file[1].txt | the bracket file |
EOF
out="$(cd "$br" && bash "$here/check_namespaces.sh" . 2>&1)"
case "$out" in
  *"0 failures"*) echo "ok   literal [ in scope resolves to named file" ;;
  *) echo "FAIL literal [ in scope resolves to named file"; fail=1 ;;
esac
out="$(cd "$br" && bash "$here/eval_scope.sh" . needle f 2>/dev/null)"
case "$out" in
  *'"ns_hits":1'*) echo "ok   [ scope evals against literal file" ;;
  *) echo "FAIL [ scope evals against literal file"; fail=1 ;;
esac
# an unclosed [ is a dead scope, never a regex error
printf '# namespaces\nrepo: br\n\n| prefix | scope | contains |\n|--|--|--|\n| bad: | src/file[.txt | oops |\n' > "$br/.prefixer/namespaces.md"
out="$(cd "$br" && bash "$here/check_namespaces.sh" . 2>&1 || true)"
case "$out" in
  *"dead scope: bad:"*) echo "ok   unclosed [ is a dead scope, not a crash" ;;
  *) echo "FAIL unclosed [ is a dead scope, not a crash"; fail=1 ;;
esac
out="$(cd "$br" && python3 "$here/visualize.py" . --no-eval -o "$tmp/br-report.html" 2>&1)" && [ -f "$tmp/br-report.html" ] \
  && echo "ok   visualize survives [ in scopes" || { echo "FAIL visualize survives [ in scopes"; fail=1; }

# --- file scopes don't widen to the parent dir in coverage ------------
cv="$tmp/cv"; mkdir -p "$cv/src/x" "$cv/.prefixer"
echo x > "$cv/src/file.txt"; echo y > "$cv/src/x/b.ts"
cat > "$cv/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: cv

| prefix | scope | contains |
|--------|-------|----------|
| f: | src/file.txt | one file |
EOF
out="$(cd "$cv" && bash "$here/check_namespaces.sh" . 2>&1)"
case "$out" in
  *"uncovered dir: src/x/"*) echo "ok   file scope doesn't cover sibling dirs" ;;
  *) echo "FAIL file scope doesn't cover sibling dirs"; fail=1 ;;
esac

# --- indented rows parse: one grammar for check, eval, visualize ------
ind="$tmp/ind"; mkdir -p "$ind/src" "$ind/extra" "$ind/.prefixer"
echo x > "$ind/src/s.ts"; echo y > "$ind/extra/e.ts"
printf '# namespaces\nrepo: ind\n\n| prefix | scope | contains |\n|--|--|--|\n| api: | src/** | things |\n  | extra: | extra/** | nested in a list |\n' > "$ind/.prefixer/namespaces.md"
out="$(cd "$ind" && bash "$here/check_namespaces.sh" . 2>&1)"
case "$out" in
  *"checked 2 namespaces"*) echo "ok   indented row counts in lint" ;;
  *) echo "FAIL indented row counts in lint"; fail=1 ;;
esac
out="$(cd "$ind" && bash "$here/eval_repo.sh" . 2>/dev/null | grep -c 'extra:')"
[ "$out" -ge 1 ] && echo "ok   indented row evals" || { echo "FAIL indented row evals"; fail=1; }

# --- scope inside baseline-excluded dirs: n/a, not a fake number ------
gx="$tmp/gx"; mkdir -p "$gx/src" "$gx/vendor" "$gx/.prefixer"
echo needle > "$gx/src/a.ts"
awk 'BEGIN{for(i=0;i<400;i++)print "needle"}' > "$gx/vendor/big.txt"
cat > "$gx/.prefixer/namespaces.md" <<'EOF'
# namespaces
repo: gx

| prefix | scope | contains |
|--------|-------|----------|
| api: | src/** | source |
| vend: | vendor/big.txt | escape hatch |
EOF
out="$(cd "$gx" && bash "$here/eval_scope.sh" . needle vend "vendor/big.txt" 2>/dev/null)"
case "$out" in
  *'"pct_saved":null,"baseline_excluded":true'*) echo "ok   excluded-scope probe flags baseline_excluded" ;;
  *) echo "FAIL excluded-scope probe flags baseline_excluded"; fail=1 ;;
esac
out="$(cd "$gx" && bash "$here/eval_repo.sh" . 2>/dev/null)"
case "$out" in
  *"baseline excludes"*) echo "ok   eval_repo marks excluded-scope rows n/a" ;;
  *) echo "FAIL eval_repo marks excluded-scope rows n/a"; fail=1 ;;
esac

echo
[ "$fail" -eq 0 ] && echo "all checks passed" || { echo "FAILURES"; exit 1; }

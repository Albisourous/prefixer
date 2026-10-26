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
for d in auth api db; do echo x > "$repo/src/$d/${d}Handler.ts"; done
echo x > "$repo/services/payments/checkout/CartFlow.ts"
echo x > "$repo/services/payments/refunds/RefundFlow.ts"
echo x > "$repo/services/orders/checkout/OrderCart.ts"
echo x > "$repo/services/orders/tracking/ShipTrack.ts"
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

echo
[ "$fail" -eq 0 ] && echo "all checks passed" || { echo "FAILURES"; exit 1; }

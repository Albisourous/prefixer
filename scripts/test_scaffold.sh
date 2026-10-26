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
repo2="$tmp/roball"
mkdir -p "$repo2/src"/{RoBallServer,RoBallClient}
echo x > "$repo2/src/RoBallServer/SaveService.luau"
echo x > "$repo2/src/RoBallClient/BeatPulse.client.luau"
bash "$here/init_namespaces.sh" "$repo2" >/dev/null 2>&1
map2="$repo2/.prefixer/namespaces.md"

check "repo slug from dir name"        'repo: roball' "$map2"
check "client segment derived"         'client: | src/RoBallClient/\*\*' "$map2"
check "server segment derived"         'server: | src/RoBallServer/\*\*' "$map2"

# --- refuses to regenerate an existing map ---
if bash "$here/init_namespaces.sh" "$repo2" >/dev/null 2>&1; then
  echo "FAIL regeneration refused"; fail=1
else
  echo "ok   regeneration refused"
fi

echo
[ "$fail" -eq 0 ] && echo "all checks passed" || { echo "FAILURES"; exit 1; }

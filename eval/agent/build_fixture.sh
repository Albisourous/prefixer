#!/usr/bin/env bash
# build_fixture.sh — build a deterministic mid-size repo for the agent
# behavior eval. Each task in tasks.txt has exactly one planted answer
# symbol; the same vocabulary also appears as prose/decoy mentions in
# sibling dirs, so a repo-wide grep pays real output bytes while a
# scoped grep stays cheap. Usage: build_fixture.sh DIR
set -euo pipefail
dir="${1:?usage: build_fixture.sh DIR}"
rm -rf "$dir"
mkdir -p "$dir"
cd "$dir"

emit() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# ---- target files (one unique answer symbol each) ----------------------

emit src/auth/session.ts <<'EOF'
// src/auth/session.ts — session lifecycle
import { store } from "../core/store";
import { issueToken } from "./tokens";

const SESSION_TTL_MS = 30 * 60 * 1000;

export interface Session {
  id: string;
  userId: string;
  createdAt: number;
}

// expireSession is the only place the idle-session ttl is enforced;
// callers poll it from the request middleware and the reaper cron.
export function expireSession(session: Session): boolean {
  const age = Date.now() - session.createdAt;
  if (age <= SESSION_TTL_MS) return false;
  store.delete(`session:${session.id}`);
  return true;
}

export function createSession(userId: string): Session {
  const session = { id: crypto.randomUUID(), userId, createdAt: Date.now() };
  store.set(`session:${session.id}`, session);
  issueToken(session.id);
  return session;
}
EOF

emit src/billing/refunds.ts <<'EOF'
// src/billing/refunds.ts — refund policy and math
import { ledger } from "./ledger";
import { centsOf } from "./money";

export interface Charge { id: string; amount: number; capturedAt: number; }

// calculateRefund applies the sliding window: full refund inside 14
// days, 50% inside 30, nothing after. Prorates partial captures.
export function calculateRefund(charge: Charge, now: number): number {
  const days = (now - charge.capturedAt) / 86_400_000;
  if (days <= 14) return charge.amount;
  if (days <= 30) return Math.floor(charge.amount / 2);
  return 0;
}

export async function issueRefund(charge: Charge): Promise<void> {
  const amount = calculateRefund(charge, Date.now());
  if (amount > 0) await ledger.post(charge.id, -centsOf(amount));
}
EOF

emit src/billing/client.ts <<'EOF'
// src/billing/client.ts — payments gateway client
const MAX_ATTEMPTS = 5;
const BASE_DELAY_MS = 250;

export interface Response { ok: boolean; status: number; body: string; }

// retryPayment retries a gateway call with exponential backoff and
// jitter; only 5xx and network faults are retryable.
export async function retryPayment(fn: () => Promise<Response>): Promise<Response> {
  let last: Response | undefined;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    last = await fn();
    if (last.ok || last.status < 500) return last;
    const delay = BASE_DELAY_MS * 2 ** attempt + Math.random() * 100;
    await new Promise((r) => setTimeout(r, delay));
  }
  return last!;
}
EOF

emit src/api/webhooks.ts <<'EOF'
// src/api/webhooks.ts — inbound webhook handling
import { createHmac, timingSafeEqual } from "node:crypto";

const SECRET = process.env.WEBHOOK_SECRET ?? "dev-secret";

// verifySignature checks the X-Signature header against an HMAC-SHA256
// of the raw body. Rejects before any handler runs.
export function verifySignature(rawBody: string, header: string): boolean {
  const expected = createHmac("sha256", SECRET).update(rawBody).digest("hex");
  if (expected.length !== header.length) return false;
  return timingSafeEqual(Buffer.from(expected), Buffer.from(header));
}

export function handleWebhook(rawBody: string, header: string): number {
  return verifySignature(rawBody, header) ? 202 : 401;
}
EOF

emit frontend/checkout/Cart.tsx <<'EOF'
// frontend/checkout/Cart.tsx — cart step of checkout
import { useCart } from "../lib/state";
import { fmt } from "../lib/format";

// renderCheckout draws the item list, totals and the pay button for
// the checkout flow. Mounted by the /checkout route.
export function renderCheckout(): JSX.Element {
  const cart = useCart();
  return (
    <section className="checkout">
      <h1>Review your order</h1>
      <ul>{cart.items.map((i) => <li key={i.sku}>{i.name} — {fmt(i.price)}</li>)}</ul>
      <p>Total: {fmt(cart.total)}</p>
      <button>Pay now</button>
    </section>
  );
}
EOF

# ---- decoy-bearing hand files ------------------------------------------

emit src/auth/tokens.ts <<'EOF'
// src/auth/tokens.ts — token issuance. tokenExpiryMs is a *token* ttl,
// unrelated to session expiry enforcement.
export const tokenExpiryMs = 15 * 60 * 1000;
export function issueToken(sessionId: string): string {
  return `tok_${sessionId.slice(0, 8)}`;
}
EOF

emit docs/guides/auth.md <<'EOF'
# Auth guide

Sessions last 30 minutes. Session expiry is enforced somewhere in the
auth layer — check the code for where the ttl comparison happens.
Tokens rotate on refresh; expiry checks happen at request time.
EOF

emit tests/auth.test.ts <<'EOF'
// tests/auth.test.ts
import { createSession } from "../src/auth/session";
test("session expiry", () => {
  const s = createSession("u1");
  expect(typeof s.id).toBe("string");
});
EOF

emit docs/api/webhooks.md <<'EOF'
# Webhooks

Every webhook POST carries an X-Signature header: an HMAC-SHA256 of the
raw body. Signature verification happens before dispatch; see the
webhooks module for the comparison.
EOF

emit tests/api.test.ts <<'EOF'
// tests/api.test.ts
test("webhook signature rejected when missing", () => {
  expect(true).toBe(true);
});
EOF

emit src/core/queue.ts <<'EOF'
// src/core/queue.ts — job queue with generic retry (NOT the payments
// client retry; that's in billing)
export async function retryJob(fn: () => Promise<void>): Promise<void> {
  for (let i = 0; i < 3; i++) {
    try { await fn(); return; } catch { /* retry loop */ }
  }
  throw new Error("job failed after retries");
}
EOF

emit docs/guides/billing.md <<'EOF'
# Billing

Refunds follow a sliding window and are prorated on partial captures —
see the refunds module for the exact math. Payment calls may retry
transient gateway faults.
EOF

emit src/orders/fulfillment.ts <<'EOF'
// src/orders/fulfillment.ts — fulfillment talks about refunds only in
// comments; the refund math itself lives in billing.
export function fulfill(orderId: string): void {
  // a cancelled order may be due a refund — billing decides
  void orderId;
}
EOF

emit tests/billing.test.ts <<'EOF'
// tests/billing.test.ts
test("refund window is 14 days", () => {
  expect(14).toBe(14);
});
EOF

emit tests/checkout.test.tsx <<'EOF'
// tests/checkout.test.tsx
test("checkout renders the cart step", () => {
  expect("cart").toBe("cart");
});
EOF

emit src/api/routes.ts <<'EOF'
// src/api/routes.ts — webhook route wires to the webhooks module
import { handleWebhook } from "./webhooks";
export const routes = [
  { method: "POST", path: "/webhooks", handler: handleWebhook },
  { method: "GET", path: "/health", handler: () => 200 },
];
EOF

emit docs/guides/deploy.md <<'EOF'
# Deploy

Checkout traffic routes through the gateway. Cart state is client-side
until the payment step completes.
EOF

emit src/orders/cart.ts <<'EOF'
// src/orders/cart.ts — order-side cart model (server cart; the checkout
// UI renders its own client cart)
export interface CartItem { sku: string; qty: number; price: number; }
export function cartTotal(items: CartItem[]): number {
  return items.reduce((t, i) => t + i.qty * i.price, 0);
}
EOF

# ---- bulk stubs ---------------------------------------------------------
# Each stub is plausible code carrying its dir's vocabulary as decoys.
# Format per line: path|word1,word2,word3
stubs='src/auth/refresh.ts|session,token,refresh
src/auth/guards.ts|session,token,guard
src/api/handlers.ts|request,handler,session
src/api/middleware.ts|request,response,session
src/billing/invoices.ts|invoice,charge,refund
src/billing/ledger.ts|ledger,posting,amount
src/billing/money.ts|cents,amount,currency
src/orders/tracking.ts|order,status,shipment
src/orders/returns.ts|order,return,refund
src/core/engine.ts|engine,pipeline,job
src/core/scheduler.ts|schedule,cron,retry
src/core/store.ts|store,cache,session
src/core/config.ts|config,env,secret
src/gateway/proxy.ts|proxy,upstream,route
src/gateway/ratelimit.ts|rate,limit,retry
src/gateway/upstream.ts|upstream,health,backend
frontend/checkout/Confirm.tsx|checkout,confirm,order
frontend/checkout/Address.tsx|checkout,address,form
frontend/components/Button.tsx|button,click,disabled
frontend/components/Modal.tsx|modal,overlay,dialog
frontend/components/Table.tsx|table,rows,columns
frontend/components/Form.tsx|form,field,submit
frontend/components/Badge.tsx|badge,status,label
frontend/pages/Home.tsx|home,landing,hero
frontend/pages/Login.tsx|login,session,form
frontend/pages/Settings.tsx|settings,refund,preferences
frontend/pages/Dashboard.tsx|dashboard,metrics,charts
frontend/lib/api.ts|fetch,request,retry
frontend/lib/format.ts|format,currency,display
frontend/lib/state.ts|state,store,cart
tests/helpers.ts|test,fixture,helper
tests/fixtures/data.ts|fixture,data,session
scripts/migrate.sh|migrate,schema,database
scripts/seed.sh|seed,data,database
scripts/release.sh|release,tag,version
infra/terraform/vars.tf|variable,region,env'

printf '%s\n' "$stubs" | while IFS='|' read -r path words; do
  [ -n "$path" ] || continue
  name="$(basename "$path" | sed 's/\.[^.]*$//')"
  emit "$path" <<EOF
// $path — generated fixture
const NAME = "$name";

// vocabulary: $words
export function ${name}Init(): number {
  let acc = 0;
  for (const w of ["${words//,/\", \""}"]) {
    acc += w.length;
  }
  return acc;
}

export function ${name}Run(input: string): string {
  const key = NAME + ":" + input;
  return key.trim().toLowerCase();
}
EOF
done

# docs stubs
for d in guides/onboarding api/auth api/orders api/payments; do
  emit "docs/$d.md" <<EOF
# $d

Reference notes for $d. Mentions session handling, retries, and the
checkout flow at a prose level only.
EOF
done

# infra stubs
emit infra/terraform/main.tf <<'EOF'
resource "aws_s3_bucket" "app" {
  bucket = "payfix-app"
}
EOF
emit infra/k8s/deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: payfix }
spec:
  replicas: 2
EOF
emit infra/k8s/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: payfix }
EOF

# dist/ — generated dupes: a root grep pays for them, a scoped grep skips
for f in auth/session auth/tokens billing/client; do
  mkdir -p "dist/src/$(dirname "$f")"
  # echo+cat, not sed 's/^/...\n/': BSD sed emits a literal 'n', and this
  # eval runs on macOS
  { echo '// generated, do not edit'; cat "src/$f.ts"; } > "dist/src/$f.js"
done

emit README.md <<'EOF'
# payfix

A payments-platform monorepo: API, billing, orders, gateway and a web
frontend. Session expiry, refunds, webhook signatures and the checkout
cart each live in exactly one module.
EOF
emit AGENTS.md <<'EOF'
# Guide for agents

TypeScript monorepo. src/ is the backend, frontend/ the web app,
docs/ the guides, tests/ the suites, infra/ the deployment.
EOF
emit package.json <<'EOF'
{ "name": "payfix", "private": true, "version": "0.0.0" }
EOF
emit tsconfig.json <<'EOF'
{ "compilerOptions": { "strict": true, "module": "esnext" } }
EOF

# own worktree — the scaffold derives repo: from the enclosing remote,
# and inside someone else's checkout the fixture would borrow its name
git init -q

n="$(find . -type f -not -path './.prefixer/*' | wc -l | tr -d ' ')"
echo "fixture: $dir ($n files)"

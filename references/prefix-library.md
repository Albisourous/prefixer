# Standard prefix library

Fallback prefixes for when sampling and expert curation are not available.
Rename domains to fit the corpus; keep the `domain type:` shape. Add rows
from real usage; a library that never changes is a library nobody checked.

| prefix | use for | example |
|--------|---------|---------|
| `<d> API reference:` | endpoint, method, or object docs | `billing API reference: refund endpoint` |
| `<d> runbook:` | operational procedures | `auth runbook: session rotation` |
| `<d> architecture decision record:` | ADRs, design decisions | `search ADR: embedding provider choice` |
| `<d> troubleshooting guide:` | symptom→fix docs | `deploy troubleshooting: health check flapping` |
| `<d> postmortem:` | incident reviews | `billing postmortem: duplicate charges 2026-03` |
| `<d> tutorial:` | step-by-step learning docs | `onboarding tutorial: first deploy` |
| `<d> config reference:` | settings, flags, env vars | `gateway config reference: retry budget` |
| `<d> schema definition:` | data shapes, migrations | `db schema: sessions table` |
| `<d> FAQ:` | question-answer pairs | `sso FAQ: token expiry` |
| `<d> changelog entry:` | release notes | `cli changelog: 2.4 breaking flags` |
| `<d> meeting notes:` | dated internal notes | `platform meeting notes: 2026-10-14` |
| `<d> wiki article:` | general internal knowledge | `it wiki article: vpn setup` |
| `<l> <m> function:` | indexed code units | `python auth function: rotate_session` |
| `<l> <m> test spec:` | indexed tests | `go api test spec: TestRateLimit` |
| `<d> CLI help:` | command usage docs | `prefixer CLI help: init namespaces` |

`<d>` = domain of the corpus (payments, auth, deploy…). `<l>` = language,
`<m>` = module, for indexed code.

## Adding a prefix

A new prefix earns a row when three documents in a real corpus would share
it. Fold variants into the existing row (`guide:` and `tutorial:` are the
same artifact). Number-free, stable spelling; the whole point is that the
same domain always reads the same way.

# Research digest: what makes agent skills get adopted and kept

Prepared 2026-11-23 for the prefixer improvement run. Sources:
github.com/garrytan/gstack, github.com/cursor/plugins/tree/main/pstack,
github.com/gaasher/agent-loop-skills, plus general knowledge of the
Agent Skills ecosystem. Distilled so the working agent needs no network.

## gstack (garrytan/gstack, ~142k stars)

Garry Tan's Claude Code setup: 23 opinionated skills that act as a
virtual engineering team (CEO, designer, eng manager, release manager,
doc engineer, QA).

Patterns worth stealing:

- **Role-shaped review.** `/review` reads a diff for the class of bugs
  tests tend to miss; `plan-ceo-review`, `plan-eng-review`,
  `plan-design-review`, `plan-devex-review` attack a plan from
  specialist seats. A council is a shipped feature, not a metaphor.
- **Evidence on the artifact.** `/ship` puts the tests it ran and the
  review results onto the PR itself. Proof travels with the work.
- **Honest marketing.** They published a 100-task eval showing gstack
  does NOT raise bug-fix rate, and say so in the README. Candor builds
  more trust than claims.
- **Mode skills as entry points.** One command (`/autoplan`) reviews a
  plan end to end and routes to the specialist skills. Users learn one
  verb, not twenty-three.
- **Update channels and a config CLI.** `bin/gstack-config set
  update_channel main|stable`; `setup --team` for shared rollout.
  Distribution is engineered, not hoped for.
- **Real-session tools.** Browser skills drive the user's logged-in
  browser instead of a sandbox; the skill earns trust by doing the
  real thing.

## pstack (cursor/plugins, poteto; React core team, ex-Meta/Netflix/Cursor)

A Cursor plugin of daily-driver skills for "write less, but higher
quality code." Directly relevant because it is the same pitch prefixer
makes (rigor over slop) executed at a higher level.

- **`/poteto-mode` is the product.** One mode skill reads the request,
  picks a playbook, and routes to the other skills as steps fire. It
  persists across turns (option+enter) and composes with cursor's
  `/loop`. Users adopt the mode; the mode adopts the skills.
- **Verification language everywhere.** "fearless parallelism": you can
  fan out agents because each produces verifiable work. Skill names are
  verbs with evidence attached: `babysit` drives a PR to merge-ready,
  `shipping` independently verifies a green stack then lands it
  bottom-up, `autopilot-*` runs PR swarms with an owner per PR.
- **Multi-model routing.** Different models per role with a hard tier
  cap, persisted via `/setup-pstack` to `~/.claude/rules/pstack-models.md`.
  Model choice is treated as an engineering decision.
- **Session continuity.** `session plan` resumes a prior agent's
  in-flight work; state handoff is a first-class feature.
- **Blinded evals.** The `eval` skill tests how a prompt/skill change
  affects agent behavior, blinded. Prefixer has `eval/` machinery;
  blinded before/after is the missing rigor.
- **Tone.** Lowercase, first person, opinionated, admits tradeoffs. The
  README itself signals taste.

## agent-loop-skills (gaasher, ~185 stars)

Drop-in agentic loops as open-standard Agent Skills: autoresearch,
scientific writing, data analysis, code/SQL/prompt optimization,
red/blue/purple teaming. The structural template for the council run.

- **Loop anatomy.** Every loop = program (SKILL.md) + artifact slot +
  feedback signal + run ledger + termination condition. Bind the task
  at invocation time; iterate against a real signal until the work is
  actually better.
- **Verification-gated, honestly framed.** Unsupervised loops spin
  forever and ship garbage: at 90% per-step accuracy a 5-step chain
  fails ~40% of the time. Every loop therefore lets an objective
  signal (tests, metric, calibrated judge) decide keep-or-revert, and
  publishes the ledger (see `showcase/tournament-autoresearch`:
  0.734 -> 0.798 val_acc over 11 iterations, 7 kept).
- **Spawn-or-degrade.** Multi-role loops use real isolated subagents
  where the host supports them and inline roles otherwise. Portability
  is a requirement, not a wish; prefixer's AGENTS.md says the same.
- **Tournament pattern.** Competing agents propose a change each step;
  a self-calibrating judge keeps winners, discards regressions. This is
  the council shape the maintainer asked for.
- **Zero heavy deps.** Loops shell out and read results; the skill
  stays Markdown + POSIX.

## What makes a skill get installed and kept (general)

- **The description is the ad.** Frontmatter `description` is what hosts
  show and what routers match; it must name triggers ("Use when...").
  Prefixer's already does; keep it accurate as scope shifts.
- **One obvious entry verb.** gstack has `/ship`-style verbs, pstack has
  `/poteto-mode`. Skills that require remembered discipline lose to
  skills that carry their own trigger (hooks, modes, commands).
- **Value must be visible at the moment of use.** Users keep what they
  can see working. A silent token saving is indistinguishable from no
  saving; narrate the scope choice and the delta.
- **Proof beats prose.** Numbers in the README (prefixer: "79% of
  search-output bytes saved across 18 repos") outperform adjectives.
  Keep the eval honest and publish it.
- **Say when not to use it.** Both prefixer ("When not to prefix") and
  gstack's negative-result README build trust; keep that section real.
- **Progressive disclosure.** Always-loaded text is the cached prefix;
  bulk moves to `references/`. The 5,500-word cap is a feature.
- **Install friction near zero.** `npx skills add`, plugin manifests for
  each host, session-start hook snippets. Already present; protect it.

## Gap read on prefixer today

The plumbing exists: scaffold, lint, scoped-search command, auto-widen,
metrics log, suggest-from-log, doctor, eval corpus, HTML report, CI
template, three host manifests. What a user experiences, though, is
"it wrote a namespaces.md file." The likely-adopted deltas a council
should weigh (the council decides; these are leads, not orders):

- The savings are invisible at use time. Per-search echo and a
  session-end summary would make the value legible ("explain why it is
  using it" is a literal maintainer requirement).
- Discipline still optional. search.sh carries the rule only if the
  agent calls it; hook coverage is install-optional. A mode-style
  always-on posture or stronger hook default closes this.
- No negative-space story for agents: nothing in the map tells the NEXT
  agent why a scope was chosen. `contains` is for disambiguation, not
  rationale; narrating the "why" could be a map row convention or a
  search.sh voice line.
- Eval is byte-level on greps, not agent-behavior-level. A blinded
  task-level eval (pstack `eval` pattern) would prove the claim that
  matters: fewer tool calls, higher first-try hit rate.
- Distribution: not listed on skills.sh-style marketplaces beyond the
  three manifests; README quickstart exists but the "install -> wow"
  path is untested by a fresh-eyes agent.

## Constraints that bind every proposal

- `SKILL.md` body cap: 5,500 words (validator enforces).
- Version must match across SKILL.md, CHANGELOG first heading, three
  plugin manifests, docs/index.html softwareVersion, and the
  integrations workflow pin. `scripts/bump-version.py X.Y.Z` rewrites
  all.
- Every `references/...`, `scripts/...`, `integrations/...`, `SPEC.md`
  path mentioned in SKILL.md must exist (validator enforces).
- No em/en dashes in any .md/.txt/.html/.svg/.yml file in the repo
  (validator scans recursively). Comma, colon, or full stop instead.
- SPEC.md is stable: additive-compatible only. Readers ignore unknown
  lines; writers must not repurpose existing lines.
- Plain language style; run humanizer over user-facing prose.
- Portability: no single-harness assumptions. Spawn-or-degrade for
  multi-agent features.

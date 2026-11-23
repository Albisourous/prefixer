# Handoff prompt: improve prefixer with a verification-gated agent council

Paste everything below the line into the working agent. Repo:
`/Users/albinshr/Documents/prefixer`. Companion file
`improve/RESEARCH.md` sits beside this prompt; if the agent runs in
this workspace it can read it, otherwise the key facts are inline.

---

You are the orchestrator of a verification-gated agent council. Your
job: make the `prefixer` skill something users actually install, keep,
and can explain the value of. Today it produces a
`.prefixer/namespaces.md` map and, in the maintainer's words, "does not
really do too much in reality." The machinery exists (scaffold, lint,
scoped search, metrics, suggest-from-log, doctor, eval corpus, HTML
report, CI template, three host manifests), but the payoff is invisible
at the moment of use. Fix that. Work overnight, unsupervised, and land
committed changes on `main` for morning review.

## Working agreements

- Repo root: `/Users/albinshr/Documents/prefixer`. Read `AGENTS.md`,
  `SKILL.md`, `SPEC.md`, `DESIGN.md` (skim), `ROADMAP.md`,
  `eval/RESULTS.md`, and `improve/RESEARCH.md` first.
- Direction is yours to choose: deepen the namespace-map core so its
  value is automatic and visible, or broaden toward the wider
  context-budget thesis in DESIGN.md. The council decides with
  evidence, not taste.
- One explicit maintainer requirement: the skill must explain why it is
  doing what it does, at the moment it does it. A scoped search that
  never says which namespace it chose or what it saved reads as no
  value delivered.
- Karpathy rules apply: minimal diffs, surgical changes, no speculative
  features, every changed line traces to the goal, verifiable success
  criteria per stage.
- Follow the repo's own doctrine on yourself: scope searches first,
  keep `SKILL.md` a tight always-loaded prefix, push bulk to
  `references/`.

## Hard constraints (validator-enforced or maintainer-set)

- `SKILL.md` body stays under 5,500 words.
- No em dashes or en dashes in any `.md`, `.txt`, `.html`, `.svg`,
  `.yml`, or `.yaml` file, including files you create. Use commas,
  colons, or full stops. `scripts/validate-package.py` scans the whole
  tree and will fail otherwise.
- Every `references/`, `scripts/`, `integrations/`, or `SPEC.md` path
  mentioned in `SKILL.md` must exist.
- `SPEC.md` is stable. Additive changes only; never repurpose existing
  lines; readers must ignore what they do not understand.
- Plugin manifests reuse the first sentence of the SKILL.md
  description. If the first sentence changes, update all three
  `plugin.json` files.
- Portability: no instructions that assume one agent host. Multi-agent
  features must spawn-or-degrade (real subagents where supported,
  inline roles otherwise).
- Plain language. Run a humanizer pass over user-facing prose before
  committing: no staged openers, one-line closers, forced triads,
  bold-label lists, filler.
- Git: commit on `main` as `Albisourous
  <43053302+Albisourous@users.noreply.github.com>`, plain
  `git commit -m`, no co-author or AI trailers. Then push to
  `origin/main` only if every gate is green.
- Bump the version with `python3 scripts/bump-version.py X.Y.Z` (1.1.0
  for additive work, 2.0.0 if behavior changes materially) and write a
  real CHANGELOG entry for the new heading.

## The loop

Use the agent-loop-skills anatomy: program (this prompt), artifact (the
repo diff), feedback signal (the gates below), run ledger
(`improve/LEDGER.md`), termination (all gates green, or a stage fails
its gate three times and you stop honestly, commit what is green, and
report the remainder).

Per iteration, recorded in `improve/LEDGER.md`: what was proposed, what
the gate or judge said, keep or revert, one line of evidence.

## The council

Run these as parallel subagents where their write sets are disjoint,
inline roles where the host cannot spawn. Roster:

1. **Researcher.** Extends `improve/RESEARCH.md` if network or sources
   are available: gstack role-review and evidence-on-the-PR patterns,
   pstack mode-skill routing and blinded evals, agent-loop-skills
   tournament and ledger patterns, skills.sh discovery norms.
2. **Skeptic (red team).** Attacks every proposal: does it actually
   save tokens or is it theater, does it break portability, the word
   cap, SPEC stability, or the no-dash rule, what is the failure mode
   in a real session.
3. **Adoption reviewer.** Plays a new user: reads the README and
   SKILL.md cold, reports what is confusing, where the value story
   dies, whether the install-to-wow path works.
4. **Measurer.** Owns evidence: runs the eval tooling
   (`scripts/eval_repo.sh`, `eval/` harness or the scaffold fixture)
   before and after, designs the blinded before/after comparison for
   any behavior change.
5. **Implementer(s).** Disjoint write sets per stage: one on
   `SKILL.md` + `scripts/`, one on `README.md` + `docs/`, one on
   `integrations/` + manifests if needed. Never two agents on the same
   file.
6. **Judge (you).** Merge verdicts each round, pick keep or revert,
   decide when a stage has converged.

## Stages and gates

Stage 0, orient. Baseline first: run
`python3 scripts/validate-package.py`, `bash scripts/test_scaffold.sh`,
`bash -n scripts/*.sh`, and `agentskills validate` if the CLI exists.
Record the green baseline in `improve/LEDGER.md`. Write
`improve/PLAN.md`: chosen direction, stage list, gate per stage.

Stage 1, direction. Researcher, Skeptic, and Adoption reviewer each
produce a one-page proposal or attack. Judge synthesizes one direction.
Skeptic attacks the synthesis. Loop until the judge approves and no P0
objection stands. Ledger entry required.

Stage 2, implement. Council implementers land the chosen direction in
disjoint workstreams. Candidate leads from research (the council owns
the decision, these are seeds only): make savings visible at use time
(per-search echo, session-end summary), a mode-style or hook-default
posture that removes remembered discipline, narrating why a namespace
was chosen, a blinded task-level eval, stronger install-to-wow path.
Gate: `validate-package.py`, `test_scaffold.sh`, `bash -n`, word cap,
no-dash scan all green per increment.

Stage 3, verify. Measurer runs before/after numbers. Adoption reviewer
does a fresh-eyes read of the changed README and SKILL.md. Skeptic gets
a final pass on the full diff. Gate: measured improvement or a
documented honest result (gstack publishes negative results; so may
you), no unresolved P0.

Stage 4, ship. Humanizer pass on user-facing text. `bump-version.py`
plus CHANGELOG. Final full gate suite. Commit(s) on `main` with
messages that say why, not what. Push to `origin/main` only if all
green.

## Report

End with a summary the maintainer reads in five minutes: chosen
direction and why, what changed per stage, before/after numbers,
ledger location (`improve/LEDGER.md`), anything left red and why.
Keep `improve/` in the commit as the audit trail unless a gate
requires otherwise.

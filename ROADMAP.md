# Roadmap to 1.0

Tracks what stood between v0.11.x and a public 1.0 release. The 1.0
bar: release mechanics exist, community files are complete, the package
conforms to the agentskills.io spec, and a new user can install, verify,
and roll out the skill without reading the source.

## P0: release mechanics

- [x] Audit: version lives in SKILL.md, CHANGELOG, three plugin.json,
  docs/index.html `softwareVersion`, and the integrations/ CI pin.
- [x] `scripts/bump-version.py`: one-command version bump across every
  file the validator checks, plus a new dated CHANGELOG heading.
  Modeled on superpowers' `.version-bump.json` file list.
- [x] `RELEASING.md`: maintainer checklist (bump, validate, test, tag,
  `gh release create`, verify install). Modeled on graphify's.
- [x] `.github/workflows/release.yml`: on `v*` tag push, run validate +
  scaffold test + script syntax checks, verify the tag matches SKILL.md
  and the CHANGELOG has real notes, then create the GitHub release.

## P1: community files

- [x] `CODE_OF_CONDUCT.md`: Contributor Covenant, the file superpowers
  and graphify both ship.
- [x] `SUPPORT.md`: where to get help (docs, doctor output, issues,
  security policy).
- [x] Bug-report form asks for `doctor.sh` output.

## P2: spec conformance and install coverage

- [x] `compatibility:` frontmatter field (agentskills.io spec): bash +
  POSIX tools, Python 3 for visualize.py.
- [x] Dropped the `triggers` field: the official validator rejects
  non-spec frontmatter, and `[user, model]` is Devin's default anyway,
  so the field was redundant. `allowed-tools` stays a YAML list: the
  spec calls its string form experimental and Devin reads the list.
- [x] `install.sh` gained a `windsurf` platform: project
  `.windsurf/skills/prefixer`, global `~/.codeium/windsurf/skills/prefixer`.
  Devin's docs confirm both paths are read.
- [x] Official `skills-ref` validator runs clean (`agentskills
  validate`) and is wired into CI pinned at `skills-ref==0.1.1`.
- [x] `validate-package.py` now also enforces the integrations/ tag pin.

## P3: usability and honesty

- [x] `scripts/doctor.sh`: one-command health check. Map present, lint
  verdict, hook wired, metrics gitignored, install stamps current.
  Prints ok/warn/FAIL, exit code reflects health, `--quiet` for CI.
  Covered by test_scaffold.sh.
- [x] `eval/agent/summarize.py`: negative deltas read as "N% larger",
  not "-271% smaller"; RESULTS.md regenerated.
- [x] `.pre-commit-config.yaml`: validate-package + `bash -n` + the
  scaffold suite before commit, same gates as CI.
- [x] README: community-file links, windsurf install row, doctor
  quickstart step, agent-eval aggregate numbers.
- [x] Docs site + llms.txt synced (windsurf, doctor).

## P4: the cut

- [x] `bump-version.py 1.0.0`, CHANGELOG entry for all of the above.
- [x] Full green: `validate-package.py`, `test_scaffold.sh`, shell
  syntax checks, `agentskills validate`.
- [ ] Tag `v1.0.0` and push: `release.yml` does the rest.
- [ ] Verify the GitHub release notes came from the CHANGELOG section.

## Later (post-1.0 candidates, parking lot)

- Per-host setup docs if install issues show up (addyosmani pattern:
  `docs/<host>-setup.md`).
- `FUNDING.yml`, if sponsorship is wanted.
- Agent-eval fixture may need to grow: the current ~140-file fixture is
  near the size gate where a map earns its keep, so mapped runs show
  negative byte deltas. Grow the fixture or document the expected sign
  per arm.
- A `windsurf` session-start hook location, if the harness adds one
  (today only `.devin/` and `.claude/` hook files are read).

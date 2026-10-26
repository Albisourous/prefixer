# Releasing prefixer

Maintainer-facing release process. Contributors do not need this; see
[CONTRIBUTING.md](CONTRIBUTING.md) for how to propose changes.

A release is a git tag plus a GitHub release. There is no package to
publish: installs read the repo, so the tag is the artifact.

## Steps

1. **Bump the version.** One command rewrites every file the validator
   checks and opens a dated CHANGELOG section:

   ```bash
   python3 scripts/bump-version.py X.Y.Z
   ```

2. **Write the release notes.** Replace the `TODO` line in the new
   CHANGELOG section. Keep the house style: lead with what changed for
   the user, no em/en dashes.

3. **Verify.** Both must be green:

   ```bash
   python3 scripts/validate-package.py
   bash scripts/test_scaffold.sh
   ```

   If README or `docs/` claims depend on eval numbers, refresh
   `eval/RESULTS.md` first (`bash eval/run.sh`, needs network and time).

4. **Commit and tag.** Commit the bump, notes, and any doc updates
   together, push `main`, then tag:

   ```bash
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

5. **The tag does the release.** Pushing `v*` fires `release.yml`: it
   re-runs the full validation, then creates the GitHub release with the
   CHANGELOG section as the notes. Check the workflow run; fix and
   re-tag if it fails.

6. **Verify the install.** Confirm the release line on the repo front
   page, then a clean install reports the new stamp:

   ```bash
   bash scripts/install.sh --global
   cat ~/.agents/skills/prefixer/.prefixer_version   # expect X.Y.Z
   ```

## Version numbering

Semantic versions. A spec-level change to `SPEC.md` or the metrics
schema is major-worthy; new scripts and behavior changes are minor;
fixes and docs are patch. Keep tags contiguous: `v` + the version in
`SKILL.md`, one tag per release.

## Supported versions

Security fixes target only the latest release. See
[SECURITY.md](SECURITY.md).

# integrations: wire the map into the places discipline gets skipped

Small drop-in files for making the namespace map automatic. Nothing here
is required; each one removes a place the skill relied on remembering.

## Session-start injection (`hooks.*.json`)

The skill's weakest step is "read the map once per session"; it depends
on the agent remembering. These snippets put the map in session context
at start, so every search begins scoped with no discipline required.

The easy path is `scripts/install_hook.sh`, which writes the real config
for your install location:

```bash
bash <skill>/scripts/install_hook.sh            # auto-detect .devin/.claude
bash <skill>/scripts/install_hook.sh claude     # merge into .claude/settings.json
```

To do it by hand, copy the shape below into your harness config and fix
the path to wherever the skill lives:

| File | Goes in | Notes |
|---|---|---|
| `hooks.devin.json` | `.devin/hooks.v1.json` | the whole file is the hooks object |
| `hooks.claude.json` | `.claude/settings.json` | merge under the existing `"hooks"` key |

Both fire `session_start.sh --json`, which prints the map plus a
one-line health verdict inside the `additionalContext` envelope both
harnesses read. A stale map reports itself at session start; a missing
map stays silent.

## CI keep-alive (`github-map-check.yml`)

The map rots the day a repo changes shape. Copy
`github-map-check.yml` into a repo's `.github/workflows/` and every PR
lints the map: dead scopes and draft rows fail the build, uncovered dirs
warn. Staleness becomes a review event instead of a silent tax on every
future search.

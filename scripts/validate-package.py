#!/usr/bin/env python3
"""Check prefixer's package files without external dependencies."""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors = []


def fail(msg):
    errors.append(msg)


def read(path):
    try:
        return (ROOT / path).read_text(encoding="utf-8")
    except OSError as error:
        fail(f"cannot read {path}: {error}")
        return ""


skill = read("SKILL.md")
changelog = read("CHANGELOG.md")

fm = re.match(r"^---\n(.*?)\n---\n", skill, re.S)
front = fm.group(1) if fm else ""
if not fm:
    fail("SKILL.md: missing YAML frontmatter")

name = re.search(r"^name:\s*(\S+)", front, re.M)
if not name or name.group(1) != "prefixer":
    fail("SKILL.md: frontmatter name must be 'prefixer'")

ver_m = re.search(r"^\s+version:\s*\"?([\w.\-]+)\"?", front, re.M)
version = ver_m.group(1) if ver_m else None
if not version:
    fail("SKILL.md: missing metadata.version")

desc_m = re.search(r"^description:\s*\|\n((?:[ \t]+.*\n?)+)", front, re.M)
desc = " ".join(desc_m.group(1).split()) if desc_m else ""
first_sentence = re.split(r"(?<=[.!?])\s", desc.strip())[0] if desc else ""
if not desc:
    fail("SKILL.md: missing description")
elif not re.search(r"\buse (when|at|for|to)\b", desc, re.I):
    fail("SKILL.md: description must state triggers ('Use when/at/for ...')")

body = skill[fm.end():] if fm else skill
words = len(body.split())
if words > 5500:
    fail(f"SKILL.md: {words} words exceeds the 5500 cap")

manifests = [
    ".claude-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
    ".devin-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
]
parsed = {}
for m in manifests:
    raw = read(m)
    if raw:
        try:
            parsed[m] = json.loads(raw)
        except json.JSONDecodeError as error:
            fail(f"{m}: bad JSON: {error}")

for m in manifests[:3]:
    p = parsed.get(m, {})
    if version and p.get("version") and p["version"] != version:
        fail(f"{m}: version {p['version']} != SKILL.md {version}")
    if first_sentence and p.get("description") and p["description"] != first_sentence:
        fail(
            f"{m}: description must equal SKILL.md description's first sentence\n"
            f"  got:  {p['description']}\n"
            f"  want: {first_sentence}"
        )

if parsed.get(".claude-plugin/plugin.json", {}).get("skills") != ["./"]:
    fail('.claude-plugin/plugin.json: skills must be ["./"] (root SKILL.md)')

ch_m = re.search(r"^##\s*\[?([\w.\-]+)\]?", changelog, re.M)
if version and ch_m and ch_m.group(1) != version:
    fail(f"CHANGELOG.md: first version {ch_m.group(1)} != SKILL.md {version}")

sv_m = re.search(r'"softwareVersion":\s*"([\w.\-]+)"', read("docs/index.html"))
if version and sv_m and sv_m.group(1) != version:
    fail(f"docs/index.html: softwareVersion {sv_m.group(1)} != SKILL.md {version}")

for m in re.finditer(r"`((?:references|scripts|integrations)/[^`\s]+|SPEC\.md)`", skill):
    if not (ROOT / m.group(1)).exists():
        fail(f"SKILL.md mentions missing file: {m.group(1)}")

for s in sorted((ROOT / "scripts").glob("*.sh")):
    if not s.read_text(encoding="utf-8").startswith("#!"):
        fail(f"{s.relative_to(ROOT)}: missing shebang")

# no em/en dashes in user-facing prose (see AGENTS.md writing style)
SKIP_DIRS = {".git", ".prefixer", "node_modules", ".work", ".fixture", ".runs"}
TEXT_EXT = {".md", ".txt", ".html", ".svg", ".yml", ".yaml"}
DASH = re.compile(r"[—–−―]")
for f in sorted(ROOT.rglob("*")):
    if f.suffix not in TEXT_EXT or not f.is_file():
        continue
    rel = f.relative_to(ROOT)
    if SKIP_DIRS & set(rel.parts):
        continue
    for lineno, line in enumerate(read(str(rel)).splitlines(), 1):
        hit = DASH.search(line)
        if hit:
            fail(f"{rel}:{lineno}: em/en dash in user-facing text")

if errors:
    for e in errors:
        print(f"FAIL {e}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SKILL.md {words} words, version {version}, manifests in sync")

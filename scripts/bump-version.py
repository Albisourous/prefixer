#!/usr/bin/env python3
"""Bump the version everywhere validate-package.py checks.

    python3 scripts/bump-version.py 1.0.0
    python3 scripts/bump-version.py 1.0.0 --date 2026-11-02

Rewrites the version string in SKILL.md, the three plugin manifests,
and docs/index.html, and opens a new dated section at the top of
CHANGELOG.md for the release notes. Refuses a version CHANGELOG.md
already has, so a re-run cannot double-open a section.
"""

import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (path, pattern, replacement template; {v} becomes the new version)
TARGETS = [
    ("SKILL.md", r'(?m)^(  version: )"[\w.\-]+"', r'\g<1>"{v}"'),
    (".claude-plugin/plugin.json", r'(?m)^(  "version": )"[\w.\-]+"', r'\g<1>"{v}"'),
    (".cursor-plugin/plugin.json", r'(?m)^(  "version": )"[\w.\-]+"', r'\g<1>"{v}"'),
    (".devin-plugin/plugin.json", r'(?m)^(  "version": )"[\w.\-]+"', r'\g<1>"{v}"'),
    ("docs/index.html", r'(?m)^(  "softwareVersion": )"[\w.\-]+"', r'\g<1>"{v}"'),
    # the consumer CI template pins the scripts it fetches at a tag
    ("integrations/github-map-check.yml",
     r"(prefixer/v)[\w.\-]+(/scripts/)", r"\g<1>{v}\g<2>"),
]


def fail(msg):
    print(f"bump-version: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    pos = []
    day = date.today().isoformat()
    it = iter(range(1, len(sys.argv)))
    for i in it:
        arg = sys.argv[i]
        if arg == "--date":
            try:
                day = sys.argv[i + 1]
            except IndexError:
                fail("--date needs a YYYY-MM-DD value")
            next(it, None)
        elif arg.startswith("--"):
            fail(f"unknown flag: {arg}")
        else:
            pos.append(arg)
    if len(pos) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", pos[0]):
        fail("usage: bump-version.py X.Y.Z [--date YYYY-MM-DD]")
    new = pos[0]
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
        fail(f"--date wants YYYY-MM-DD, got {day!r}")

    for rel, pattern, repl in TARGETS:
        path = ROOT / rel
        text = path.read_text(encoding="utf-8")
        if not re.search(pattern, text):
            fail(f"{rel}: version line not found")
        out, n = re.subn(pattern, repl.replace("{v}", new), text)
        path.write_text(out, encoding="utf-8")
        print(f"{rel}: {new}")

    ch_path = ROOT / "CHANGELOG.md"
    ch = ch_path.read_text(encoding="utf-8")
    if re.search(rf"^##\s*\[?{re.escape(new)}\]?", ch, re.M):
        fail(f"CHANGELOG.md already has a {new} section")
    heading = f"## [{new}] - {day}\n\n- TODO: release notes\n\n"
    m = re.search(r"^##\s", ch, re.M)
    if not m:
        fail("CHANGELOG.md: no version section found")
    ch_path.write_text(ch[: m.start()] + heading + ch[m.start():], encoding="utf-8")
    print(f"CHANGELOG.md: opened [{new}] section dated {day}")

    print("\nnext: fill in the CHANGELOG notes, then")
    print("  python3 scripts/validate-package.py")
    print("  bash scripts/test_scaffold.sh")
    print(f"  git commit -am 'v{new}' && git tag v{new}")


if __name__ == "__main__":
    main()

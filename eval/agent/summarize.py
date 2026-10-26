#!/usr/bin/env python3
"""summarize.py RUNS_DIR TASKS_FILE — per-run tool telemetry -> markdown.

Reads eval/agent run artifacts:
  <cond>__<task>__r<rep>.jsonl    one tool call per line (hook_posttool.sh)
  <cond>__<task>__r<rep>.out.txt  the agent's final output
  <cond>__<task>__r<rep>.map.md   the map in force during that run, if any

Classifies every call (search / nav / read / other), measures search
output bytes, whether the FIRST pattern search was scoped to the dir
holding the answer (first-try hit), whether the run ever scaffolded a
map itself, and whether the final output names expected_path + symbol.
"""
import json
import re
import sys
from pathlib import Path

SEARCH_RE = re.compile(r"\b(grep|rg|ag|ack)\b|search\.sh|\.prefixer/.*/?search")
NAV_RE = re.compile(r"\b(find|fd|ls|tree|locate)\b")
READ_RE = re.compile(r"\b(cat|head|tail|less|more|sed|awk|perl|python3?)\b")
INIT_RE = re.compile(r"init_namespaces")
TAG_RE = re.compile(r"search\.sh\s+(?:--\S+\s+)*([A-Za-z0-9_.-]+):?")


def kind(rec):
    t = (rec.get("tool") or "").lower()
    blob = json.dumps(rec.get("input") or {}).lower()
    if re.search(r"grep|search|glob", t):
        return "search"
    if re.search(r"read|view|cat|open", t):
        return "read"
    if re.search(r"find|ls|list|tree", t):
        return "nav"
    if SEARCH_RE.search(blob):
        return "search"
    if NAV_RE.search(blob):
        return "nav"
    if READ_RE.search(blob):
        return "read"
    return "other"


def parse_map(path):
    """tag -> list of top dirs covered (scope tokens minus globs)."""
    tag_dirs = {}
    if not path.exists():
        return tag_dirs
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("|") or "---" in line:
            continue
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 3 or "prefix" in cells[1]:
            continue
        tag, scope = cells[1].rstrip(":"), cells[2]
        dirs = []
        for tok in scope.split(","):
            tok = tok.strip().rstrip("/")
            tok = re.sub(r"/\*\*$", "", tok)
            tok = re.sub(r"/\*$", "", tok)
            if "/" in tok:
                tok = tok.rsplit("/", 1)[0]
            if tok and "*" not in tok and "?" not in tok and "{" not in tok:
                dirs.append(tok)
        tag_dirs[tag] = dirs
    return tag_dirs


def scoped_to_dir(blob, tag_dirs, want_dir):
    """Was this search call confined to want_dir? Either it names a path
    inside want_dir, or it calls search.sh with a tag whose scope covers
    want_dir."""
    if want_dir in blob:
        return True
    m = TAG_RE.search(blob)
    if m:
        for d in tag_dirs.get(m.group(1), []):
            if d == want_dir or want_dir.startswith(d + "/") or d.startswith(want_dir):
                return True
    return False


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: summarize.py RUNS_DIR TASKS_FILE")
    runs, tasks_file = Path(sys.argv[1]), Path(sys.argv[2])
    tasks = {}
    for line in tasks_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "|" not in line:
            continue
        # rsplit the last two fields: a prompt may itself contain '|'
        tid, rest = line.split("|", 1)
        parts = [p.strip() for p in rest.rsplit("|", 2)]
        if len(parts) != 3:
            print(f"warn: malformed task line skipped: {line!r}",
                  file=sys.stderr)
            continue
        tasks[tid.strip()] = (parts[1], parts[2])

    rows = []
    for out_f in sorted(runs.glob("*__r*.out.txt")):
        stem = out_f.name[:-8]
        cond, tid, _rep = stem.split("__")
        epath, esym = tasks.get(tid, ("", ""))
        want_dir = str(Path(epath).parent)
        log_f = runs / (stem + ".jsonl")
        map_f = runs / (stem + ".map.md")
        tag_dirs = parse_map(map_f)
        recs = []
        if log_f.exists():
            for line in log_f.read_text().splitlines():
                try:
                    recs.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        kinds = [kind(r) for r in recs]
        searches = [r for r, k in zip(recs, kinds) if k == "search"]
        search_bytes = sum(r.get("out_bytes", 0) for r in searches)
        total_bytes = sum(r.get("out_bytes", 0) for r in recs)
        first_try = False
        if searches:
            blob = json.dumps(searches[0].get("input") or {}).lower()
            first_try = scoped_to_dir(blob, tag_dirs, want_dir)
        out = out_f.read_text(errors="replace")
        success = bool(epath and epath in out and esym and esym in out)
        self_init = any(INIT_RE.search(json.dumps(r.get("input") or {}))
                        for r in recs)
        rows.append({
            "cond": cond, "tid": tid, "tools": len(recs),
            "searches": len(searches),
            "search_bytes": search_bytes, "total_bytes": total_bytes,
            "first_try": first_try, "success": success,
            "self_init": self_init,
        })

    print("# Agent-behavior eval\n")
    print("Every tool call logged (PostToolUse hook or the ACP")
    print("session/update stream, adapter-dependent); final output checked")
    print("for expected path + symbol. Arms differ only in the map:")
    print("`baseline` has no `.prefixer/`, `mapped` has the scaffolded map")
    print("injected at session start. Agents are stochastic; read means,")
    print("not single runs.\n")
    print("| task | arm | tool calls | searches | search bytes | total bytes |"
          " first-try scoped | correct answer | self-init map |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['tid']} | {r['cond']} | {r['tools']} | {r['searches']} "
              f"| {r['search_bytes']} | {r['total_bytes']} "
              f"| {'yes' if r['first_try'] else 'no'} "
              f"| {'yes' if r['success'] else 'no'} "
              f"| {'yes' if r['self_init'] else ''} |")

    print("\n## Aggregates\n")
    print("| arm | runs | mean calls | mean searches | mean search bytes |"
          " mean total bytes | first-try % | success % |")
    print("|---|---|---|---|---|---|---|---|")
    agg = {}
    for cond in ("baseline", "mapped"):
        rs = [r for r in rows if r["cond"] == cond]
        if not rs:
            continue
        n = len(rs)
        a = {k: sum(r[k] for r in rs) / n
             for k in ("tools", "searches", "search_bytes", "total_bytes")}
        ft = 100 * sum(r["first_try"] for r in rs) / n
        su = 100 * sum(r["success"] for r in rs) / n
        agg[cond] = a
        print(f"| {cond} | {n} | {a['tools']:.1f} | {a['searches']:.1f} "
              f"| {a['search_bytes']:.0f} | {a['total_bytes']:.0f} "
              f"| {ft:.0f}% | {su:.0f}% |")
    if "baseline" in agg and "mapped" in agg and agg["baseline"]["search_bytes"]:
        saved = 100 * (1 - agg["mapped"]["search_bytes"]
                       / agg["baseline"]["search_bytes"])
        tsaved = 100 * (1 - agg["mapped"]["total_bytes"]
                        / agg["baseline"]["total_bytes"])
        print(f"\nSearch output bytes: **{saved:.0f}% smaller** with the "
              f"map; total tool-output bytes {tsaved:.0f}% smaller.")


if __name__ == "__main__":
    main()

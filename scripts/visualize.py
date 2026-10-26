#!/usr/bin/env python3
"""Render a repo's .prefixer/ state as a self-contained HTML report.

The map painted onto the file tree — every file colored by the namespace
that scopes it — plus the measured delta: the same grep at repo root vs
inside each namespace's globs. Stdlib only; the output is one file with
no external assets.

usage: visualize.py [repo-root] [-o OUT] [--no-eval] [--max-files N] [--open]
       --max-files N caps the file rows shown per directory (default 60)
"""
import html
import json
import os
import re
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone
from pathlib import Path

SKIP = {"node_modules", "vendor", "dist", "build", "target", "out", ".git",
        ".prefixer", ".work", "__pycache__", ".next", ".cache", "venv", ".venv",
        ".idea", ".vscode", "coverage", ".turbo", ".output", ".nuxt",
        ".svelte-kit", "storybook-static", "DerivedData", "Pods",
        "bin", "obj"}

PALETTE = ["#2dd4bf", "#60a5fa", "#f472b6", "#a3e635", "#facc15", "#fb923c",
           "#c084fc", "#34d399", "#22d3ee", "#e879f9", "#f87171", "#94a3b8"]


def skipped(name):
    return name in SKIP or name.endswith("-out")


def esc(s):
    return html.escape(str(s), quote=True)


def fmt_bytes(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def fmt_num(n):
    return f"{n:,}"


def expand_scope(scope):
    """{a,b} arms, then comma split — the tokens a searching shell sees."""
    def expand(s):
        i = s.find("{")
        if i < 0:
            return [s]
        depth, close = 0, -1
        for k in range(i, len(s)):
            if s[k] == "{":
                depth += 1
            elif s[k] == "}":
                depth -= 1
                if depth == 0:
                    close = k
                    break
        if close < 0:
            return [s]
        inner, depth, last, arms = s[i + 1:close], 0, 0, []
        for k, ch in enumerate(inner):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            elif ch == "," and depth == 0:
                arms.append(inner[last:k])
                last = k + 1
        arms.append(inner[last:])
        out = []
        for arm in arms:
            out += expand(s[:i] + arm + s[close + 1:])
        return out

    toks = []
    for e in expand(scope):
        toks += [t.strip() for t in e.split(",")]
    return [t for t in dict.fromkeys(toks) if t]


def glob_re(g):
    """Shell glob -> anchored regex. * stays inside its dir level, **
    crosses, ? is one non-/ char, a leading / anchors at repo root —
    same semantics as the shell scripts."""
    out, i = [], 0
    g = g[1:] if g.startswith("/") else g
    while i < len(g):
        if g[i:i + 2] == "**":
            out.append("\x00")
            i += 2
        elif g[i] == "*":
            out.append("[^/]*")
            i += 1
        elif g[i] == "?":
            out.append("[^/]")
            i += 1
        elif g[i] in ".+^$|()[]{}\\":
            # char classes are not scope syntax — brackets are literal,
            # so no scope can produce an invalid regex
            out.append("\\" + g[i])
            i += 1
        else:
            out.append(g[i])
            i += 1
    s = "".join(out)
    s = s.replace("\x00/", "(.*/)?").replace("\x00", ".*")
    return "^" + s + "$"


def parse_map(map_path):
    """Markdown table -> rows with composed tags, rebuilt from indentation
    the same way check_namespaces.sh validates them."""
    repo, rows, stack = None, [], {}
    for line in map_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^repo:\s*(.+)", line)
        if m and repo is None:
            repo = m.group(1).strip()
        if not line.lstrip().startswith("|"):
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue
        pf, scope, cont = parts[1], parts[2].strip(), parts[3].strip()
        name = pf.strip().rstrip(":").strip()
        if not name or name == "prefix" or name.startswith("-"):
            continue
        lvl = len(pf) - len(pf.lstrip())
        for k in [k for k in stack if k >= lvl]:
            del stack[k]
        parent = None
        for k in range(lvl - 1, -1, -1):
            if k in stack:
                parent = stack[k]
                break
        tag = f"{parent}:{name}" if parent else name
        stack[lvl] = tag
        draft = name.startswith("todo-") or "TODO" in cont or "undocumented" in cont
        toks = expand_scope(scope)
        rows.append({
            "tag": tag, "leaf": name, "scope": scope, "contains": cont,
            "lvl": lvl, "draft": draft, "tokens": toks,
            "res": [re.compile(glob_re(t)) for t in toks],
            "n_files": 0, "bytes": 0, "overlap": 0, "eval": None,
        })
    return repo, rows


def walk(root):
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not skipped(d))
        for fn in sorted(filenames):
            p = Path(dirpath) / fn
            try:
                size = p.stat().st_size
            except OSError:
                size = 0
            files.append((p.relative_to(root).as_posix(), size))
    return files


def assign(files, rows):
    """Each file -> first row in map order that scopes it (the order an
    agent reads the map). Overlaps are counted, not double-assigned."""
    owner = {}
    for rel, size in files:
        hit = -1
        for i, row in enumerate(rows):
            if any(rx.match(rel) for rx in row["res"]):
                row["overlap"] += 1
                if hit < 0:
                    hit = i
        if hit >= 0:
            rows[hit]["n_files"] += 1
            rows[hit]["bytes"] += size
        owner[rel] = hit
    return owner


def run_eval(root, rows):
    """Reuse eval_scope.sh — the honest number, not an estimate."""
    script = Path(__file__).resolve().parent / "eval_scope.sh"
    if not script.exists():
        print("warn: eval_scope.sh not found beside visualize.py; "
              "coverage shown without measured savings", file=sys.stderr)
        return
    for row in rows:
        try:
            out = subprocess.run(
                ["bash", str(script), str(root), row["leaf"], row["tag"],
                 row["scope"]],
                capture_output=True, text=True, timeout=180)
            line = out.stdout.strip().splitlines()
            if out.returncode == 0 and line:
                row["eval"] = json.loads(line[-1])
        except (OSError, json.JSONDecodeError, subprocess.TimeoutExpired):
            pass


def read_metrics(path):
    entries = []
    if not path.exists():
        return entries
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("error"):
            e["kind"] = "error"
        elif e.get("baseline"):
            e["kind"] = "baseline"
        elif e.get("task") == "eval-scope" or "pct_saved" in e:
            e["kind"] = "eval"
        elif "tool_calls" in e or "first_try_hit" in e or e.get("searches", 1) != 1:
            e["kind"] = "task"
        else:
            e["kind"] = "search"
        entries.append(e)
    return entries


def metrics_fallback(rows, entries):
    """--no-eval: reuse the latest logged eval-scope line per tag."""
    latest = {}
    for e in entries:
        if e.get("kind") == "eval" and e.get("ns"):
            latest[e["ns"]] = e
    for row in rows:
        if row["tag"] in latest:
            row["eval"] = latest[row["tag"]]


# ---------------------------------------------------------------- tree

def build_tree(files, owner):
    tree = {"dirs": {}, "files": []}
    for rel, size in files:
        parts = rel.split("/")
        node = tree
        for d in parts[:-1]:
            node = node["dirs"].setdefault(d, {"dirs": {}, "files": []})
        node["files"].append((parts[-1], owner[rel], size, rel))
    return tree


def count_files(node):
    return len(node["files"]) + sum(count_files(v) for v in node["dirs"].values())


def render_tree(node, depth, file_cap, capped):
    """Full in-memory tree; each directory lists at most file_cap rows so a
    vendored-size subtree cannot drown the report. `capped` collects a
    marker per directory that hit the cap, for the footnote."""
    out = []
    for name in sorted(node["dirs"]):
        sub = node["dirs"][name]
        n = count_files(sub)
        open_attr = " open" if depth < 3 and n <= 250 else ""
        out.append(
            f'<details class="d"{open_attr}><summary><span class="dn">{esc(name)}/</span>'
            f'<span class="dc">{n} file{"s" if n != 1 else ""}</span></summary>'
            f'<ul class="dl">{render_tree(sub, depth + 1, file_cap, capped)}</ul></details>')
    for fname, ns, size, rel in sorted(node["files"])[:file_cap]:
        color = PALETTE[ns % len(PALETTE)] if ns >= 0 else "#30363d"
        out.append(
            f'<li class="f" data-ns="{ns}" title="{esc(rel)}">'
            f'<i style="background:{color}"></i>{esc(fname)}'
            f'<em>{fmt_bytes(size)}</em></li>')
    rest = len(node["files"]) - file_cap
    if rest > 0:
        capped.append(1)
        out.append(f'<li class="f more">… {rest} more file'
                   f'{"s" if rest != 1 else ""}</li>')
    return "".join(out)


# ---------------------------------------------------------------- html

CSS = """
:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8b949e;--teal:#2dd4bf;--blue:#60a5fa;
--border:#30363d;--red:#f87171;--panel:#161b22}
*{box-sizing:border-box;margin:0}
body{background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,"Segoe UI",
Helvetica,Arial,sans-serif;max-width:960px;margin:0 auto;padding:48px 24px}
h1{font-size:1.5rem;margin:0 0 4px}
.sub{color:var(--muted);font-size:.85rem;margin-bottom:32px;font-family:
ui-monospace,SFMono-Regular,Menlo,monospace}
h2{font-size:1.05rem;margin:36px 0 14px;color:var(--teal);font-weight:600}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
gap:12px;margin:0 0 8px}
.card{border:1px solid var(--border);border-radius:8px;padding:14px 16px}
.card strong{display:block;font-size:1.4rem;line-height:1.2;background:
linear-gradient(90deg,var(--teal),var(--blue));-webkit-background-clip:text;
background-clip:text;color:transparent}
.card span{color:var(--muted);font-size:.78rem}
table{border-collapse:collapse;width:100%;font-size:.85rem}
td,th{border-bottom:1px solid var(--border);padding:7px 10px;text-align:left;
vertical-align:top}
th{color:var(--muted);font-weight:600;font-size:.75rem;text-transform:uppercase;
letter-spacing:.04em}
td code{background:var(--panel);border:1px solid var(--border);border-radius:5px;
padding:1px 6px;font-size:.8em;font-family:ui-monospace,SFMono-Regular,Menlo,
monospace;white-space:nowrap}
.tag{display:inline-block;padding:1px 8px;border-radius:10px;font-weight:600;
font-size:.8rem;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
color:#0d1117;white-space:nowrap}
.child{margin-left:14px}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:.78rem;
font-weight:600}
.b-hi{background:#123f36;color:#2dd4bf}.b-mid{background:#3d2e0a;color:#facc15}
.b-lo{background:#3d1414;color:#f87171}.b-none{color:var(--muted)}
.draft{color:#f87171;font-size:.75rem}
.part{display:flex;height:26px;border-radius:6px;overflow:hidden;
border:1px solid var(--border);margin:0 0 10px}
.part div{min-width:0}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 14px}
.chip{border:1px solid var(--border);border-radius:14px;padding:3px 12px;
font-size:.78rem;cursor:pointer;background:var(--panel);color:var(--fg);
font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.chip i{display:inline-block;width:9px;height:9px;border-radius:50%;
margin-right:6px}
.chip.on{outline:2px solid var(--teal)}
.tree{border:1px solid var(--border);border-radius:8px;padding:12px 16px;
font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.8rem;
max-height:560px;overflow:auto}
.tree ul{list-style:none;padding-left:18px}
.tree>ul,.tree details>ul{padding-left:18px}
.dl{border-left:1px solid var(--border);margin-left:4px}
details.d{margin:1px 0}
details.d>summary{cursor:pointer;padding:1px 4px;list-style:none;color:var(--fg)}
details.d>summary::-webkit-details-marker{display:none}
details.d>summary::before{content:"▸";display:inline-block;width:12px;
color:var(--muted);transition:transform .1s}
details.d[open]>summary::before{transform:rotate(90deg)}
.dn{color:var(--blue)}
.dc{color:var(--muted);font-size:.72rem;margin-left:8px}
li.f{padding:1px 4px 1px 16px;color:#c9d1d9;white-space:nowrap;
overflow:hidden;text-overflow:ellipsis}
li.f i{display:inline-block;width:8px;height:8px;border-radius:2px;
margin-right:7px}
li.f em{color:var(--muted);font-style:normal;font-size:.72rem;margin-left:8px}
li.f.more{color:var(--muted);font-style:italic}
li.f.dim{opacity:.18}
.bar-row{margin:0 0 10px}
.bar-lbl{display:flex;justify-content:space-between;font-size:.78rem;
font-family:ui-monospace,SFMono-Regular,Menlo,monospace;margin-bottom:3px}
.bar-lbl .t{color:var(--fg)}
.bar-lbl .n{color:var(--muted)}
.bar-track{position:relative;height:16px}
.bar-root{position:absolute;left:0;top:0;height:16px;background:#3d1414;
border-radius:3px}
.bar-ns{position:absolute;left:0;top:3px;height:10px;background:var(--teal);
border-radius:2px}
.legend{color:var(--muted);font-size:.78rem;margin:0 0 12px}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;
margin:0 4px 0 12px;vertical-align:-1px}
.legend i:first-child{margin-left:0}
.note{color:var(--muted);font-size:.85rem}
footer{margin-top:48px;padding-top:16px;border-top:1px solid var(--border);
color:var(--muted);font-size:.8rem}
svg.tl{display:block;width:100%;height:auto}
.miss{color:var(--muted)}
"""


def badge(pct):
    if pct is None:
        return '<span class="badge b-none">-</span>'
    cls = "b-hi" if pct >= 80 else "b-mid" if pct >= 50 else "b-lo"
    return f'<span class="badge {cls}">{pct}%</span>'


def render(rows, repo, root, files, owner, entries, evaled, file_cap):
    total = len(files)
    ns_files = sum(r["n_files"] for r in rows)
    # 100% means every file scoped — a single unscoped file must not
    # round up into a claim the map doesn't back
    cov = (100 if ns_files == total else min(99, int(100 * ns_files / total))
           ) if total else 0
    evals = [r["eval"] for r in rows if r["eval"]]
    # honest evals only: 0-hit probes are blind spots, and a scope living
    # inside baseline-excluded dirs compares two different universes —
    # neither proves a saving (same rule eval_repo.sh applies)
    hevals = [e for e in evals
              if isinstance(e.get("pct_saved"), int) and e["pct_saved"] >= 0
              and e.get("ns_hits", 1) > 0]
    mean_pct = (round(sum(e["pct_saved"] for e in hevals) / len(hevals))
                if hevals else None)
    mean_tok = (round(sum(e.get("est_tokens_saved", 0) for e in hevals) / len(hevals))
                if hevals else None)
    tasks = [e for e in entries if e["kind"] == "task"]
    hits = [e for e in tasks if e.get("first_try_hit") is True]
    hit_known = [e for e in tasks if "first_try_hit" in e]
    hit_rate = (round(100 * len(hits) / len(hit_known)) if hit_known else None)
    drafts = sum(1 for r in rows if r["draft"])
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    color = {i: PALETTE[i % len(PALETTE)] for i in range(len(rows))}

    cards = [
        (str(len(rows)), "namespaces" + (f", {drafts} draft" if drafts else "")),
        (f"{cov}%", f"files scoped · {fmt_num(ns_files)}/{fmt_num(total)}"),
        (f"{mean_pct}%" if mean_pct is not None else "-",
         "mean search bytes saved" + ("" if evaled else " (from log)")),
        (f"~{fmt_num(mean_tok)}" if mean_tok is not None else "-",
         "est. tokens saved / query"),
        (f"{hit_rate}%" if hit_rate is not None else fmt_num(total - ns_files),
         (f"first-try hit rate · n={len(hit_known)}" if hit_rate is not None
          else "unscoped files")),
    ]

    out = [f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>prefixer map · {esc(repo)}</title>
<style>{CSS}</style></head><body>
<h1>prefixer map · <span style="color:var(--teal)">{esc(repo)}</span></h1>
<div class="sub">{esc(root)} · generated {ts}</div>
<div class="cards">"""]
    out += [f'<div class="card"><strong>{esc(v)}</strong><span>{esc(k)}</span></div>'
            for v, k in cards]
    out.append("</div>")

    # ---- the map
    out.append("<h2>The map</h2><table><tr><th>tag</th><th>scope</th>"
               "<th>contains</th><th>files</th><th>saved</th></tr>")
    for i, r in enumerate(rows):
        ind = ' class="child"' if r["lvl"] else ""
        draft = ' <span class="draft">draft</span>' if r["draft"] else ""
        ev = r["eval"]
        pct = ev.get("pct_saved") if ev else None
        if ev and (pct is None or pct < 0 or ev.get("ns_hits", 1) == 0):
            pct = None  # n/a — same honesty rule as eval_repo.sh
        out.append(
            f'<tr><td><span class="tag" style="background:{color[i]}">'
            f'{esc(r["tag"])}:</span></td>'
            f'<td{ind}><code>{esc(r["scope"])}</code>{draft}</td>'
            f'<td>{esc(r["contains"])}</td>'
            f'<td>{fmt_num(r["n_files"])}</td><td>{badge(pct)}</td></tr>')
    out.append("</table>")

    # ---- coverage
    unscoped = total - ns_files
    out.append('<h2>Coverage: every file, colored by the namespace that scopes it</h2>')
    out.append('<div class="part">')
    for i, r in enumerate(rows):
        w = 100 * r["n_files"] / total if total else 0
        if w > 0:
            out.append(f'<div style="width:{w:.2f}%;background:{color[i]}" '
                       f'title="{esc(r["tag"])}: {r["n_files"]} files"></div>')
    if unscoped:
        out.append(f'<div style="width:{100 * unscoped / total:.2f}%;background:#21262d" '
                   f'title="unscoped: {unscoped} files"></div>')
    out.append('</div><div class="chips">')
    out.append('<button class="chip on" data-ns="all"><i style="background:#e6edf3"></i>all</button>')
    for i, r in enumerate(rows):
        out.append(f'<button class="chip" data-ns="{i}"><i style="background:{color[i]}">'
                   f'</i>{esc(r["tag"])}: <span class="miss">{r["n_files"]}</span></button>')
    if unscoped:
        out.append(f'<button class="chip" data-ns="-1"><i style="background:#30363d">'
                   f'</i>unscoped <span class="miss">{unscoped}</span></button>')
    out.append('</div>')
    capped = []
    tree_html = render_tree(build_tree(files, owner), 0, file_cap, capped)
    out.append(f'<div class="tree"><ul>{tree_html}</ul></div>')
    if capped:
        out.append(f'<p class="note">Directories list their first {file_cap} '
                   f'files (--max-files to change); counts above are complete.</p>')

    # ---- scoped vs root
    out.append('<h2>Scoped vs root: the same grep, two scopes</h2>')
    if evals:
        maxb = max((e.get("root_bytes", 0) for e in evals), default=1) or 1
        out.append('<div class="legend"><i style="background:#3d1414"></i>root grep'
                   '<i style="background:var(--teal)"></i>scoped grep: bytes of '
                   'output the agent would have to read</div>')
        for i, r in enumerate(rows):
            e = r["eval"]
            if not e:
                continue
            rb, sb = e.get("root_bytes", 0), e.get("ns_bytes", 0)
            pct = e.get("pct_saved")
            ptxt = (f"{pct}%" if isinstance(pct, int) and pct >= 0
                    and e.get("ns_hits", 1) > 0 else "n/a")
            out.append(
                f'<div class="bar-row"><div class="bar-lbl">'
                f'<span class="t" style="color:{color[i]}">{esc(r["tag"])}:</span>'
                f'<span class="n">{fmt_bytes(rb)} → {fmt_bytes(sb)} · '
                f'~{fmt_num(e.get("est_tokens_saved", 0))} tok saved · {ptxt}</span></div>'
                f'<div class="bar-track">'
                f'<div class="bar-root" style="width:{100 * rb / maxb:.1f}%"></div>'
                f'<div class="bar-ns" style="width:{100 * sb / maxb:.1f}%"></div>'
                f'</div></div>')
        if mean_pct is not None:
            out.append(f'<p class="note">mean {mean_pct}% of search-output bytes '
                       f'saved across {len(hevals)} measurable namespaces'
                       f'{"" if evaled else " (latest logged evals)"}. '
                       f'probe: each row\'s own name.</p>')
    else:
        out.append('<p class="note">No measured evals. Re-run without '
                   '<code>--no-eval</code> to probe every namespace with '
                   'eval_scope.sh, or log evals via <code>eval_scope.sh --log</code>.</p>')

    # ---- search log
    if entries:
        out.append('<h2>Search log: metrics.jsonl</h2>')
        n_tok = sum(e.get("est_tokens", e.get("est_tokens_saved", 0))
                    for e in entries if e["kind"] != "error")
        searches = [e.get("searches", 1) for e in tasks]
        mean_s = f"{sum(searches) / len(searches):.1f}" if searches else "-"
        out.append(f'<p class="note">{len(entries)} log lines · {len(tasks)} tasks · '
                   f'mean {mean_s} searches/task · ~{fmt_num(n_tok)} est. tokens total'
                   + (f' · first-try hits {len(hits)}/{len(hit_known)}' if hit_known else "")
                   + '</p>')
        vals = [e.get("est_tokens", e.get("est_tokens_saved", 0)) for e in entries]
        vmax = max(vals) or 1
        W, H, BH = 900, 140, 100
        bw = max(2, W / max(len(entries), 1) - 2)
        kinds = {"baseline": "#60a5fa", "eval": "#c084fc",
                 "task": "#2dd4bf", "search": "#8b949e", "error": "#f87171"}
        svg = [f'<svg class="tl" viewBox="0 0 {W} {H}" role="img">']
        for i, e in enumerate(entries):
            x = i * (W / len(entries))
            h = max(2, BH * vals[i] / vmax)
            svg.append(
                f'<rect x="{x:.1f}" y="{H - 20 - h:.1f}" width="{bw:.1f}" height="{h:.1f}" '
                f'fill="{kinds[e["kind"]]}" rx="1"><title>{esc(e.get("ts", ""))} '
                f'{esc(e.get("task", e.get("ns", "")))}: '
                f'~{fmt_num(vals[i])} tokens</title></rect>')
            if e.get("first_try_hit") is True:
                svg.append(f'<circle cx="{x + bw / 2:.1f}" cy="{H - 14 - h:.1f}" r="2.4" '
                           f'fill="#3fb950"><title>first-try hit</title></circle>')
        svg.append(f'<line x1="0" y1="{H - 20}" x2="{W}" y2="{H - 20}" stroke="#30363d"/>')
        svg.append('</svg>')
        out.append("".join(svg))
        out.append('<div class="legend"><i style="background:#2dd4bf"></i>task'
                   '<i style="background:#8b949e"></i>search'
                   '<i style="background:#c084fc"></i>eval probe'
                   '<i style="background:#60a5fa"></i>baseline'
                   '<i style="background:#f87171"></i>failed probe'
                   '<i style="background:#3fb950"></i>first-try hit</div>')

    out.append(f"""<footer>Generated by <code>scripts/visualize.py</code> from
<code>.prefixer/namespaces.md</code>{", eval_scope.sh probes" if evaled else ""}
{" + .prefixer/metrics.jsonl" if entries else ""}. The map is the interface;
this file is telemetry, safe to delete or gitignore.</footer>
<script>
document.querySelectorAll('.chip').forEach(function(c){{
  c.addEventListener('click',function(){{
    var ns=c.dataset.ns;
    document.querySelectorAll('.chip').forEach(function(x){{x.classList.remove('on')}});
    c.classList.add('on');
    document.querySelectorAll('li.f').forEach(function(f){{
      f.classList.toggle('dim', ns!=='all' && f.dataset.ns!==ns);
    }});
  }});
}});
</script></body></html>""")
    return "".join(str(o) for o in out)


def main(argv):
    root, args = Path.cwd(), argv[1:]
    if args and not args[0].startswith("-"):
        root, args = Path(args[0]).resolve(), args[1:]
    out_path, do_eval, open_it, max_files = None, True, False, 60

    def usage():
        print("usage: visualize.py [repo-root] [-o OUT] [--no-eval] "
              "[--max-files N] [--open]", file=sys.stderr)
        return 2

    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-o", "--max-files"):
            i += 1
            if i >= len(args):
                return usage()
            if a == "-o":
                out_path = Path(args[i])
            else:
                try:
                    max_files = int(args[i])
                except ValueError:
                    return usage()
                if max_files < 1:
                    return usage()
        elif a == "--no-eval":
            do_eval = False
        elif a == "--open":
            open_it = True
        else:
            return usage()
        i += 1

    map_path = root / ".prefixer" / "namespaces.md"
    if not map_path.exists():
        print(f"no map at {map_path}; run init_namespaces.sh first", file=sys.stderr)
        return 1

    repo, rows = parse_map(map_path)
    if not rows:
        print(f"no namespace rows in {map_path}", file=sys.stderr)
        return 1
    repo = repo or root.name

    files = walk(root)
    owner = assign(files, rows)

    entries = read_metrics(root / ".prefixer" / "metrics.jsonl")
    if do_eval:
        run_eval(root, rows)
    else:
        metrics_fallback(rows, entries)
    evaled = do_eval and any(r["eval"] for r in rows)

    if out_path is None:
        out_path = root / ".prefixer" / "report.html"
    out_path.write_text(render(rows, repo, str(root), files, owner, entries,
                               evaled, max_files),
                        encoding="utf-8")

    # report.html is generated telemetry — gitignore it like metrics.jsonl
    gi = root / ".prefixer" / ".gitignore"
    try:
        lines = gi.read_text().splitlines() if gi.exists() else []
        if "report.html" not in lines:
            with gi.open("a") as f:
                f.write("report.html\n")
    except OSError:
        pass

    n_files = sum(r["n_files"] for r in rows)
    evals = [r["eval"] for r in rows if r["eval"]]
    hevals = [e for e in evals
              if isinstance(e.get("pct_saved"), int) and e["pct_saved"] >= 0
              and e.get("ns_hits", 1) > 0]
    mean = (round(sum(e["pct_saved"] for e in hevals) / len(hevals))
            if hevals else None)
    print(f"wrote {out_path}")
    print(f"{len(rows)} namespaces · {n_files}/{len(files)} files scoped"
          + (f" · mean {mean}% search bytes saved" if mean is not None else ""))
    if open_it:
        webbrowser.open(out_path.resolve().as_uri())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

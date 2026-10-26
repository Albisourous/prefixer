#!/usr/bin/env python3
"""acp_run.py — drive a headless Devin session over ACP (devin acp).

Used by eval/agent/adapters/devin_acp.sh when the standalone `devin -p`
path can't authenticate (the bundled CLI wants Devin-account creds; the
ACP server accepts the Windsurf API key the app already stores).

    acp_run.py --cwd DIR --log LOG.jsonl --out OUT.txt [--prefix TEXT]
               [--timeout SECS] [--check] -- PROMPT

Writes the same JSONL shape hook_posttool.sh produces (one line per
completed tool call: {tool, input, out_bytes, ok}) so summarize.py reads
it unchanged. Agent message text lands in OUT.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

DEFAULT_BIN = "/Applications/Devin.app/Contents/Resources/app/extensions/windsurf/devin/bin/devin"


def api_key():
    for var in ("DEVIN_API_KEY", "WINDSURF_API_KEY"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        body = open(os.path.expanduser("~/.local/share/devin/credentials.toml")).read()
        m = re.search(r'windsurf_api_key\s*=\s*"([^"]+)"', body)
        if m:
            return m.group(1)
    except OSError:
        pass
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--log")
    ap.add_argument("--out")
    ap.add_argument("--prefix", default="")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("prompt", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    prompt = " ".join(a.prompt).lstrip("-").strip()
    if a.prefix:
        prompt = "Session context (already loaded):\n" + a.prefix + "\n\nTask: " + prompt

    bin_ = os.environ.get("DEVIN_BIN", DEFAULT_BIN)
    proc = subprocess.Popen([bin_, "acp"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            cwd=a.cwd, env=dict(os.environ), text=True, bufsize=1)

    _id = [0]

    def send(method, params):
        _id[0] += 1
        proc.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "id": _id[0], "method": method, "params": params}) + "\n")
        proc.stdin.flush()
        return _id[0]

    def answer(m):
        """Reply to a server->client request (fs access, permissions)."""
        meth, params = m.get("method", ""), m.get("params", {})
        if meth.endswith("requestPermission") or "request_permission" in meth:
            opts = params.get("options", [])
            pick = next((o for o in opts if "allow" in o.get("kind", "")),
                        opts[0] if opts else {})
            res = {"outcome": {"outcome": "selected", "optionId": pick.get("optionId", "")}}
        elif "readTextFile" in meth:
            try:
                res = {"content": open(params["path"]).read()}
            except Exception:
                res = {"content": ""}
        elif "writeTextFile" in meth:
            try:
                open(params["path"], "w").write(params.get("content", ""))
            except Exception:
                pass
            res = {}
        else:
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": m["id"],
                "error": {"code": -32601, "message": "unimplemented"}}) + "\n")
            proc.stdin.flush()
            return
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": res}) + "\n")
        proc.stdin.flush()

    def content_bytes(u):
        """Bytes of output a tool call surfaced to the agent. Content shows
        up on whichever update carries it, in-progress or completed, so
        callers keep the max per call. A resource_link's payload is the
        link text the agent reads, not the file it points at."""
        n = 0
        for c in u.get("content", []) or []:
            inner = c.get("content", {})
            t = inner.get("type")
            if t == "text":
                n += len(inner.get("text", ""))
            elif t == "resource":
                r = inner.get("resource", {})
                n += len(r.get("text", "") or r.get("blob", ""))
            elif t == "resource_link":
                n += len(inner.get("uri", "")) + len(inner.get("name", ""))
            elif t == "diff":
                n += len(inner.get("newText", "")) + len(inner.get("oldText", "") or "")
            else:
                n += len(json.dumps(inner))
        return n

    init_id = send("initialize", {"protocolVersion": 1, "clientCapabilities":
        {"fs": {"readTextFile": True, "writeTextFile": True}, "terminal": False}})
    auth_id = [None]
    calls = {}   # toolCallId -> {tool, input}
    done = {}    # toolCallId -> out_bytes / ok
    out_text = []
    deadline = time.time() + a.timeout
    init_deadline = time.time() + 60

    while time.time() < deadline:
        if a.check and auth_id[0] is None and time.time() > init_deadline:
            break
        line = proc.stdout.readline()
        if not line:
            break
        try:
            m = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "id" in m and "method" in m:
            answer(m)
            continue
        if "id" in m:
            rid = m["id"]
            if rid == init_id and "result" in m:
                auth_id[0] = send("authenticate",
                    {"methodId": "devin-browser", "_meta": {"api_key": api_key()}})
            elif rid == auth_id[0]:
                if "error" in m:
                    print("auth failed:", m["error"].get("message", "")[:200],
                          file=sys.stderr)
                    break
                if a.check:
                    print("ok")
                    break
                send("session/new", {"cwd": a.cwd, "mcpServers": []})
            elif "result" in m and "sessionId" in m["result"]:
                send("session/prompt", {"sessionId": m["result"]["sessionId"],
                     "prompt": [{"type": "text", "text": prompt}]})
            elif "result" in m and "stopReason" in m["result"]:
                break
            elif "error" in m:
                print("rpc error:", json.dumps(m["error"])[:200], file=sys.stderr)
        elif m.get("method") == "session/update":
            u = m["params"].get("update", {})
            kind = u.get("sessionUpdate")
            if kind == "tool_call":
                calls[u["toolCallId"]] = {
                    "tool": u.get("_meta", {}).get("cognition.ai/inferenceToolName")
                            or u["toolCallId"].split(":")[0],
                    "input": u.get("rawInput") or
                             {"title": u.get("title"), "kind": u.get("kind"),
                              "locations": u.get("locations")},
                }
            elif kind == "tool_call_update":
                cid = u["toolCallId"]
                st = u.get("status")
                prev = done.get(cid, (0, False))
                done[cid] = (max(prev[0], content_bytes(u)),
                             st == "completed" or prev[1])
            elif kind == "agent_message_chunk":
                out_text.append(u.get("content", {}).get("text", ""))

    proc.terminate()

    if a.log:
        os.makedirs(os.path.dirname(a.log) or ".", exist_ok=True)
        with open(a.log, "w") as f:
            for cid, rec in calls.items():
                ob, ok = done.get(cid, (0, False))
                f.write(json.dumps({"tool": rec["tool"], "input": rec["input"],
                                    "out_bytes": ob, "ok": ok}) + "\n")
    if a.out:
        with open(a.out, "w") as f:
            f.write("".join(out_text))


if __name__ == "__main__":
    main()

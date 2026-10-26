#!/usr/bin/env bash
# hook_posttool.sh LOG — PostToolUse logger for the agent eval.
# Reads the hook payload on stdin (devin and claude share the shape:
# {tool_name, tool_input, tool_response:{output, success}}) and appends
# one compact JSONL line to LOG. Never blocks: always exits 0.
set -u
log="${1:?usage: hook_posttool.sh LOG}"
mkdir -p "$(dirname "$log")"
# -c, not `python3 -` — with - the program comes from stdin and the hook
# payload piped to us would be discarded
python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
tool = d.get("tool_name") or d.get("toolName") or ""
ti = d.get("tool_input") or d.get("toolInput") or {}
tr = d.get("tool_response") or d.get("toolResponse") or {}
out = tr.get("output")
if isinstance(out, (list, dict)):
    out = json.dumps(out)
rec = {
    "tool": tool,
    "input": ti,
    "out_bytes": len(str(out or "")),
    "ok": bool(tr.get("success", tr.get("ok", True))),
}
with open(sys.argv[1], "a") as f:
    f.write(json.dumps(rec) + "\n")
' "$log"
exit 0

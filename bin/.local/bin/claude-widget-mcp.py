#!/usr/bin/env python3
"""MCP server with one tool, step: how Claude reports its progress to the widget.

The tool itself does nothing. The PostToolUse hook in claude-widget.sh reads the call,
because hooks are told which session it came from and this server isn't.
"""

import json
import sys

STEP = {
    "name": "step",
    "description": "Report progress on the current request to the desktop progress bar. "
    "Call it with total (your plan in steps) and done: 0 before starting, then again as each "
    "step finishes. Silent and cheap: it only draws a bar.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "done": {"type": "integer", "minimum": 0, "description": "Steps finished so far."},
            "total": {"type": "integer", "minimum": 1, "description": "Steps planned; may change if the plan does."},
            "note": {"type": "string", "description": "The step in progress, a few words."},
        },
        "required": ["done"],
    },
}


def answer(method, params):
    if method == "initialize":
        return {
            "protocolVersion": params.get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "claude-widget", "version": "1.0.0"},
        }
    if method == "tools/list":
        return {"tools": [STEP]}
    if method == "tools/call":
        return {"content": [{"type": "text", "text": "ok"}]}
    return {}


for line in sys.stdin:
    message = json.loads(line)
    # Notifications have no id and get no reply
    if "id" in message:
        result = answer(message.get("method"), message.get("params") or {})
        print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}), flush=True)

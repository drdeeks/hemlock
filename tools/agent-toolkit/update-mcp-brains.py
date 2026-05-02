#!/usr/bin/env python3
"""Update openclaw.json with per-agent MCP brain entries."""
import json

with open("/home/drdeek/.openclaw/openclaw.json") as f:
    cfg = json.load(f)

servers = cfg.setdefault("mcp", {}).setdefault("servers", {})
servers.pop("hermes-brain", None)

venv = "/home/drdeek/.hermes/hermes-agent/venv/bin/python3"
script = "/home/drdeek/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py"

for a in cfg["agents"]["list"]:
    aid = a["id"]
    servers[f"brain-{aid}"] = {
        "command": venv,
        "args": [script],
        "env": {
            "AGENT_ID": aid,
            "HERMES_HOME": f"/home/drdeek/.openclaw/agents/{aid}",
        }
    }
    print(f"  brain-{aid} -> {aid}")

with open("/home/drdeek/.openclaw/openclaw.json", "w") as f:
    json.dump(cfg, f, indent=2)

print(f"\n{len(cfg['agents']['list'])} per-agent MCP brains configured")

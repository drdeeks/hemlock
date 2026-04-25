---
name: openclaw-hermes-mcp-integration
category: devops
description: Deploy OpenClaw multi-agent fleet with hermes-agent brain as MCP server, using bind-mounted agent homes for single-source-of-truth architecture.
---

# OpenClaw + Hermes Brain MCP Integration

Deploy autonomous AI agents where each runs in its own Docker container with:
- **OpenClaw Gateway** (Node.js) — platform adapter (Telegram, Discord, etc.)
- **Hermes Brain MCP** (Python) — agent loop, memory, skills via MCP protocol

## Key Architecture Decision

**Agent workspace `~/.openclaw/agents/<name>/` is the single source of truth.**

Bind-mount it directly into containers — NEVER use Docker volumes for agent data:
```yaml
volumes:
  - ~/.openclaw/agents/titan:/data/agents/titan        # read-write
  - ~/.openclaw/openclaw.json:/data/openclaw.json:ro   # shared config
  - ~/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py:/app/agent_brain_mcp.py:ro
```

Benefits: edit on host → instant in container, backup by copying dir, no sync needed.

## Files

### agent_brain_mcp.py (MCP server)
- Location: `~/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py`
- Tools: `agent_chat`, `agent_memory_get/set`, `agent_skills_list`, `agent_insights`, `agent_sessions`, `agent_identity`
- Critical: `agent_chat` MUST run in ThreadPoolExecutor with hard timeout (300s) — never hang the MCP server
- All tools return JSON strings, all have try/except, all log with timestamps

### entrypoint.sh (container bootstrap)
- Pre-flight checks: AGENT_ID set, python3/node/openclaw exist, bind mounts exist, agent_brain_mcp.py valid Python
- Generates per-agent openclaw.json with `mcp.servers.hermes-brain` injected
- Never overwrites host files (only creates stubs if missing)
- Uses `set -euo pipefail` + SIGTERM/SIGINT traps for clean shutdown
- Validates generated config JSON before starting gateway
- Runs gateway in background with `wait` to forward signals

### docker-compose.yml
- Healthcheck: `python3 -c "import ast; ast.parse(open('/app/agent_brain_mcp.py').read())" && openclaw --version`
- Healthcheck interval: 60s, timeout: 10s, retries: 3, start_period: 30s
- No top-level `volumes:` section (all bind mounts)

## Entrypoint Config Injection

The entrypoint generates a per-agent config that includes the MCP brain:
```json
{
  "mcp": {
    "servers": {
      "hermes-brain": {
        "command": "python3",
        "args": ["/app/agent_brain_mcp.py"],
        "env": { "AGENT_ID": "<agent>", "HERMES_HOME": "/data/agents/<agent>" }
      }
    }
  }
}
```

## Critical: openclaw.json Parsing

The Python heredoc in entrypoint.sh uses `python3 << 'PYEOF' 2>&1`. Test extractors must handle the `2>&1` on the same line as the heredoc start — skip to the next line before extracting.

## Security Hardening in agent_brain_mcp.py

- `_validate_filename()` — blocks path traversal (`../`), absolute paths, unsafe chars
- `_safe_read_text()` — 5MB max per file read, `errors="replace"` for encoding safety
- `_safe_write_text()` — atomic writes via temp file + rename, permission error handling
- `_clamp()` — all integer inputs clamped to sane ranges
- SIGTERM/SIGINT handlers — graceful shutdown instead of abrupt exit
- Every tool returns JSON (never raises to caller), all exceptions caught and logged
- Startup diagnostics log agent_id, model, API key presence, issues list

## Common Pitfalls

1. **Docker volumes vs bind mounts** — user will reject volumes. Always bind-mount agent homes.
2. **openclaw.json syntax** — the gateway/tailscale section has nested objects. Validate with `python3 -m json.tool` before deploying. Common bug: extra `}` closing gateway.
3. **agent_brain_mcp.py location** — lives in toolkit dir `~/.openclaw/agents/.scripts/agent-toolkit/`, bind-mounted at runtime. Do NOT COPY into Docker image. Keep docker/ copy in sync manually.
4. **agent_chat timeout** — without ThreadPoolExecutor wrapper, a stuck LLM call hangs the entire MCP server forever.
5. **Entrypoint heredoc** — use `python3 << 'PYEOF'` (quoted), then check `$?` after. Don't add `|| die` on the same line — it gets captured by test extractors.
6. **_HERMES_HOME isolation in tests** — module captures `_HERMES_HOME` at import time. Tests must either: (a) patch the module-level constant, or (b) use `_get_hermes_home()` which reads env fresh each call.
7. **openclaw.json openclaw.json nesting bug** — lines 363-365 often have broken brace nesting for gateway/tailscale. Fix: `"tailscale": {...}\n  },` not `}\n}\n  },`.

## Local Mode (No Docker)

OpenClaw gateway can spawn hermes MCP brain locally. Just add `mcp.servers.hermes-brain` to the HOST `~/.openclaw/openclaw.json`:

```json
{
  "mcp": {
    "servers": {
      "hermes-brain": {
        "command": "python3",
        "args": ["/home/drdeek/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py"],
        "env": {
          "AGENT_ID": "hermes",
          "HERMES_HOME": "/home/drdeek/.openclaw/agents/hermes"
        }
      }
    }
  }
}
```

Then: `openclaw gateway run --allow-unconfigured`

The gateway auto-spawns the MCP process. No Docker needed.

## Systemd Service (Auto-start, Self-healing)

Install: `sudo ~/.openclaw/agents/.scripts/install-service.sh`

Unit file features:
- `Restart=always` + `RestartSec=5` — restarts on crash
- `WantedBy=multi-user.target` — starts on boot
- `StartLimitBurst=5` in 300s — prevents restart loops
- `KillMode=mixed` + `TimeoutStopSec=30` — graceful shutdown
- `ProtectSystem=strict` + `ReadWritePaths` — security hardened

## Config Change Propagation

Almost everything flows through one rule: **change openclaw.json or .env → restart gateway**.

```bash
openclaw gateway restart    # local mode (preferred — openclaw has built-in restart)
systemctl restart hermes-agent  # systemd mode
docker compose restart hermes   # docker mode
```

The gateway re-reads openclaw.json, re-spawns MCP brain with new config, reconnects Telegram.

Live (no restart needed): SOUL.md, MEMORY.md, memory/, skills/ — loaded fresh each message.

## Global Skills Symlinking

Shared skills live at `~/.openclaw/agents/.skills/`. Symlink into each agent:

```bash
for agent in allman aton avery guard main mort titan tom hermes; do
    for skill in ~/.openclaw/agents/.skills/*/; do
        name=$(basename "$skill")
        dst=~/.openclaw/agents/$agent/skills/$name
        [ -d "$dst" ] && [ ! -L "$dst" ] && continue  # agent-owned takes priority
        [ -L "$dst" ] && continue                       # already linked
        ln -s "$skill" "$dst"
    done
done
```

Agent-specific skills created in `<agent>/skills/` stay as real directories. Owned always beats symlinked.

## openclaw.json Merge from Example

When merging with an example/reference config:
- Preserve existing tokens, bindings, agent entries
- Merge: model providers (add missing), per-agent tools/groupChat/model fallbacks
- Add missing sections: tools.web, tools.agentToAgent, hooks.internal, gateway.nodes, plugins
- Port must be integer: `18789` not `"18789"`
- Validate after merge: `python3 -m json.tool openclaw.json`

## Agent-to-Agent and Group Chat

```json
{
  "agents": {
    "list": [{
      "id": "titan",
      "groupChat": {"mentionPatterns": ["@titan"]},
      "tools": {"allow": ["*"], "deny": [], "elevated": {}}
    }]
  },
  "tools": {
    "agentToAgent": {"allow": ["allman", "aton", "guard"]}  // exclude specific agents
  }
}
```

## Agent Home Migration (~/.hermes → ~/.openclaw/agents/<name>)

When migrating an agent's home to the openclaw structure:
1. `mkdir -p ~/.openclaw/agents/<name>/{memory,sessions,skills,tools,logs,.secrets,cron,memories}`
2. Copy identity files, config.yaml, .env, state.db, sessions/
3. Create agent.json with builder code
4. Add entry to openclaw.json agents.list, channels.telegram.accounts, bindings
5. Set `HERMES_HOME=~/.openclaw/agents/<name>` in bashrc
6. `openclaw gateway restart`

## Testing

- Test suite at `~/.openclaw/docker/tests/` — 8 files, ~2800 lines
- 150 passing tests, 25 skipped (need `mcp` package on host — available in containers)
- Run: `cd ~/.openclaw/docker && python3 -m pytest tests/ -m "not integration"`
- Smoke tests (integration marker): `./tests/run_tests.sh --smoke` (needs running containers)
- Test categories: agent_brain_mcp (35), e2e_pipeline (20), failure_modes (17), docker_infra (39), entrypoint (14), bootstrap (21)
- Mocking pattern: use `FakeFastMCP` + patch `_HERMES_HOME` at module level for test isolation

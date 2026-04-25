# Hermes Skill Scanner v1.7.0

Core skills shared. Agent skills isolated. One inventory.

---

## What This Does

Manages core vs per-agent skills.

    ~/.hermes/skills/                    CORE (shared)
    ~/.openclaw/agents/titan/skills/     AGENT view
    ├── github -> ../../skills/github    symlink to core
    └── farcaster-agent/                 agent-owned

---

## Commands

| Command | What It Does |
|---------|-------------|
| scan [agent] | Inventory — core-linked, agent-owned, broken |
| sync [agent] | Symlink core skills into agent dirs |
| diff <a> <b> | Compare skills between two agents |
| unlink <agent> | Remove core symlinks |
| list | List core skills |

---

## Flags

| Flag | Short | Effect |
|------|-------|--------|
| --openclaw | -o | Scan OpenClaw agent dirs |
| --dry-run | -n | Preview without modifying |

---

## Sync Behavior

| Agent has... | Sync does... |
|-------------|-------------|
| Nothing | Creates symlink to core |
| Correct symlink | Skips |
| Stale symlink | Fixes |
| Real directory | Skips (agent-owned) |

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| SHARED_SKILLS_DIR | ~/.hermes/skills | Core skills directory |
| OPENCLAW_ROOT | ~/.openclaw | OpenClaw directory |

---

## License

Use it however you want.

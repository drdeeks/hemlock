# OpenClaw Agent Toolkit

**Enterprise Multi-Agent Management System**

Bootstrap, configure, scan, repair, and containerize autonomous AI agents.

Powered by [OpenClaw](https://openclaw.ai) (gateway/platform layer) +
[Hermes Agent](https://github.com/NousResearch/hermes-agent) (agent brain/runtime).

**Note:** All paths in this documentation use placeholders:
- `<RUNTIME_ROOT>` = Project root directory (set via environment or current working directory)
- `<CONTAINER_ROOT>` = `/` or container root
- `{agent-name}` = Actual agent name

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Directory Layout](#directory-layout)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Agent Management](#agent-management)
- [Docker Operations](#docker-operations)
- [Backup and Disaster Recovery](#backup-and-disaster-recovery)
- [Configuration Reference](#configuration-reference)
- [MCP Brain Server](#mcp-brain-server)
- [Security](#security)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Appendix](#appendix)

---

## Overview

The Agent Toolkit manages the full lifecycle of AI agents:

```
  CREATE          CONFIGURE         DEPLOY           OPERATE           RECOVER
    │                │                │                 │                 │
    ▼                ▼                ▼                 ▼                 ▼
┌────────┐    ┌────────────┐    ┌──────────┐    ┌────────────┐    ┌──────────┐
│  init  │───►│ configure  │───►│  docker  │───►│ scan/restart│───►│  repair  │
│        │    │   config   │    │  build   │    │  logs       │    │  backup  │
└────────┘    └────────────┘    └──────────┘    └────────────┘    └──────────┘
   Step 1         Step 2           Step 3          Daily ops        As needed
```

**Design principles:**
- Single source of truth: `<RUNTIME_ROOT>/agents/<name>/` is the agent workspace
- Bind-mounted into containers: no Docker volumes, no duplication
- Edit on host, see instantly in container
- Back up by copying a directory
- Each agent is fully self-contained and portable
- All paths are relative to runtime root, no hardcoded locations

---

## Architecture

### System Topology

```
                        ┌─────────────────────────────────┐
                        │         Telegram Cloud           │
                        │  ┌──────┐ ┌──────┐ ┌──────┐    │
                        │  │Bot:titan│Bot:allman│Bot:guard│ │
                        │  └──┬───┘ └──┬───┘ └──┬───┘    │
                        └─────┼────────┼────────┼─────────┘
                              │        │        │
                    ┌─────────┼────────┼────────┼──────────┐
                    │         ▼        ▼        ▼          │
                    │  ┌─────────────────────────────────┐ │
                    │  │      Docker Bridge Network       │ │
                    │  │          (openclaw)              │ │
                    │  └──┬──────────┬──────────┬────────┘ │
                    │     │          │          │           │
     Host OS        │  ┌──▼───┐  ┌──▼───┐  ┌──▼───┐      │
                    │  │oc-   │  │oc-   │  │oc-   │      │
  <RUNTIME_ROOT>/ ─┼──│agent1│  │agent2│  │agent3│      │
  agents/           │  │      │  │      │  │      │      │
                    │  │GW+MCP│  │GW+MCP│  │GW+MCP│      │
                    │  └──┬───┘  └──┬───┘  └──┬───┘      │
                    │     │         │         │           │
                    └─────┼─────────┼─────────┼───────────┘
                          │         │         │
                          ▼         ▼         ▼
                    Host agent directories (bind-mounted)
```

### Container Internals

Each container runs two components connected via MCP protocol:

```
┌────────────────────────────────────────────────────────────────────┐
│  Container: oc-{agent-name}                                       │
│                                                                    │
│  ┌────────────────────────────┐    ┌────────────────────────────┐ │
│  │   OpenClaw Gateway         │    │  Hermes Brain MCP Server   │ │
│  │   (Node.js process)        │    │  (Python process)          │ │
│  │                            │    │                            │ │
│  │  • Telegram adapter        │    │  • agent_chat()            │ │
│  │  • Message routing         │MCP │  • agent_memory_get()      │ │
│  │  • Session management      │◄──►│  • agent_memory_set()      │ │
│  │  • Config loading          │    │  • agent_skills_list()     │ │
│  │  • Tool orchestration      │    │  • agent_insights()        │ │
│  │                            │    │  • agent_sessions()        │ │
│  └────────────┬───────────────┘    │  • agent_identity()        │ │
│               │                    └────────────┬───────────────┘ │
│               │                                 │                 │
│  ┌────────────▼─────────────────────────────────▼───────────────┐ │
│  │              /data/agents/titan/  (bind-mounted from host)   │ │
│  │                                                              │ │
│  │  SOUL.md  USER.md  MEMORY.md  sessions/  memory/  skills/   │ │
│  └──────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

### Message Flow

```
User sends message on Telegram
        │
        ▼
┌─────────────────┐
│ Telegram API    │
└────────┬────────┘
         │ webhook / polling
         ▼
┌──────────────────────────────────────────────────────────────┐
│  oc-titan container                                          │
│                                                              │
│  OpenClaw Gateway                                            │
│    │                                                         │
│    ├─ Loads config: <CONTAINER_ROOT>/.openclaw/openclaw.json            │
│    ├─ Resolves agent: titan                                  │
│    ├─ Creates session                                        │
│    │                                                         │
│    ▼                                                         │
│  MCP call: agent_chat(message="...")                         │
│    │                                                         │
│    ▼                                                         │
│  Hermes Brain MCP Server                                     │
│    │                                                         │
│    ├─ Builds system prompt (SOUL.md + MEMORY.md + skills)    │
│    ├─ Calls LLM API (Nous/OpenRouter/Anthropic/OpenAI)       │
│    ├─ Executes tool calls (terminal, files, web, browser)    │
│    ├─ Loops until final response                             │
│    ├─ Updates MEMORY.md if insights detected                 │
│    │                                                         │
│    ▼                                                         │
│  Response returned to OpenClaw Gateway                       │
│    │                                                         │
│    ▼                                                         │
│  Gateway sends reply to Telegram                             │
└──────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ Telegram API    │
└────────┬────────┘
         │
         ▼
    User receives reply
```

### Data Flow: Host ↔ Container

```
  HOST FILESYSTEM                      CONTAINER FILESYSTEM
  ═══════════════                      ════════════════════

  <RUNTIME_ROOT>/                      /data/
  ├── config/ ────────────────────────► ├── config/ (ro)
  │   (shared config)                  │   (per-agent filtered copy)
  │                                    │
  └── agents/                          └── agents/
      │                                    │
      ├── {agent-name}/ ──────────────► ├── {agent-name}/
      │   ├── SOUL.md                   │   ├── SOUL.md        ◄── same file
      │   ├── USER.md                   │   ├── USER.md        ◄── same file
      │   ├── MEMORY.md                 │   ├── MEMORY.md      ◄── read+write
      │   ├── config.yaml               │   ├── config.yaml    ◄── same file
      │   ├── .env                       │   ├── .env           ◄── same file
      │   ├── agent.json                │   ├── agent.json     ◄── same file
      │   ├── memory/                    │   ├── memory/        ◄── read+write
      │   │   └── notes.md              │   │   └── notes.md
      │   ├── sessions/                  │   ├── sessions/      ◄── read+write
      │   │   └── *.jsonl               │   │   └── *.jsonl
      │   ├── skills/                    │   ├── skills/        ◄── read+write
      │   ├── .secrets/                  │   ├── .secrets/      ◄── sensitive
      │   └── ...                        │   └── ...
      │                                  │
      └── scripts/                       /app/
          └── toolkit/                    ├── agent_brain_mcp.py (ro)
              └── agent_brain_mcp.py ──► └── hermes-agent/
                                                 └── (python source)

  Legend:
    ─────►  bind mount (read-write unless noted)
    ◄──     same physical file on disk
    (ro)    read-only mount
```

---

## Directory Layout

### Toolkit Files

```
<RUNTIME_ROOT>/tools/agent-toolkit/
│
├── agent-bootstrap.sh          Main CLI
├── agent_brain_mcp.py          MCP server — hermes agent brain
├── skill-scanner.sh            Skill scanner bash wrapper
├── skill_scanner.py            Skill scanner (SQLite-backed)
├── SKILL-SCANNER.md            Scanner documentation
└── README.md                   This file
```

### Generated Docker Files

```
<RUNTIME_ROOT>/docker/
├── Dockerfile                  Container image definition
├── entrypoint.sh               Per-agent bootstrap + MCP injection
├── docker-compose.yml          Multi-agent orchestration
└── hermes-agent/               Build context (hermes source copy)
```

### Agent Workspace (per agent)

```
<RUNTIME_ROOT>/agents/<name>/
│
├── IDENTITY FILES
│   ├── SOUL.md                 Agent personality, values, behavior
│   ├── USER.md                 User info, preferences, context
│   ├── AGENTS.md               Multi-agent protocols and coordination
│   ├── HEARTBEAT.md            Heartbeat context and status
│   ├── IDENTITY.md             Extended identity details
│   └── TOOLS.md                Tool preferences and configuration
│
├── MEMORY
│   ├── MEMORY.md               Main persistent memory file
│   └── memory/                 Structured memory directory
│       ├── notes/              Categorized notes
│       ├── skills-learned.md   Auto-learned capabilities
│       └── *.md                Arbitrary memory files
│
├── SESSIONS
│   └── sessions/               Conversation transcripts (JSONL)
│
├── SKILLS
│   └── skills/                 Agent skills (owned + symlinked core)
│       ├── github → ../../skills/github    (symlink to core)
│       └── custom-skill/                   (agent-owned)
│           └── SKILL.md
│
├── CONFIGURATION
│   ├── config.yaml             Model, tools, memory, skills config
│   ├── .env                    API keys, bot tokens (SENSITIVE)
│   └── agent.json              Builder code (bc_26ulyc23)
│
├── PROJECTS
│   └── projects/               Project workspaces
│
├── RUNTIME
│   ├── tools/                  Tool state and cache
│   ├── logs/                   Agent runtime logs
│   └── archives/               Archived sessions/data
│
└── SECURITY
    ├── .secrets/               Secret storage (mode: 700)
    └── .backups/               Auto-backups before modifications
```

---

## Prerequisites

| Requirement | Version | Purpose |
|------------|---------|---------|
| Linux host | Ubuntu 22.04+ | Container runtime |
| Docker | 20.10+ | Container engine |
| Docker Compose | 2.0+ | Multi-container orchestration |
| Node.js | 22+ | OpenClaw runtime |
| Python | 3.11+ | Hermes agent brain |
| Git | 2.0+ | Source management |

### Verify Prerequisites

```bash
# Docker
docker --version
# Expected: Docker version 20.10+

docker compose version
# Expected: Docker Compose version v2.0+

# Node.js
node --version
# Expected: v22+

# Python
python3 --version
# Expected: Python 3.11+

# Hermes agent source
ls ~/.hermes/hermes-agent/run_agent.py
# Expected: file exists
```

### Required API Keys

| Provider | Key | Where to Get |
|----------|-----|-------------|
| Telegram | Bot Token | @BotFather on Telegram |
| Nous | API Key | inference-api.nousresearch.com |
| OpenRouter | API Key | openrouter.ai/keys |
| OpenAI | API Key | platform.openai.com/api-keys |
| Anthropic | API Key | console.anthropic.com |

---

## Installation

### Step 1: Install OpenClaw

```bash
npm install -g openclaw

# Verify
openclaw --version
```

### Step 2: Install Hermes Agent

```bash
# Clone source
git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent

# Create virtual environment
cd ~/.hermes/hermes-agent
python3 -m venv venv
source venv/bin/activate

# Install with MCP support
pip install -e ".[mcp]"

# Verify
python3 -c "from run_agent import AIAgent; print('OK')"
```

### Step 3: Run Setup Wizard

```bash
openclaw doctor
```

This creates `~/.openclaw/openclaw.json` with provider configuration.

---

## Quick Start

```bash
# 1. Create an agent
cd <RUNTIME_ROOT>/agents/.scripts/agent-toolkit
./agent-bootstrap.sh --openclaw init my-agent

# 2. Configure it
./agent-bootstrap.sh configure my-agent

# 3. Verify health
./agent-bootstrap.sh scan

# 4. Generate config + Docker
./agent-bootstrap.sh config
./agent-bootstrap.sh docker

# 5. Launch
cd ~/.openclaw/docker
docker compose up -d

# 6. Check
docker compose logs -f my-agent
```

---

## Detailed Setup

### Creating Agents

```bash
cd <RUNTIME_ROOT>/agents/.scripts/agent-toolkit

# Interactive — prompts for provider, platform, API keys
./agent-bootstrap.sh --openclaw init titan

# Creates:
#   <RUNTIME_ROOT>/agents/titan/
#   ├── SOUL.md, USER.md, AGENTS.md, HEARTBEAT.md
#   ├── config.yaml
#   ├── .env
#   ├── agent.json
#   ├── memory/, sessions/, skills/, tools/, logs/, .secrets/, .backups/
```

Create multiple agents:

```bash
./agent-bootstrap.sh --openclaw init titan
./agent-bootstrap.sh --openclaw init allman
./agent-bootstrap.sh --openclaw init guard
./agent-bootstrap.sh --openclaw init main
```

### Configuring Agents

**Interactive configuration:**

```bash
./agent-bootstrap.sh configure titan
```

```
── Configure: titan ──
  Current bot token: 876225...ARkY
  Keep this token? [Y/n]: y

  Current provider: nous
  Keep this provider? [Y/n]: y

  ✓ Configuration saved
```

**Manual configuration:**

```bash
# Set bot token
echo 'TELEGRAM_BOT_TOKEN=8762250094:YOUR_TOKEN_HERE' >> <RUNTIME_ROOT>/agents/titan/.env

# Set API key
echo 'NOUS_API_KEY=your-nous-api-key' >> <RUNTIME_ROOT>/agents/titan/.env

# Edit model config
vim <RUNTIME_ROOT>/agents/titan/config.yaml
```

**config.yaml reference:**

```yaml
model:
  primary: "nous/xiaomi/mimo-v2-pro"     # Primary model
  # fallback: "openrouter/anthropic/claude-sonnet-4"  # Fallback model

tools:
  profile: coding                         # Tool profile (coding, minimal, full)

memory:
  enabled: true
  max_chars: 100000                       # Max memory context chars

skills:
  enabled: true
```

### Writing Identity Files

Identity files shape how the agent behaves:

**SOUL.md** — Agent personality:
```markdown
# Titan's Soul

You are Titan, a focused technical assistant. You prioritize:
- Accuracy over speed
- Clear explanations over jargon
- Practical solutions over theory

You communicate in a direct, professional tone.
```

**USER.md** — User context:
```markdown
# User Profile

- Name: DrDeek
- Role: System administrator
- Timezone: America/Chicago
- Prefers: Detailed technical answers
```

### Scanning Agent Health

```bash
./agent-bootstrap.sh scan
```

```
── Scanning: titan ──
  ✓ HERMES_HOME exists
  ✓ config.yaml: 4750 bytes
  ✓ .env: 69 lines
  ✓ Bot token configured
  ✓ API key configured
  ✓ .secrets/ permissions: 700
  ✓ Skills: 12 linked, 3 owned

── Scanning: allman ──
  ✓ HERMES_HOME exists
  ⚠ config.yaml: 0 bytes (empty)
  ✓ .env: 45 lines
  ✗ Bot token not configured
  ✓ .secrets/ permissions: 700

Summary: 1 healthy, 1 warnings, 1 errors
```

### Generating Config

```bash
./agent-bootstrap.sh config
```

```
── Config Generator ──
  Discovered agents: titan, allman, guard, main, mort, aton, avery, tom
  Written to: ~/.openclaw/agents-config-generated.json

  Agents: 8
  Telegram accounts: 8
  Bindings: 8
```

### Generating Docker

```bash
./agent-bootstrap.sh docker

# Or preview first
./agent-bootstrap.sh --dry-run docker
```

```
── Docker Generator ──

  This will generate files in: <RUNTIME_ROOT>/docker/

  Dockerfile           — base image with OpenClaw + Hermes agent brain
  entrypoint.sh        — per-agent MCP config injection + gateway start
  docker-compose.yml   — 8 services, bind-mounted from host

  Architecture:
    • Agent homes bind-mounted: <RUNTIME_ROOT>/agents/<name>/ → /data/agents/<name>/
    • agent_brain_mcp.py bind-mounted from toolkit (single source)
    • openclaw.json bind-mounted from host
    • No Docker volumes — your host files ARE the agent workspace

  Generate? [Y/n]: y
  ✓ hermes-agent source copied
  ✓ Dockerfile
  ✓ agent_brain_mcp.py at <RUNTIME_ROOT>/agents/.scripts/agent-toolkit/agent_brain_mcp.py
  ✓ entrypoint.sh (per-agent config + MCP brain injection)
  ✓ docker-compose.yml (8 services, bind-mounted from host)

Docker setup ready: <RUNTIME_ROOT>/docker/

  cd ~/.openclaw/docker
  docker-compose up -d --build
  docker-compose logs -f titan

  Agent workspace: <RUNTIME_ROOT>/agents/<name>/ (bind-mounted, single source)
  Edit files on host → changes appear instantly in container.
  Backup: cp -r <RUNTIME_ROOT>/agents/<name>/ ./backup/
```

---

## Agent Management

### Lifecycle Commands

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   CREATE     │    │  OPERATE     │    │  DESTROY     │
│              │    │              │    │              │
│ init         │    │ scan         │    │ delete       │
│ configure    │───►│ repair       │───►│              │
│ config       │    │ restart      │    │              │
│ docker       │    │ logs         │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
```

### Container Operations

```bash
# Start all agents
docker compose up -d

# Start specific agent
docker compose up -d titan

# Stop all
docker compose down

# Stop one agent
docker compose stop titan

# Restart one agent (picks up config changes)
docker compose restart titan

# View logs
docker compose logs -f titan        # Follow one agent
docker compose logs --tail=100 titan  # Last 100 lines
docker compose logs -f              # All agents

# Shell into container
docker exec -it oc-titan bash

# Check container status
docker compose ps
```

### Config Changes (Live Reload)

Because agent homes are bind-mounted, changes are instant:

```bash
# Edit personality on host
vim <RUNTIME_ROOT>/agents/titan/SOUL.md

# Changes appear immediately in the running container
# No rebuild, no restart needed for file content

# Restart needed only for:
# - .env changes (environment variables are read at startup)
# - config.yaml changes (loaded once at startup)
# - openclaw.json changes (loaded once at startup)
docker compose restart titan
```

### Adding Agents to Running Fleet

```bash
# 1. Create on host
cd <RUNTIME_ROOT>/agents/.scripts/agent-toolkit
./agent-bootstrap.sh --openclaw init scout
./agent-bootstrap.sh configure scout

# 2. Regenerate config + compose
./agent-bootstrap.sh config
./agent-bootstrap.sh docker

# 3. Launch new agent (existing agents unaffected)
cd ~/.openclaw/docker
docker compose up -d --build scout
```

### Removing Agents

```bash
# 1. Stop container
cd ~/.openclaw/docker
docker compose rm -sf scout

# 2. Remove from openclaw.json (edit or regenerate)
./agent-bootstrap.sh config

# 3. Remove agent directory (backs up first)
cd <RUNTIME_ROOT>/agents/.scripts/agent-toolkit
./agent-bootstrap.sh delete scout
```

---

## Docker Operations

### Build Process

```
docker compose build
    │
    ├──► Dockerfile
    │      │
    │      ├── FROM python:3.11-slim
    │      ├── RUN apt-get install curl git jq
    │      ├── RUN install Node.js 22
    │      ├── RUN npm install -g openclaw
    │      ├── COPY hermes-agent/ /app/hermes-agent/
    │      ├── RUN pip install -e ".[mcp]"
    │      └── COPY entrypoint.sh /app/
    │
    └──► Image ready for all agents
```

### Runtime Flow

```
docker compose up -d
    │
    ├──► oc-titan starts
    │      │
    │      ├── entrypoint.sh
    │      │    ├── mkdir -p dirs (if missing)
    │      │    ├── write stubs (if missing)
    │      │    ├── python3: generate per-agent openclaw.json
    │      │    │    └── inject mcp.servers.hermes-brain
    │      │    └── exec openclaw gateway run
    │      │
    │      ├── Gateway reads <CONTAINER_ROOT>/.openclaw/openclaw.json
    │      ├── Gateway connects MCP server: python3 /app/agent_brain_mcp.py
    │      └── Gateway polls Telegram for messages
    │
    ├──► oc-allman starts (same flow)
    ├──► oc-guard starts
    └──► ... (one per configured agent)
```

### Volume Mounts Per Service

```
oc-titan:
  volumes:
    - <RUNTIME_ROOT>/agents/titan           → /data/agents/titan        (rw)
    - ~/.openclaw/openclaw.json          → /data/openclaw.json       (ro)
    - <RUNTIME_ROOT>/agents/.scripts/
      agent-toolkit/agent_brain_mcp.py   → /app/agent_brain_mcp.py   (ro)
```

### Resource Management

```bash
# Check resource usage
docker stats

# Limit resources per agent (add to docker-compose.yml)
services:
  titan:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 512M
```

---

## Backup and Disaster Recovery

### Backup Strategy

```
┌──────────────────────────────────────────────────────────────────┐
│                        BACKUP TARGETS                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  <RUNTIME_ROOT>/agents/<name>/          ← PRIMARY BACKUP   │    │
│  │                                                         │    │
│  │  Contains: SOUL.md, MEMORY.md, sessions/, memory/,     │    │
│  │            skills/, .env, config.yaml, agent.json       │    │
│  │                                                         │    │
│  │  Size: ~10-100MB per agent (depends on sessions)        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  ~/.openclaw/openclaw.json           ← SHARED CONFIG    │    │
│  │                                                         │    │
│  │  Contains: All agent entries, bindings, Telegram        │    │
│  │            accounts, provider config                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### Backup Commands

```bash
# ── Single agent ──────────────────────────────────────────────────
cp -r <RUNTIME_ROOT>/agents/titan/ ./backup/titan-$(date +%Y%m%d)/

# ── All agents ────────────────────────────────────────────────────
mkdir -p ./backup-$(date +%Y%m%d)
for agent in <RUNTIME_ROOT>/agents/*/; do
    name=$(basename "$agent")
    [[ "$name" == .* ]] && continue  # skip dotfiles
    echo "Backing up $name..."
    cp -r "$agent" "./backup-$(date +%Y%m%d)/$name/"
done

# ── Full system ───────────────────────────────────────────────────
tar czf openclaw-backup-$(date +%Y%m%d).tar.gz \
    <RUNTIME_ROOT>/agents/ \
    ~/.openclaw/openclaw.json \
    <RUNTIME_ROOT>/docker/

# ── Automated daily backup (cron) ────────────────────────────────
# Add to crontab -e:
0 3 * * * tar czf /backups/openclaw-$(date +\%Y\%m\%d).tar.gz <RUNTIME_ROOT>/agents/ ~/.openclaw/openclaw.json
```

### Restore Procedure

```bash
# ── Restore single agent ─────────────────────────────────────────
cp -r ./backup/titan-20260418/ <RUNTIME_ROOT>/agents/titan/
cd ~/.openclaw/docker
docker compose restart titan

# ── Restore on new host ──────────────────────────────────────────
# 1. Install prerequisites (Docker, OpenClaw, hermes-agent)
# 2. Copy backup
scp -r ./backup-20260418/* newhost:<RUNTIME_ROOT>/agents/
scp ./openclaw.json newhost:~/.openclaw/

# 3. Copy toolkit
scp -r <RUNTIME_ROOT>/agents/.scripts newhost:<RUNTIME_ROOT>/agents/

# 4. Copy Docker files
scp -r ~/.openclaw/docker newhost:~/.openclaw/

# 5. Launch
ssh newhost
cd ~/.openclaw/docker && docker compose up -d
```

### Disaster Recovery Checklist

```
┌──────────────────────────────────────────────────────────────────┐
│  RECOVERY CHECKLIST                                              │
│                                                                  │
│  □ 1. Verify backup integrity                                   │
│       tar tzf backup.tar.gz | head -20                          │
│                                                                  │
│  □ 2. Install Docker + Docker Compose                           │
│                                                                  │
│  □ 3. Install Node.js 22                                        │
│                                                                  │
│  □ 4. Install OpenClaw                                          │
│       npm install -g openclaw                                   │
│                                                                  │
│  □ 5. Clone hermes-agent                                        │
│       git clone ... ~/.hermes/hermes-agent                      │
│       pip install -e ".[mcp]"                                   │
│                                                                  │
│  □ 6. Restore agent directories                                 │
│       tar xzf backup.tar.gz -C /                                │
│                                                                  │
│  □ 7. Verify config                                             │
│       cat ~/.openclaw/openclaw.json                             │
│       ./agent-bootstrap.sh scan                                 │
│                                                                  │
│  □ 8. Rebuild and launch                                        │
│       cd ~/.openclaw/docker                                     │
│       docker compose build && docker compose up -d              │
│                                                                  │
│  □ 9. Verify agents responding                                  │
│       docker compose logs -f                                    │
│       Send test message on Telegram                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## Configuration Reference

### openclaw.json Structure

```jsonc
{
  "meta": {                          // System metadata
    "lastTouchedVersion": "2026.4.11"
  },
  "auth": {                          // Provider auth profiles
    "profiles": { ... }
  },
  "models": {                        // Model provider config
    "providers": {
      "nous": { "baseUrl": "...", "apiKey": "...", "models": [...] },
      "openrouter": { ... },
      "anthropic": { ... }
    }
  },
  "agents": {                        // Agent definitions
    "defaults": {                    // Default settings for all agents
      "model": { "primary": "..." },
      "timeoutSeconds": 120,
      "maxConcurrent": 4
    },
    "list": [                        // Individual agent entries
      { "id": "titan", "name": "Titan", "workspace": "..." }
    ]
  },
  "channels": {                      // Platform channels
    "telegram": {
      "accounts": {
        "titan": { "botToken": "..." }
      }
    }
  },
  "bindings": [                      // Agent → channel routing
    { "type": "route", "agentId": "titan", "match": { "channel": "telegram" } }
  ],
  "mcp": {                           // MCP server config (injected by entrypoint)
    "servers": {
      "hermes-brain": {
        "command": "python3",
        "args": ["/app/agent_brain_mcp.py"],
        "env": { "AGENT_ID": "titan", "HERMES_HOME": "..." }
      }
    }
  },
  "gateway": {                       // Gateway settings
    "port": "18789",
    "mode": "local"
  }
}
```

### config.yaml Reference

```yaml
# Model configuration
model:
  primary: "nous/xiaomi/mimo-v2-pro"       # Primary model (provider/model-id)
  # fallback: "openrouter/anthropic/claude-sonnet-4"  # Fallback model

# Tool configuration
tools:
  profile: coding                          # coding | minimal | full

# Memory configuration
memory:
  enabled: true                            # Enable memory system
  max_chars: 100000                        # Max memory context chars

# Skills configuration
skills:
  enabled: true                            # Enable skills system
```

### .env Reference

```bash
# ── Platform Tokens ───────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=8762250094:YOUR_TOKEN_HERE
TELEGRAM_ALLOWED_USERS=*                   # Comma-separated user IDs or *
TELEGRAM_HOME_CHANNEL=                     # Optional default channel

# ── Provider API Keys ────────────────────────────────────────────
NOUS_API_KEY=your-nous-key
OPENROUTER_API_KEY=your-openrouter-key
OPENAI_API_KEY=your-openai-key
ANTHROPIC_API_KEY=your-anthropic-key

# ── Terminal ──────────────────────────────────────────────────────
SUDO_PASSWORD=                             # If needed for sudo commands
TERMINAL_TIMEOUT=30

# ── Optional Integrations ────────────────────────────────────────
GITHUB_TOKEN=                              # For GitHub skills
NOTION_API_KEY=                            # For Notion integration
LINEAR_API_KEY=                            # For Linear integration
```

---

## MCP Brain Server

### Overview

`agent_brain_mcp.py` runs as an MCP (Model Context Protocol) server inside each
container. OpenClaw connects to it and exposes its tools to the agent runtime.

```
┌────────────────────────────────────────────────────────────────┐
│  MCP Protocol Flow                                             │
│                                                                │
│  OpenClaw Gateway                                              │
│    │                                                           │
│    ├─ Discovers tools: agent_chat, agent_memory_get, ...      │
│    │                                                           │
│    ├─ When agent needs to "think":                             │
│    │   └─ calls agent_chat(message, max_turns)                │
│    │       └─ hermes brain runs full LLM loop                 │
│    │                                                           │
│    ├─ When agent needs to "remember":                          │
│    │   └─ calls agent_memory_set(content)                     │
│    │       └─ writes to MEMORY.md                             │
│    │                                                           │
│    └─ When agent needs to "recall":                            │
│        └─ calls agent_memory_get(query)                        │
│            └─ searches memory files                            │
└────────────────────────────────────────────────────────────────┘
```

### Available Tools

| Tool | Input | Output | Description |
|------|-------|--------|-------------|
| `agent_chat` | message, max_turns, system_prompt | JSON {response, turns, model} | Full agent loop with tool calling |
| `agent_memory_get` | query?, limit | JSON {count, memories[]} | Search/retrieve memories |
| `agent_memory_set` | content, filename? | JSON {ok, path, bytes} | Store memory |
| `agent_skills_list` | (none) | JSON {count, skills[]} | List available skills |
| `agent_insights` | days | JSON {sessions, tokens, cost} | Usage analytics |
| `agent_sessions` | limit | JSON {count, sessions[]} | List recent sessions |
| `agent_identity` | (none) | JSON {soul, user, config} | Read identity files |

### agent_chat Detail

```
agent_chat("Deploy the latest version to staging")
    │
    ├─ 1. Build system prompt
    │     ├── Load SOUL.md (personality)
    │     ├── Load USER.md (user context)
    │     ├── Load MEMORY.md (persistent memory)
    │     ├── Load skills context
    │     └── Load tool definitions
    │
    ├─ 2. Call LLM API
    │     └── Model: nous/xiaomi/mimo-v2-pro (or configured)
    │
    ├─ 3. If tool call returned:
    │     ├── terminal: run shell commands
    │     ├── read_file: read file contents
    │     ├── write_file: write file contents
    │     ├── web_search: search the web
    │     ├── browser: automate browser
    │     └── ... (40+ tools available)
    │
    ├─ 4. Loop: send tool result back to LLM
    │     └── Repeat until final response (max_turns=15)
    │
    └─ 5. Return final response
```

---

## Security

### File Permissions

```
<RUNTIME_ROOT>/agents/<name>/
├── .secrets/           mode: 700 (owner-only)
├── .env                mode: 600 (owner read-write)
├── agent.json          mode: 644
├── config.yaml         mode: 644
└── *.md                mode: 644
```

### Secrets Management

```bash
# API keys go in .env (not in SOUL.md or MEMORY.md)
echo 'NOUS_API_KEY=secret' >> <RUNTIME_ROOT>/agents/titan/.env

# .secrets/ directory for runtime secrets
# Permissions enforced by entrypoint: chmod 700 .secrets/
```

### Container Security

```
┌──────────────────────────────────────────────────────────────────┐
│  SECURITY BOUNDARIES                                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  Container: oc-titan                                   │     │
│  │                                                        │     │
│  │  • Runs as root (default)                              │     │
│  │  • Network: bridge (isolated from host)                │     │
│  │  • Mounts: agent home (rw), config (ro), brain (ro)   │     │
│  │  • No privileged mode                                  │     │
│  │  • No host network access                              │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  RECOMMENDATIONS:                                                │
│  • Use --read-only flag for containers                           │
│  • Add cap_drop: ALL for hardened deployments                    │
│  • Use Docker secrets for sensitive values                       │
│  • Rotate bot tokens periodically                                │
│  • Enable Telegram's allowed users list                          │
└──────────────────────────────────────────────────────────────────┘
```

### Hardened docker-compose.yml (Optional)

```yaml
services:
  titan:
    # ... existing config ...
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
```

---

## Testing

### Test Suite Structure

```
<RUNTIME_ROOT>/docker/tests/
├── conftest.py                 Shared fixtures
├── run_tests.sh                Test runner
├── test_agent_brain_mcp.py     MCP server unit tests
├── test_entrypoint.py          Config generation tests
├── test_docker_infra.py        Dockerfile/compose validation
├── test_bootstrap.py           CLI command tests
└── test_smoke.py               Live container smoke tests
```

### Running Tests

```bash
cd ~/.openclaw/docker

# Unit + infrastructure tests (no containers needed)
./tests/run_tests.sh

# All tests including smoke tests (requires running containers)
./tests/run_tests.sh --all

# Specific categories
./tests/run_tests.sh --unit
./tests/run_tests.sh --infra
./tests/run_tests.sh --bootstrap
./tests/run_tests.sh --smoke

# Pattern matching
./tests/run_tests.sh -k test_memory

# Verbose
./tests/run_tests.sh -v
```

### Test Coverage

| Suite | Tests | Dependencies |
|-------|-------|-------------|
| agent_brain_mcp | Server creation, memory tools, skills, sessions, identity, helpers | mcp package |
| entrypoint | Config generation, MCP injection, directory structure, permissions | bash, python3 |
| docker_infra | Dockerfile, compose structure, volume mounts, build context | generated files |
| bootstrap | CLI dispatch, flag parsing, agent discovery, docker generation | agent-bootstrap.sh |
| smoke | Container health, config validation, MCP brain, bind mounts | running containers |

---

## Troubleshooting

### Decision Tree

```
Problem
  │
  ├─ Container won't start
  │   ├─ Check: docker compose logs <agent>
  │   ├─ Fix: Missing .env token → configure agent
  │   ├─ Fix: openclaw.json syntax → validate JSON
  │   └─ Fix: agent_brain_mcp.py missing → check toolkit dir
  │
  ├─ Agent not responding on Telegram
  │   ├─ Check: docker exec oc-<agent> ps aux | grep openclaw
  │   ├─ Check: docker exec oc-<agent> env | grep TELEGRAM
  │   ├─ Fix: Restart → docker compose restart <agent>
  │   └─ Fix: Wrong token → edit .env, restart
  │
  ├─ MCP brain errors
  │   ├─ Check: docker exec oc-<agent> python3 -c "from mcp..."
  │   ├─ Check: docker exec oc-<agent> python3 -c "from run_agent..."
  │   └─ Fix: Rebuild → docker compose build --no-cache
  │
  ├─ Host changes not appearing in container
  │   ├─ Check: docker inspect oc-<agent> | grep Binds
  │   ├─ Fix: Wrong mount path → fix docker-compose.yml
  │   └─ Fix: Container caching → restart container
  │
  └─ Permission denied errors
      ├─ Check: ls -la <RUNTIME_ROOT>/agents/<agent>/.secrets/
      ├─ Fix: chmod 700 <RUNTIME_ROOT>/agents/<agent>/.secrets/
      └─ Fix: chown -R $(id -u):$(id -g) <RUNTIME_ROOT>/agents/<agent>/
```

### Common Issues

**Issue: `docker compose up` fails with "no such file"**

```bash
# Cause: agent_brain_mcp.py not in toolkit dir
ls <RUNTIME_ROOT>/agents/.scripts/agent-toolkit/agent_brain_mcp.py

# Fix: Copy it
cp <RUNTIME_ROOT>/docker/agent_brain_mcp.py \
   <RUNTIME_ROOT>/agents/.scripts/agent-toolkit/
```

**Issue: Agent container starts but gateway crashes**

```bash
# Check logs
docker compose logs titan

# Common cause: malformed openclaw.json
# Fix: validate JSON
python3 -m json.tool ~/.openclaw/openclaw.json

# Common cause: missing bot token
grep TELEGRAM_BOT_TOKEN <RUNTIME_ROOT>/agents/titan/.env
```

**Issue: MCP brain returns import errors**

```bash
# Check hermes-agent is installed in container
docker exec oc-titan python3 -c "
import sys; sys.path.insert(0, '/app/hermes-agent')
from run_agent import AIAgent
print('OK')
"

# If fails: rebuild with hermes-agent source
cd ~/.openclaw/docker
docker compose build --no-cache
```

### Diagnostic Commands

```bash
# Full system diagnostic
echo "=== Docker ==="
docker compose ps
echo ""
echo "=== Container logs (last 20) ==="
for agent in titan allman guard; do
    echo "--- $agent ---"
    docker compose logs --tail=5 $agent 2>&1 | tail -3
done
echo ""
echo "=== Bind mounts ==="
docker inspect oc-titan --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}
{{end}}'
echo ""
echo "=== MCP config ==="
docker exec oc-titan cat <CONTAINER_ROOT>/.openclaw/openclaw.json | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('MCP:', list(d.get('mcp', {}).get('servers', {}).keys()))
print('Agents:', [a['id'] for a in d.get('agents', {}).get('list', [])])
"
```

---

## Appendix

### Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--openclaw` | `-o` | Use OpenClaw agent structure |
| `--dry-run` | `-n` | Preview actions without executing |
| `--force` | `-f` | Overwrite existing files (backs up first) |
| `--yes` | `-y` | Skip all confirmation prompts |

### Commands Reference

| Command | Description | Example |
|---------|-------------|---------|
| `init <name>` | Create new agent | `./agent-bootstrap.sh -o init titan` |
| `scan` | Health check all agents | `./agent-bootstrap.sh scan` |
| `sync` | Reconcile files, offer Docker | `./agent-bootstrap.sh sync` |
| `configure <name>` | Interactive agent setup | `./agent-bootstrap.sh configure titan` |
| `config` | Generate openclaw.json | `./agent-bootstrap.sh config` |
| `docker [dir]` | Generate Docker files | `./agent-bootstrap.sh docker` |
| `repair <name>` | Fix broken agent config | `./agent-bootstrap.sh repair titan` |
| `link <name>` | Symlink core skills | `./agent-bootstrap.sh link titan` |
| `unlink <name>` | Remove skill symlinks | `./agent-bootstrap.sh unlink titan` |
| `list` | Show agent status | `./agent-bootstrap.sh list` |
| `delete <name>` | Remove agent (backs up) | `./agent-bootstrap.sh delete titan` |

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `HERMES_HOME` | `~/.hermes` | Base Hermes directory |
| `OPENCLAW_ROOT` | `~/.openclaw` | OpenClaw directory |
| `AGENTS_ROOT` | (unset) | Override agent directory root |
| `HERMES_BIN` | auto-detected | Path to `hermes` binary |
| `AGENT_ID` | (required) | Agent identifier (container) |
| `TELEGRAM_BOT_TOKEN` | (required) | Telegram bot token (container) |
| `PYTHONPATH` | (auto-set) | Include hermes-agent source |

### File Formats

**agent.json** (builder code):
```json
{
  "builderCode": {
    "code": "bc_26ulyc23",
    "hex": "0x62635f3236756c79633233",
    "owner": "0x12F1B38DC35AA65B50E5849d02559078953aE24b",
    "hardwired": true,
    "enforced": true
  }
}
```

---

**Version:** 3.4.0
**Builder Code:** bc_26ulyc23
**Last Updated:** 2026-04-18

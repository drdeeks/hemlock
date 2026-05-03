# Hemlock Enterprise Agent Framework
## Comprehensive Encyclopedia — Every Function, Flag, Config, and Q&A

> **Version:** 3.4.0 | **Builder Code:** `bc_26ulyc23` | **Updated:** 2026-05-03

---

## Table of Contents

1. [What Is Hemlock?](#1-what-is-hemlock)
2. [Architecture Deep Dive](#2-architecture-deep-dive)
3. [Directory Reference (Complete)](#3-directory-reference-complete)
4. [First-Run Initialization System](#4-first-run-initialization-system)
5. [Environment & Configuration Reference](#5-environment--configuration-reference)
6. [runtime.sh — Master CLI (Every Command)](#6-runtimesh--master-cli-every-command)
7. [Agent Lifecycle — Every Script](#7-agent-lifecycle--every-script)
8. [Crew System — Every Script](#8-crew-system--every-script)
9. [Memory Injection System](#9-memory-injection-system)
10. [Backup & Recovery System](#10-backup--recovery-system)
11. [Shared Library: lib/common.sh](#11-shared-library-libcommonsh)
12. [Shared Helpers: scripts/helpers.sh](#12-shared-helpers-scriptshelperssh)
13. [Diagnostics & Doctor Tools](#13-diagnostics--doctor-tools)
14. [Testing Framework](#14-testing-framework)
15. [Skills System (216+ Skills)](#15-skills-system-216-skills)
16. [Plugin System](#16-plugin-system)
17. [Agent Toolkit (agent-bootstrap.sh)](#17-agent-toolkit-agent-bootstrapsh)
18. [MCP Brain Server](#18-mcp-brain-server)
19. [Docker Build System](#19-docker-build-system)
20. [Security Model](#20-security-model)
21. [Self-Healing & Retry System](#21-self-healing--retry-system)
22. [GitHub Integration](#22-github-integration)
23. [Complete Q&A](#23-complete-qa)
24. [Troubleshooting Decision Trees](#24-troubleshooting-decision-trees)
25. [Glossary](#25-glossary)
26. [Changelog](#26-changelog)

---

## 1. What Is Hemlock?

Hemlock Enterprise Agent Framework is a **production-ready multi-agent AI system** built on top of:

- **OpenClaw Gateway** — Node.js message routing, Telegram/API adapters, session management
- **Hermes Agent Brain** — Python MCP server powering each agent's reasoning loop (40+ tools)
- **Hemlock Runtime** — Bash orchestration layer managing agent/crew lifecycle, memory, backups, diagnostics

The framework lets you create, configure, deploy, and operate networks of persistent AI agents that share memory, work in crews, and run autonomously in Docker containers.

### Core design principles

| Principle | Implementation |
|-----------|---------------|
| Single source of truth | `agents/<id>/` on host = agent workspace; bind-mounted read-write into container |
| No duplication | Edit host files → changes appear instantly inside container |
| Portability | Each agent is fully self-contained; backup = `cp -ra agents/<id>/ backup/` |
| Security by default | Read-only FS, `cap_drop: ALL`, ICC disabled, no privileged mode |
| Self-healing | `lib/common.sh` retry loops + `with_self_healing()` wrapping all critical ops |
| 216+ skills | Modular skill library; agents load only what they need |

---

## 2. Architecture Deep Dive

### System topology

```
                        ┌──────────────────────────────┐
                        │        Telegram Cloud         │
                        │  ┌────┐  ┌────┐  ┌────┐     │
                        │  │Bot1│  │Bot2│  │Bot3│     │
                        └──┼────┼──┼────┼──┼────┼─────┘
                           │    │  │    │  │    │
              ┌────────────┼────┼──┼────┼──┼────┼───────────┐
              │  Host OS   ▼    ▼  ▼    ▼  ▼    ▼           │
              │                                              │
              │  ┌─────────────────────────────────────┐    │
              │  │       Docker Bridge Network          │    │
              │  │           (openclaw)                 │    │
              │  └──────┬──────────┬──────────┬────────┘    │
              │         │          │          │              │
              │  ┌──────▼─┐  ┌────▼──┐  ┌───▼───┐         │
              │  │oc-agent1│  │oc-agent2│ │oc-crew│         │
              │  │GW+Brain│  │GW+Brain│ │GW+Brain│         │
              │  └──────┬─┘  └────┬──┘  └───┬───┘         │
              └─────────┼─────────┼──────────┼─────────────┘
                        │         │          │
                   agents/<id>/ (bind-mounted from host)
```

### Container internals

Each container (`oc-<agent_id>`) runs two cooperating processes:

```
┌──────────────────────────────────────────────────────────┐
│  Container: oc-<agent_id>                                │
│                                                          │
│  ┌─────────────────────┐    ┌────────────────────────┐   │
│  │  OpenClaw Gateway   │    │  Hermes Brain MCP      │   │
│  │  (Node.js)          │MCP │  Server (Python)        │   │
│  │                     │◄──►│                        │   │
│  │  • Telegram adapter │    │  agent_chat()           │   │
│  │  • Message routing  │    │  agent_memory_get()     │   │
│  │  • Session mgmt     │    │  agent_memory_set()     │   │
│  │  • Tool orch.       │    │  agent_skills_list()    │   │
│  │  • Config loading   │    │  agent_insights()       │   │
│  └─────────┬───────────┘    │  agent_sessions()       │   │
│            │                │  agent_identity()       │   │
│            └───────┬────────┘                         │   │
│                    ▼                                   │   │
│   /data/agents/<id>/  (bind-mounted from host)        │   │
│   SOUL.md  USER.md  MEMORY.md  sessions/  skills/     │   │
└──────────────────────────────────────────────────────────┘
```

### Message flow (Telegram → Response)

```
User → Telegram → OpenClaw Gateway
  → Creates session
  → MCP call: agent_chat(message)
  → Hermes Brain:
      1. Load SOUL.md + USER.md + MEMORY.md + skills
      2. Call LLM (Nous/OpenRouter/Anthropic/OpenAI)
      3. Execute tool calls (terminal, files, web, browser, ...)
      4. Loop max 15 turns until final response
      5. Update MEMORY.md if insights detected
  → Gateway → Telegram → User
```

### Data flow: host ↔ container

```
HOST                           CONTAINER
agents/<id>/                   /data/agents/<id>/
  SOUL.md       ────────────►    SOUL.md       (same file, bind-mount)
  USER.md       ────────────►    USER.md
  MEMORY.md     ────────────►    MEMORY.md     (read+write)
  config.yaml   ────────────►    config.yaml
  .env          ────────────►    .env
  memory/       ────────────►    memory/       (read+write)
  sessions/     ────────────►    sessions/     (read+write)
  skills/       ────────────►    skills/       (read+write)
  .secrets/     ────────────►    .secrets/     (mode 700)

config/         ────────────►  /data/config/   (read-only)
lib/common.sh   ────────────►  /app/lib/       (read-only)
```

---

## 3. Directory Reference (Complete)

```
hemlock-enterprise/                   ← RUNTIME_ROOT
│
├── runtime.sh                        Master CLI (1,457 lines)
├── build.sh                          One-shot Docker build script
├── docker-compose.yml                Multi-service orchestration (4 named services)
├── Dockerfile                        Agent container image definition
├── entrypoint.sh                     Per-agent bootstrap + MCP injection
├── .env                              Runtime secrets (never in Docker image)
├── .env.template                     Template for .env
├── .dockerignore                     Docker build exclusions
│
├── agents/                           ← AGENTS_DIR / AGENTS_ROOT
│   └── <agent-id>/                   One directory per agent
│       ├── SOUL.md                   Personality, values, behavior
│       ├── USER.md                   User context, preferences
│       ├── MEMORY.md                 Persistent memory (auto-updated)
│       ├── AGENTS.md                 Multi-agent coordination
│       ├── HEARTBEAT.md              Heartbeat/status context
│       ├── IDENTITY.md               Extended identity details
│       ├── TOOLS.md                  Tool preferences/config
│       ├── config.yaml               Model, tools, memory, skills config
│       ├── agent.json                Builder code + agent metadata
│       ├── .env                      API keys, bot tokens (mode 600)
│       ├── data/                     Agent data files
│       ├── config/                   Agent config overrides
│       ├── logs/                     Per-agent logs
│       ├── skills/                   Agent-owned skills + symlinks to core
│       ├── tools/                    Tool state, cache, memory-context.md
│       │   └── memory-context.md     Injected memory context (tool-inject-memory.sh)
│       ├── memory/                   Structured memory directory
│       │   ├── notes/                Categorized notes
│       │   ├── skills-learned.md     Auto-learned capabilities
│       │   └── YYYY-MM-DD.md         Daily memory files
│       ├── sessions/                 Conversation transcripts (JSONL)
│       ├── projects/                 Project workspaces
│       ├── .secrets/                 Secret storage (mode: 700)
│       ├── .backups/                 Auto-backups before modifications
│       ├── .hermes/                  Hermes runtime files
│       └── .archive/                 Archived sessions/data
│
├── crews/                            ← CREWS_DIR
│   └── <crew-name>/
│       ├── crew.yaml                 Crew config (channel, status, agents list)
│       └── logs/
│           └── crew.log              Crew activity log
│
├── config/                           ← CONFIG_DIR
│   ├── runtime.yaml                  Gateway port, token, security settings
│   ├── gateway.yaml                  Gateway-specific config
│   ├── model-config.yaml             Active model, backend, quant (first-run writes this)
│   └── backup-config.yaml            Backup system configuration
│
├── scripts/                          ← All lifecycle scripts
│   ├── helpers.sh                    Shared helper functions (sourced by all scripts)
│   ├── agent-create.sh               Create new agent
│   ├── agent-delete.sh               Delete agent (with backup)
│   ├── agent-import.sh               Import agent from external source
│   ├── agent-export.sh               Export agent to external destination
│   ├── agent-monitor.sh              Monitor agent activity
│   ├── agent-control.sh              start/stop/restart/status via Docker Compose
│   ├── agent-run.sh                  Spawn agent container with dynamic config
│   ├── agent-stop.sh                 Clean container shutdown
│   ├── agent-restart.sh              Stop + run (passes overrides)
│   ├── agent-logs.sh                 Stream live container logs
│   ├── crew-create.sh                Create crew + assign agents
│   ├── crew-start.sh                 Start all agents in crew
│   ├── crew-stop.sh                  Stop all agents in crew
│   ├── crew-monitor.sh               Monitor crew and agent status
│   ├── crew-join.sh                  Add agent to existing crew
│   ├── crew-leave.sh                 Remove agent from crew
│   ├── crew-dissolve.sh              End crew session + cleanup
│   ├── tool-inject-memory.sh         Inject memory context into agent tools
│   ├── backup-interactive.sh         Full-featured backup system (1,623 lines)
│   ├── runtime-doctor.sh             Runtime validation + auto-fix
│   └── system/
│       ├── first-run.sh              First-time initialization (5 phases)
│       ├── hemlock-doctor.sh         Comprehensive diagnostics (1,722 lines)
│       ├── hardware-scanner.sh       CPU/GPU/memory hardware detection
│       ├── llama-build.sh            Llama.cpp build with hardware optimization
│       ├── model-manager.sh          Download, convert, manage GGUF models
│       └── security-scanner.sh       Security posture checks
│
├── lib/
│   └── common.sh                     Shared library: logging, retry, self-healing
│
├── skills/
│   └── skills/                       216+ skill modules
│       └── <skill-name>/
│           └── SKILL.md              Skill instructions
│
├── plugins/
│   ├── tool-enforcement/
│   │   └── plugin.yaml               Hooks: pre_llm_call, pre_tool_call
│   ├── backup-protocol/
│   │   └── README.md
│   └── crews/                        Crew templates and blueprints
│       └── crewsscripts/
│
├── tools/
│   └── agent-toolkit/
│       ├── README.md                 Toolkit documentation (1,331 lines)
│       ├── agent-bootstrap.sh        Main CLI for agent lifecycle
│       ├── agent_brain_mcp.py        MCP server (Hermes brain)
│       ├── skill-scanner.sh          Skill scanner bash wrapper
│       └── skill_scanner.py          SQLite-backed skill scanner
│
├── tests/
│   ├── run_all.sh                    Test runner (discovers all categories)
│   ├── run-all-tests.sh              Alias runner
│   ├── test-helpers.sh               Shared test utilities
│   ├── validation/                   Validation tests
│   ├── unit/                         Unit tests
│   ├── integration/                  Integration tests
│   ├── e2e/                          End-to-end tests
│   └── security/                     Security tests
│
├── logs/                             ← LOG_DIR
│   ├── runtime.log                   System-wide runtime log
│   └── <agent-id>.log                Per-agent log
│
├── backups/                          Default backup destination
│   ├── .backup-key                   AES-256 encryption key
│   └── backup-<YYYYMMDD-HHMMSS>/     Timestamped backup directories
│       └── BACKUP_MANIFEST.txt
│
├── models/
│   └── gguf/                         GGUF model files
│       └── qwen3-0_6b-Q4_K_M.gguf   Default model
│
├── bin/
│   └── llama-cli                     Llama.cpp binary (built by first-run)
│
├── docker/                           Generated Docker files
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── docker-compose.yml
│   └── hermes-agent/
│
├── docs/
│   └── README.md                     Documentation index
│
└── .cache/
    ├── .first_run_completed          First-run flag file
    ├── hardware-scan.json            Hardware scan results
    └── hardware-scan-recommendations.json  Model/quant recommendations
```

---

## 4. First-Run Initialization System

**Script:** `scripts/system/first-run.sh`

Automatically invoked on first startup (when `.cache/.first_run_completed` does not exist). Runs 5 sequential phases. Subsequent starts skip all phases.

### Initialization phases

| Phase | Name | What happens |
|-------|------|-------------|
| 1 | System Hardware Scan | Runs `hardware-scanner.sh`; writes `hardware-scan.json` and `hardware-scan-recommendations.json` to `.cache/` |
| 2 | Llama.cpp Build | Checks for `bin/llama-cli`; if absent, runs `llama-build.sh build` (falls back to `build-cpu` on failure) |
| 3 | Model Download & Conversion | Runs `model-manager.sh setup --quant <QUANT> --model qwen3-0.6b`; reads recommended quantization from Phase 1 results |
| 4 | System Configuration | Calls `update_default_agent()` (writes `config/model-config.yaml`, updates `.env` and `config/runtime.yaml`); creates helper agent |
| 5 | Finalization | Writes `.cache/.first_run_completed`; runs 5 verification checks; writes `logs/INITIALIZATION_SUMMARY.md` |

### Functions in first-run.sh

| Function | Purpose |
|----------|---------|
| `is_first_run()` | Returns 0 if `.cache/.first_run_completed` absent |
| `is_initialized()` | Returns 0 if GGUF model or persistent config exists |
| `mark_first_run_complete()` | Writes timestamp to `.cache/.first_run_completed` |
| `create_helper_agent()` | Creates `agents/helper/` with agent.json, INSTRUCTIONS.md, MEMORY.md, SOUL.md, USER.md, AGENT_TYPE.txt, ROLE.txt, `.default`, `.main`, `.system`, `.priority` |
| `update_default_agent(model_path)` | Updates `DEFAULT_AGENT_MODEL` in `.env`, `default_model` in `config/runtime.yaml`, writes `config/model-config.yaml` |
| `phase_system_scan()` | Runs hardware-scanner.sh |
| `phase_llama_build()` | Builds llama-cli binary |
| `phase_model_setup()` | Downloads + converts Qwen3-0.6B to GGUF |
| `phase_configuration(model_path)` | Writes configs + creates helper agent |
| `phase_finalization()` | Writes flag, verifies 5 checks, writes summary |
| `full_initialization()` | Orchestrates all 5 phases; tracks timing |

### Helper agent (`agents/helper/`)

The helper is a safe chatbot created at first run:
- **Model:** Qwen3-0.6B (Q4_K_M), backend: Llama.cpp
- **Allowed:** `web_browse` tool only
- **Excluded tools:** `code_execution`, `file_read`, `file_write`, `file_delete`, `bash`
- **Capabilities:** Chat, knowledgebase, documentation, system_info
- **Config:** temperature 0.3, top_p 0.9, context 4096, max_tokens 4096, mirostat_mode 2
- **Flags:** `is_default: true`, `is_main: true`, `startup_active: true`, `system_agent: true`

### Default model config (`config/model-config.yaml`)

```yaml
default_model: Qwen3-0.6B
default_quant: Q4_K_M
default_backend: llama.cpp
active_model: Qwen3-0.6B
first_run_initialized: true

models:
  - name: Qwen3-0.6B
    repo: Qwen/Qwen3-0.6B
    path: <path-to-gguf>
    enabled: true
    default: true
    quantizations: [Q4_K_M, Q5_K_M, Q8_0]

system:
  auto_detected: true
  initialization_complete: true
```

### Forcing re-initialization

```bash
rm -f .cache/.first_run_completed
./runtime.sh initialize
```

---

## 5. Environment & Configuration Reference

### `.env` / `.env.template` — All variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_IMAGE` | `openclaw/gateway:latest` | Docker image for gateway |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Gateway bind mode (`lan`, `localhost`, `all`) |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway listen port |
| `OPENCLAW_GATEWAY_TOKEN` | `change_this_to_a_secure_token` | Auth token for gateway API |
| `OPENCLAW_CONFIG_DIR` | `~/.openclaw` | OpenClaw configuration directory |
| `OPENCLAW_WORKSPACE_DIR` | `~/.openclaw/workspace` | OpenClaw workspace directory |
| `GOG_KEYRING_PASSWORD` | _(empty)_ | Keyring password for encrypted secrets |
| `XDG_CONFIG_HOME` | `/home/node/.openclaw` | XDG config home override |
| `DEFAULT_AGENT_MODEL` | `nous/mistral-large` | Default LLM model |
| `DEFAULT_AGENT_NETWORK` | `agents_net` | Default Docker network |
| `MODEL_BACKEND` | `ollama` | Model backend (`ollama`, `llamacpp`, `openrouter`) |
| `DEFAULT_MODEL` | _(from backend)_ | Model name for selected backend |
| `OLLAMA_HOST` | _(set per env)_ | Ollama API endpoint |
| `LLAMACPP_HOST` | _(set per env)_ | llama.cpp server endpoint |
| `OPENROUTER_API_KEY` | _(required for openrouter)_ | OpenRouter API key |
| `AGENTS_ROOT` | `agents/` | Root path for agent directories |
| `AGENT_APP_DIR_NAME` | `app` | Subdirectory name for agent app files |
| `AGENT_DATA_DIR_NAME` | `data` | Subdirectory name for agent data |
| `AGENT_CONFIG_DIR_NAME` | `config` | Subdirectory name for agent config |
| `LOGS_ROOT` | `logs/` | Root for log files |

### `config/runtime.yaml` — Full reference

```yaml
runtime:
  gateway:
    port: 18789              # Gateway listen port
    token: "..."             # Auth token (change in production)
    bind: "lan"              # lan | localhost | all
  agents:
    default_model: "nous/mistral-large"   # Default LLM
    default_network: "agents_net"         # Docker network name
  security:
    read_only: true          # Agent containers use read-only filesystem
    cap_drop: true           # Drop all Linux capabilities
    icc: false               # Disable inter-container communication
    tmpfs: true              # Mount /tmp as tmpfs
    tmpfs_size: "64m"        # tmpfs size limit
  logging:
    level: "info"            # Log level: debug | info | warn | error
    max_size: "10m"          # Max log file size
    max_files: 5             # Number of log files to keep
```

### `agents/<id>/config.yaml` — Per-agent config

```yaml
agent:
  id: <agent_id>
  name: <display_name>
  model: "nous/mistral-large"       # LLM model
  personality: "default"
  memory:
    enabled: true
    max_chars: 100000               # Max memory context chars
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
```

### Agent identity files

| File | Purpose |
|------|---------|
| `SOUL.md` | Personality, values, principles, behavioral constraints |
| `USER.md` | User profile, name, role, timezone, preferences |
| `AGENTS.md` | Multi-agent coordination protocols, peer agents |
| `HEARTBEAT.md` | Heartbeat context, current status, live state |
| `IDENTITY.md` | Extended identity details |
| `TOOLS.md` | Tool preferences, restrictions, default behaviors |
| `MEMORY.md` | Persistent memory (auto-updated by brain on insights) |

### `agent.json` — Builder code structure

```json
{
  "id": "<agent_id>",
  "name": "<display_name>",
  "description": "...",
  "model": "<model_path>",
  "backend": "llama.cpp",
  "type": "chatbot",
  "role": "assistant",
  "personality": "...",
  "capabilities": ["chat", "knowledgebase"],
  "tools": ["web_browse"],
  "excluded_tools": ["code_execution"],
  "enabled": true,
  "active": true,
  "config": {
    "temperature": 0.3,
    "top_p": 0.9,
    "top_k": 50,
    "max_tokens": 4096,
    "context_size": 4096,
    "repeat_penalty": 1.1,
    "threads": 4,
    "batch_size": 512
  },
  "builderCode": {
    "code": "bc_26ulyc23",
    "hardwired": true,
    "enforced": true
  }
}
```

---

## 6. runtime.sh — Master CLI (Every Command)

`runtime.sh` is the 1,457-line master CLI. It is the primary entry point for all operations.

### Synopsis

```
./runtime.sh <command> [arguments] [flags]
```

### Agent commands

| Command | Description | Example |
|---------|-------------|---------|
| `create-agent <id>` | Create new agent with full directory structure | `./runtime.sh create-agent myagent` |
| `delete-agent <id>` | Delete agent (prompts; backs up to `backups/agents/`) | `./runtime.sh delete-agent myagent` |
| `import-agent <src> <id>` | Import agent from path/archive | `./runtime.sh import-agent /tmp/export/ myagent` |
| `export-agent <id> <dest>` | Export agent to path/archive | `./runtime.sh export-agent myagent /tmp/export/` |
| `list-agents` | List all agents with status | `./runtime.sh list-agents` |
| `agent-status <id>` | Show detailed status of one agent | `./runtime.sh agent-status myagent` |
| `start-agent <id>` | Start agent container | `./runtime.sh start-agent myagent` |
| `stop-agent <id>` | Stop agent container | `./runtime.sh stop-agent myagent` |
| `restart-agent <id>` | Restart agent container | `./runtime.sh restart-agent myagent` |
| `agent-logs <id>` | Stream agent container logs | `./runtime.sh agent-logs myagent` |
| `monitor-agent <id>` | Monitor agent metrics | `./runtime.sh monitor-agent myagent` |

### Crew commands

| Command | Description | Example |
|---------|-------------|---------|
| `create-crew <name> <agents...>` | Create crew with listed agents | `./runtime.sh create-crew devteam agent1 agent2` |
| `start-crew <name>` | Start all agents in crew | `./runtime.sh start-crew devteam` |
| `stop-crew <name>` | Stop all agents in crew | `./runtime.sh stop-crew devteam` |
| `dissolve-crew <name>` | End crew session + cleanup | `./runtime.sh dissolve-crew devteam` |
| `crew-status <name>` | Show crew and all member status | `./runtime.sh crew-status devteam` |
| `join-crew <crew> <agent>` | Add agent to existing crew | `./runtime.sh join-crew devteam newagent` |
| `leave-crew <crew> <agent>` | Remove agent from crew | `./runtime.sh leave-crew devteam oldagent` |
| `list-crews` | List all crews | `./runtime.sh list-crews` |
| `monitor-crew <name>` | Monitor crew live | `./runtime.sh monitor-crew devteam` |

### Memory commands

| Command | Description | Example |
|---------|-------------|---------|
| `inject-memory <id>` | Inject all memory context into agent | `./runtime.sh inject-memory myagent` |
| `inject-memory <id> --daily-only` | Inject only today's daily memory | `./runtime.sh inject-memory myagent --daily-only` |

### System commands

| Command | Description | Example |
|---------|-------------|---------|
| `initialize` | Run first-run initialization | `./runtime.sh initialize` |
| `status` | Show system status | `./runtime.sh status` |
| `doctor` | Run diagnostics (hemlock-doctor.sh) | `./runtime.sh doctor` |
| `doctor check` | Run all health checks | `./runtime.sh doctor check` |
| `runtime-doctor` | Legacy runtime validation | `./runtime.sh runtime-doctor` |
| `runtime-doctor --fix` | Auto-fix runtime issues | `./runtime.sh runtime-doctor --fix` |

### Backup commands

| Command | Description | Example |
|---------|-------------|---------|
| `backup` | Run backup with current config | `./runtime.sh backup` |
| `backup init` | Interactive backup setup wizard | `./runtime.sh backup init` |
| `backup status` | Show backup config and last backup | `./runtime.sh backup status` |
| `backup list` | List available backups | `./runtime.sh backup list` |
| `backup validate` | Verify latest backup integrity | `./runtime.sh backup validate` |

### Docker commands

| Command | Description | Example |
|---------|-------------|---------|
| `build` | Build all Docker images | `./runtime.sh build` |
| `up` | Start all Docker services | `./runtime.sh up` |
| `down` | Stop all Docker services | `./runtime.sh down` |
| `ps` | Show running containers | `./runtime.sh ps` |

### Help

```bash
./runtime.sh --help
./runtime.sh <command> --help
```

---

## 7. Agent Lifecycle — Every Script

### `scripts/helpers.sh` — Shared helper functions

Sourced by virtually every script in `scripts/`. Do not call directly.

#### Every function

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `generate_random_token` | `()` | 32-char hex string | `openssl rand -hex 16` |
| `agent_exists` | `(agent_id)` | 0/1 | Tests `-d "$AGENTS_DIR/$agent_id"` |
| `list_existing_agents` | `()` | stdout | Lists `~/.openclaw/agents/` (legacy path) |
| `validate_agent_id` | `(agent_id)` | 0/1 + error msg | Regex: `^[a-z][a-z0-9_-]{2,15}$` (3-16 chars, start with letter) |
| `check_docker` | `()` | 0/1 | Checks `docker` command + `docker info` |
| `check_docker_compose` | `()` | 0/1 | Checks `docker-compose` command |
| `check_port_available` | `(port)` | 0/1 | `ss -tuln \| grep ":$port "` |
| `create_agent_structure` | `(agent_id)` | — | Creates `data/`, `config/`, `logs/`, `skills/`, `tools/`; writes default `config.yaml`, `data/SOUL.md`, `data/AGENTS.md` |
| `validate_yaml` | `(file)` | 0/1 | Uses `yq eval '.'`; skips if `yq` absent |
| `log` | `(level, message)` | — | Appends `[$ts] [$level] $msg` to `$LOG_DIR/runtime.log` |
| `agent_log` | `(agent_id, level, message)` | — | Appends to `$LOG_DIR/$agent_id.log` |
| `is_service_running` | `(service_name)` | 0/1 | `docker ps --format '{{.Names}}' \| grep "^$service_name$"` |
| `get_agent_container` | `(agent_id)` | string | Returns `oc-<agent_id>` |

#### Agent ID constraints (enforced by `validate_agent_id`)

- Length: 3–16 characters
- Must start with a lowercase letter (`a-z`)
- Allowed characters: `a-z`, `0-9`, `_`, `-`
- Pattern: `^[a-z][a-z0-9_-]{2,15}$`

---

### `scripts/agent-create.sh`

Creates a new agent directory with full structure.

**Usage:**
```bash
./scripts/agent-create.sh <agent_id> [--model <model>] [--personality <p>]
```

**What it creates:**
```
agents/<id>/
  data/SOUL.md           Default soul with id, purpose, capabilities, limitations
  data/AGENTS.md         Default workspace file
  config.yaml            Default config (model: nous/mistral-large, memory.max_chars: 100000)
  config/                Empty config overrides directory
  logs/                  Empty logs directory
  skills/                Empty skills directory
  tools/                 Empty tools directory
```

**Default `config.yaml` generated:**
```yaml
agent:
  id: <agent_id>
  name: <agent_id>
  model: "nous/mistral-large"
  personality: "default"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
```

---

### `scripts/agent-delete.sh`

Deletes an agent. Backs up first by default.

**Usage:**
```bash
./scripts/agent-delete.sh <agent_id> [--force] [--no-backup]
```

| Flag | Effect |
|------|--------|
| `--force` | Skip confirmation prompt |
| `--no-backup` | Delete without creating backup |

**Backup location:** `backups/agents/<agent_id>-<timestamp>/`

---

### `scripts/agent-import.sh`

Import an agent from an external source. Uses `cp -ra "$SOURCE/." "$DEST/"` to preserve hidden files.

**Usage:**
```bash
./scripts/agent-import.sh <source_path> <agent_id> [--overwrite]
```

**Supported sources:**
- Directory path
- `.tar.gz` archive (auto-extracted)
- `.zip` archive (auto-extracted)

**Hidden file preservation:** Uses `cp -ra "$SOURCE/." "$DEST/"` pattern — the trailing `/.` ensures all hidden files (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env`) are copied.

---

### `scripts/agent-export.sh`

Export an agent to a destination.

**Usage:**
```bash
./scripts/agent-export.sh <agent_id> <dest_path> [--compress] [--exclude-secrets]
```

| Flag | Effect |
|------|--------|
| `--compress` | Create `.tar.gz` archive |
| `--exclude-secrets` | Skip `.secrets/` and `.env` |

---

### `scripts/agent-monitor.sh`

Monitor agent activity in real time.

**Usage:**
```bash
./scripts/agent-monitor.sh <agent_id> [--follow] [--stats]
```

---

### `scripts/agent-control.sh`

Low-level container control: start / stop / restart / status.

**Usage:**
```bash
./scripts/agent-control.sh <command> <agent_id> [--force]
```

**Commands:**

| Command | What happens |
|---------|-------------|
| `start` | Checks `is_service_running(oc-<id>)`; if already running, exits 0; else `docker-compose up -d oc-<id>`; verifies started; logs INFO |
| `stop` | Checks running; `docker-compose stop oc-<id>`; verifies stopped; with `--force`, uses `docker rm -f oc-<id>` if graceful stop fails |
| `restart` | Calls `stop`, sleeps 2s, calls `start` |
| `status` | `docker ps --filter "name=oc-<id>"` or prints "STOPPED" |

**Container naming:** `oc-<agent_id>` (prefix `oc-` hardwired in `get_agent_container()`)

**`--force` flag:** Only applies to `stop`; uses `docker rm -f` if graceful stop fails.

---

### `scripts/agent-run.sh`

Spawns an agent container from scratch with dynamic configuration and optional env overrides.

**Usage:**
```bash
./scripts/agent-run.sh <AGENT_ID> [VAR=value ...]
```

**Examples:**
```bash
./scripts/agent-run.sh my-agent
./scripts/agent-run.sh my-agent MODEL_BACKEND=ollama DEFAULT_MODEL=codellama
./scripts/agent-run.sh my-agent OPENROUTER_API_KEY=sk-xxx DEFAULT_MODEL=claude-3
```

**What it does:**
1. Sources `.env` (with `set -a` to auto-export)
2. Exports overrides from CLI arguments
3. Constructs `AGENT_PATH`, `AGENT_APP_PATH`, `AGENT_DATA_PATH`, `AGENT_CONFIG_PATH`
4. Creates directories (`$AGENTS_ROOT/$AGENT_ID/{app,data,config}`, `$LOGS_ROOT`)
5. Validates model backend (connectivity check for ollama/llamacpp; API key check for openrouter)
6. Runs `docker compose -p "$AGENT_ID" -f docker-compose.yml up -d --build`
7. Prints status with `docker compose -p "$AGENT_ID" ps`

**Backend validation:**

| Backend | Check | Error condition |
|---------|-------|----------------|
| `ollama` | `curl -sf $OLLAMA_HOST/api/tags` | Warning only (continues) |
| `llamacpp` | `curl -sf $LLAMACPP_HOST/health` | Warning only (continues) |
| `openrouter` | `$OPENROUTER_API_KEY` set | Fatal error if unset |

---

### `scripts/agent-stop.sh`

Stops a running agent container cleanly.

**Usage:**
```bash
./scripts/agent-stop.sh <AGENT_ID>
```

Runs: `docker compose -p "$AGENT_ID" -f docker-compose.yml down`

---

### `scripts/agent-restart.sh`

Calls `agent-stop.sh` then `agent-run.sh`, passing any overrides through.

**Usage:**
```bash
./scripts/agent-restart.sh <AGENT_ID> [VAR=value ...]
```

---

### `scripts/agent-logs.sh`

Streams live log output from the agent's Docker Compose project.

**Usage:**
```bash
./scripts/agent-logs.sh <AGENT_ID>
```

Runs: `docker compose -p "$AGENT_ID" -f docker-compose.yml logs -f`

---

## 8. Crew System — Every Script

A **crew** is a named group of agents sharing a communication channel (`CREW_CHANNEL` environment variable). The channel name defaults to `crew-<crew_name>`.

### `scripts/crew-create.sh`

Creates a new crew and assigns initial agents.

**Usage:**
```bash
./scripts/crew-create.sh <crew_name> [agent1 agent2 ...]
```

**Crew name constraints:** 3–21 characters, alphanumeric.

**What it creates:**
```
crews/<crew_name>/
  crew.yaml          channel, status: active, created, agents list
  logs/crew.log      Empty log file
```

**crew.yaml structure:**
```yaml
name: <crew_name>
channel: crew-<crew_name>
status: active
created: <ISO8601 timestamp>
agents:
  - <agent1>
  - <agent2>
```

---

### `scripts/crew-start.sh`

Starts all agent containers in a crew.

**Usage:**
```bash
./scripts/crew-start.sh <crew_name>
```

Reads `crew.yaml`, calls `agent-control.sh start <agent>` for each member.

---

### `scripts/crew-stop.sh`

Stops all agent containers in a crew.

**Usage:**
```bash
./scripts/crew-stop.sh <crew_name>
```

---

### `scripts/crew-monitor.sh`

Monitors crew and member agent status.

**Usage:**
```bash
./scripts/crew-monitor.sh <crew_name> [--status] [--follow] [--logs]
```

**Flags:**

| Flag | Effect |
|------|--------|
| `--status` | Show agent status (default) |
| `--follow` | `tail -f` the crew log in real time |
| `--logs` | Show last 50 lines of `crews/<name>/logs/crew.log` |

**Per-agent display (when running):**
- Container status string
- Container name (`oc-<id>`)
- CREW_CHANNEL value (read from container env via `docker inspect`)
- Live CPU/memory stats via `docker stats --no-stream`

---

### `scripts/crew-join.sh`

Adds an agent to an existing crew.

**Usage:**
```bash
./scripts/crew-join.sh <crew_name> <agent_id> [--force]
```

**What it does:**
1. Validates crew exists (`crews/<crew_name>/` directory)
2. Validates agent exists (`agents/<agent_id>/` directory)
3. Checks if already in crew (exits 0 without `--force`)
4. Appends `- <agent_id>` to `crew.yaml` agents list via `awk`
5. Updates `docker-compose.yml`: adds `CREW_CHANNEL=<channel>` to agent's environment block
6. Installs default skills via `skills-install.sh --quiet <agent_id>`
7. Appends join event to `crews/<name>/logs/crew.log`

**After joining — required steps:**
```bash
./scripts/agent-control.sh stop <agent_id>
docker compose build oc-<agent_id>
./scripts/agent-control.sh start <agent_id>
```

---

### `scripts/crew-leave.sh`

Removes an agent from a crew.

**Usage:**
```bash
./scripts/crew-leave.sh <crew_name> <agent_id>
```

**What it does:**
1. Removes `- <agent_id>` from `crew.yaml` agents list via `awk`
2. Removes `CREW_CHANNEL=...` from that agent's environment block in `docker-compose.yml`
3. Logs leave event to crew log
4. Warns if crew now has zero members (suggests dissolving)

---

### `scripts/crew-dissolve.sh`

Ends a crew session permanently.

**Usage:**
```bash
./scripts/crew-dissolve.sh <crew_name> [--force]
```

**What it does:**
1. Shows warning with channel and members list
2. Prompts for confirmation (skipped with `--force`)
3. Stops all running agent containers: `docker compose -f docker-compose.yml stop oc-<agent>`
4. Removes `CREW_CHANNEL=...` entries from `docker-compose.yml` for all members (via `awk`)
5. Updates `crew.yaml`: `status: active → status: dissolved`
6. Appends `dissolved: <ISO8601>` to `crew.yaml`
7. Logs dissolution to `crews/<name>/logs/crew.log`

**After dissolving:**
- Crew data remains in `crews/<crew_name>/` for debugging
- Agents can be started individually or added to new crews
- To fully remove: `rm -rf crews/<crew_name>/`

---

## 9. Memory Injection System

**Script:** `scripts/tool-inject-memory.sh`

Builds `agents/<id>/tools/memory-context.md` by aggregating multiple memory sources. This file is loaded by the Hermes brain as additional context.

### Usage

```bash
./scripts/tool-inject-memory.sh [flags] <agent_id>
./runtime.sh inject-memory <agent_id> [flags]
```

### Flags

| Flag | Effect |
|------|--------|
| `--all` | Inject all memory sources (default behavior) |
| `--force` | Overwrite existing memory-context.md without prompt |
| `--quiet` | Suppress non-error output |
| `--daily-only` | Only inject today's daily memory file |
| `--verify` | Verify injection without writing |
| `--date <YYYY-MM-DD>` | Use a specific date for daily memory (default: today) |

### Sources injected into `memory-context.md`

| File | Where it comes from |
|------|-------------------|
| `SOUL.md` | `agents/<id>/data/SOUL.md` |
| `USER.md` | `agents/<id>/data/USER.md` |
| `IDENTITY.md` | `agents/<id>/data/IDENTITY.md` |
| `MEMORY.md` | `agents/<id>/data/MEMORY.md` |
| `AGENTS.md` | `agents/<id>/data/AGENTS.md` |
| Daily memory | `data/memory/YYYY-MM-DD.md` |
| `HEARTBEAT.md` | `agents/<id>/data/HEARTBEAT.md` |
| Projects | `agents/<id>/projects/` |
| Sessions | `agents/<id>/sessions/` |
| Workflow info | `agents/<id>/agent.json` |

### Size limits

| Limit | Value |
|-------|-------|
| Per-file maximum | 10 MB |
| Total context maximum | 50 MB |

### Output location

`agents/<id>/tools/memory-context.md`

This file is bind-mounted into the container at `/data/agents/<id>/tools/memory-context.md` and automatically discovered by the Hermes brain MCP server.

---

## 10. Backup & Recovery System

**Script:** `scripts/backup-interactive.sh` (1,623 lines)

A comprehensive backup system with multiple modes, levels, backends, encryption, compression, and scheduling.

### Synopsis

```bash
./scripts/backup-interactive.sh [command] [flags]
```

### Commands

| Command | Description |
|---------|-------------|
| `backup` | Run backup with current/flag config (default if no command given) |
| `init` | Interactive setup wizard (writes `config/backup-config.yaml`) |
| `restore` | Restore from backup (stub — use plugins/backup-protocol for full restore) |
| `status` | Show current config and last backup info |
| `list` | List all available backups |
| `validate` | Verify integrity of latest backup |
| `test` | Run test suite against all backup modes |
| `help` | Show usage |

### Backup modes (`--mode`)

| Mode | Description |
|------|-------------|
| `plan-history` | Configs + identity files only; excludes Docker images, archives, large binaries |
| `docker-full` | Everything including Docker images and volumes |
| `combo` | Configurable mix (default) |

### Backup levels (per scope)

| Level | Includes | Excludes |
|-------|----------|---------|
| `configs` | Config files, SOUL/USER/IDENTITY/MEMORY/AGENTS.md | sessions/, logs/, temp/ |
| `full` | Everything including logs and sessions | Nothing additional |
| `workspaces` | Everything except temp files | temp/, tmp/ |

### Scope flags

| Flag | Effect |
|------|--------|
| `--crews <name1,name2>` | Backup specific named crews (comma-separated) |
| `--agents <name1,name2>` | Backup specific named agents (comma-separated) |
| `--all-crews` | Backup all crews |
| `--all-agents` | Backup all agents |
| `--crew <level>` | Set crew backup level (`configs`, `full`, `workspaces`) |
| `--agent <level>` | Set agent backup level (`configs`, `full`) |
| `--combo <mode>` | Combo shorthand (see table below) |

### Combo modes (`--combo`)

| Combo | Crew level | Agent level |
|-------|-----------|-------------|
| `crews-configs` | configs | configs |
| `crews-full` | full | full |
| `crews-workspaces` | workspaces | configs |
| `all-full` | workspaces | full |

### Content flags

| Flag | Effect |
|------|--------|
| `--include-hidden` | Include hidden files (`.secrets/`, `.hermes/`, `.env`, etc.) |
| `--exclude-hidden` | Exclude hidden files |
| `--include-git` | Include `.git/` directories |
| `--exclude-git` | Exclude `.git/` (default) |
| `--compress` | Create `.tar.gz` archive from backup directory |
| `--encrypt` | AES-256-CBC encrypt `.env` and `.secrets/` files |
| `--setup-timer` | Configure cron job for automatic backups |
| `--dry-run` | Show what would happen without actually writing |

### Backup types (set during `init`)

| Type | Where backups go |
|------|-----------------|
| `local` | Local directory (default: `backups/`) |
| `external` | External mount point |
| `ssh` | SSH destination (`ssh://user@host/path`) |
| `git` | Git repository (auto-commits + pushes) |
| `cloud` | Cloud URL (S3, GCS, etc.) |

### Backup destination structure

```
backups/
└── backup-<YYYYMMDD-HHMMSS>/
    ├── BACKUP_MANIFEST.txt        Metadata: timestamp, mode, selections, file counts
    ├── crews/
    │   └── <crew_name>/           Crew data at requested level
    ├── agents/
    │   └── <agent_id>/            Agent data at requested level
    ├── docker/
    │   ├── images/                Saved Docker images (*.tar)
    │   └── volumes/               Docker volume archives (*.tar.gz)
    ├── config/                    Runtime configs
    ├── sessions/                  Sessions (if full backup)
    ├── workflows/                 Workflows (if full backup)
    └── plugins/                   Plugin configs
```

### Encryption

- Algorithm: AES-256-CBC via `openssl enc`
- Key storage: `backups/.backup-key` (generated by `generate_encryption_key()`)
- Key archive: `config/encryption-keys/`
- Files encrypted: `.env`, `auth.json`, `.secrets/*` in each agent directory
- Encrypted files get `.enc` extension

### Exclude logic

Always excluded:
- System cruft: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.log`
- Development: `node_modules/` (when lockfile exists), `__pycache__/`, `*.pyc`, `venv/`
- Build artifacts: `*.tar`, `*.gz`, `*.zip` (in `plan-history` mode)

Conditionally excluded:
- `node_modules/` only if a lockfile (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`) exists in source
- `.git/` when `INCLUDE_GIT=false` (default)
- Hidden files when `INCLUDE_HIDDEN=false`

### Scheduling (`--setup-timer`)

Installs a cron job:
```cron
0 */6 * * *  /path/to/scripts/backup-interactive.sh backup
```
If `crontab` is unavailable, writes `crontab-entry.txt` for manual installation.

### Core internal functions

| Function | Purpose |
|----------|---------|
| `load_config()` | Reads `config/backup-config.yaml`; sets all runtime variables |
| `save_config()` | Writes current settings to `config/backup-config.yaml` |
| `generate_encryption_key()` | `openssl rand -base64 32` → `backups/.backup-key` |
| `get_encryption_key()` | Returns path to key file |
| `encrypt_file(src, dest, key)` | `openssl enc -aes-256-cbc` |
| `check_destination(dest, type)` | Validates write access to backup destination |
| `setup_backup_timer()` | Installs cron job |
| `verify_module_capability(dir)` | Checks npm/pip/docker availability + registry access |
| `verify_backup_integrity(dir)` | Checks expected dirs/files; reads manifest; counts files |
| `get_excludes()` | Builds rsync `--exclude=` list from all settings |
| `backup_directory(src,dest,manifest,section,level)` | Core rsync-based backup with all excludes |
| `backup_standard_directory(...)` | Wraps `backup_directory` with `configs` level |
| `backup_full_directory(...)` | Wraps `backup_directory` with `full` level |
| `backup_docker_images(dest)` | Saves project-specific Docker images as `.tar` files |
| `backup_docker_volumes(dest)` | Archives named Docker volumes as `.tar.gz` via busybox |
| `backup_sessions(dest, manifest)` | Sessions backup (only if `FULL_BACKUP=true`) |
| `backup_workflows(dest, manifest)` | Workflows backup (only if `FULL_BACKUP=true`) |
| `enrypt_sensitive(dest_dir, key)` | Encrypts `.env`, `auth.json`, `.secrets/*` in all agent dirs |
| `cmd_backup()` | Main backup command; orchestrates all above functions |
| `cmd_init()` | Interactive setup wizard |
| `cmd_restore()` | Restore stub |
| `cmd_status()` | Print current config + last backup |
| `cmd_list()` | List backups in destination |
| `cmd_validate()` | Run `verify_backup_integrity` on latest |
| `cmd_test()` | 7-test suite covering all modes, levels, flags |

### `cmd_test()` test suite

| Test | What it verifies |
|------|----------------|
| 1 | Specific crew backup with `--dry-run` |
| 2 | Specific agent backup with `--dry-run` |
| 3 | All agents/crews at `configs` level |
| 4 | All agents/crews at `full` level |
| 5 | All 4 combo modes |
| 6 | `--include-hidden` and `--exclude-hidden` |
| 7 | `--include-git` and `--exclude-git` |

---

## 11. Shared Library: lib/common.sh

Sourced by `runtime.sh`, test runners, and system scripts. Provides standardized logging, retry logic, and self-healing.

### Logging functions

| Function | Prefix | Description |
|----------|--------|-------------|
| `log "msg"` | `[INFO]` blue | General information |
| `success "msg"` | `[PASS]` green | Successful operation |
| `warn "msg"` | `[WARN]` yellow | Non-fatal warning (to stderr) |
| `error "msg"` | `[FAIL]` red | Error (to stderr) |
| `fatal "msg"` | `[FAIL]` red | Error + `exit 1` |

All functions include caller context: `${FUNCNAME[1]:-main}`.

### Retry functions

```bash
retry_with_fallback "primary_cmd" "fallback_cmd" [max_attempts=3] [delay_seconds=1]
```

- Attempts `primary_cmd` up to `max_attempts` times
- Waits `delay_seconds` between attempts (exponential backoff supported)
- If all primary attempts fail, runs `fallback_cmd`
- Returns exit code of final attempt

### Self-healing wrapper

```bash
with_self_healing "operation_description"
```

Wraps a function call with automatic error detection and recovery. Used in backup, agent start/stop, and system initialization. Logs to `logs/runtime.log` via `log()`.

### Standard exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Usage/argument error |
| 3 | Dependency missing |
| 4 | Permission denied |

---

## 12. Shared Helpers: scripts/helpers.sh

### `validate_agent_id` — ID rules enforced

```bash
validate_agent_id "my-agent"         # OK: starts with letter, valid chars
validate_agent_id "1bad"             # FAIL: starts with digit
validate_agent_id "ab"               # FAIL: too short (min 3)
validate_agent_id "verylongagentid17"  # FAIL: too long (max 16)
validate_agent_id "my agent"         # FAIL: contains space
validate_agent_id "my_agent-1"       # OK: underscore and dash allowed
```

Regex: `^[a-z][a-z0-9_-]{2,15}$`

### `create_agent_structure` — Default files

Calling `create_agent_structure <id>` creates:

```bash
agents/<id>/data/           # Agent data directory
agents/<id>/config/         # Config overrides
agents/<id>/logs/           # Runtime logs
agents/<id>/skills/         # Skills directory
agents/<id>/tools/          # Tools directory
agents/<id>/config.yaml     # Default YAML config
agents/<id>/data/SOUL.md    # Default soul (capabilities + limitations)
agents/<id>/data/AGENTS.md  # Default workspace file
```

### Test ID conventions

Tests use time-based IDs to avoid collision:
```bash
pfx-$(date +%s | tail -c 5)   # e.g. pfx-34521
```
This satisfies: starts with letter, 3-16 chars, all lowercase.

---

## 13. Diagnostics & Doctor Tools

### `scripts/system/hemlock-doctor.sh` (1,722 lines)

Comprehensive system diagnostics tool with interactive and batch modes.

**Usage:**
```bash
./scripts/system/hemlock-doctor.sh <command> [options]
```

#### Commands

| Command | Description |
|---------|-------------|
| `check` | Run ALL health checks; returns health score % |
| `status` | Show system status (runtime root, version, init status) |
| `diagnose` | Interactive step-by-step diagnosis |
| `info` | OS, CPU, memory, disk, Hemlock version info |
| `services` | Check running services |
| `dependencies` | Check required + optional dependencies |
| `configuration` | Validate config files |
| `models` | Check GGUF model files |
| `agents` | Check agent configurations (agent.json presence) |
| `security` | Security posture checks |
| `troubleshoot` | Interactive troubleshooting assistant |
| `report` | Generate full diagnostic report |
| `fix` | Attempt to fix common issues |

#### Options

| Option | Effect |
|--------|--------|
| `--dry-run` | Show what would be checked without running |
| `--verbose`, `-v` | Verbose output |
| `--json` | Output all results as JSON |
| `--help`, `-h` | Show help |
| `--category <c>` | Run only a specific category |

#### Health check scoring

Hemlock Doctor calculates a health score from individual checks:

```
health_score = (checks_passed / checks_total) * 100
```

| Score | Rating |
|-------|--------|
| >= 90% | Excellent |
| >= 70% | Good |
| >= 50% | Fair |
| < 50% | Poor — Attention required |

#### Checks performed

| Category | Checked items |
|----------|---------------|
| Directory structure | `agents/`, `config/`, `scripts/`, `.cache/`, `models/`, `logs/` |
| Critical files | `hardware-scanner.sh`, `llama-build.sh`, `model-manager.sh`, `first-run.sh`, `runtime.sh` |
| Dependencies | `git`, `make`, `cmake`, `python3`, `jq` (required); `huggingface-cli`, `git-lfs`, `docker` (optional) |
| Initialization | `.cache/.first_run_completed` flag |
| Default model | `models/gguf/qwen3-0_6b-Q4_K_M.gguf` |
| Llama.cpp | `bin/llama-cli` binary |
| Agents | Count of agents with valid `agent.json` |

#### Dependency categories

| Category | Tools checked |
|----------|--------------|
| Build Tools | git, make, cmake |
| Compilers | gcc, g++, clang, clang++ |
| Python | python3, python3-pip, python3-venv |
| Utilities | jq, curl, wget, tar, gzip |
| Optional | huggingface-cli, git-lfs, docker |

#### JSON output mode

```bash
./scripts/system/hemlock-doctor.sh check --json
# Returns structured JSON with all check results, counts, health score
```

#### Internal functions

| Function | Purpose |
|----------|---------|
| `check_command(cmd, name)` | Command existence + path |
| `check_dir(dir, name)` | Directory existence |
| `check_file(file, name)` | File existence + size |
| `check_executable(file, name)` | File is executable |
| `show_system_info()` | OS, kernel, CPU, memory, disk stats |
| `get_version()` | Reads `VERSION`, git tag, or returns `dev-YYYYMMDD` |
| `run_health_checks()` | Runs all checks; calculates score |
| `check_dependencies()` | All dependency categories |
| `check_configuration()` | Config file validation |

---

### `scripts/runtime-doctor.sh`

Lighter, interactive runtime validator and auto-fixer.

**Usage:**
```bash
./scripts/runtime-doctor.sh [flags]
```

**Flags:**

| Flag | Effect |
|------|--------|
| `--full` | Run complete validation suite |
| `--interactive` | Enter interactive menu (8 options) |
| `--docker` | Docker environment check only |
| `--config` | Config validation only |
| `--fix` | Apply auto-fixes |

**Interactive menu options:**

1. Check Docker Environment
2. Check Runtime Structure
3. Validate Configurations
4. Check Security Settings
5. Check System Health
6. Run Full Validation
7. Apply Auto-Fixes
8. Exit

**Auto-fix capabilities (`--fix`):**
- Creates missing directories (`agents/`, `config/`, `logs/`, `scripts/`)
- Generates default `docker-compose.yml` with gateway service
- Generates default `config/runtime.yaml` with security settings
- Enables `read_only: true` in runtime config
- Enables `cap_drop: true` in runtime config
- Disables ICC in `docker-compose.yml`
- Enables `read_only`/`cap_drop` in all agent configs

**Tracking counters:**
- `WARNINGS` — non-fatal issues found
- `ERRORS` — fatal issues found
- `FIXED` — auto-fixes applied

**Security checks:**
- `runtime.security.read_only` == `true`
- `runtime.security.cap_drop` == `true`
- `runtime.security.icc` == `false`
- `com.docker.network.bridge.enable_icc: "false"` in `docker-compose.yml`
- Per-agent `security.read_only` and `security.cap_drop`

---

## 14. Testing Framework

**Runner:** `tests/run_all.sh`

### Test structure

```
tests/
├── run_all.sh          Main runner
├── run-all-tests.sh    Alias
├── test-helpers.sh     Shared test utilities (sourced by tests)
├── validation/         Structural validation tests
├── unit/               Unit tests (no Docker required)
├── integration/        Integration tests
├── e2e/                End-to-end tests (Docker required)
└── security/           Security tests
```

### Usage

```bash
# Run all categories
./tests/run_all.sh

# Run one category only
./tests/run_all.sh validation
./tests/run_all.sh unit

# Run single test file
./tests/run_all.sh "" tests/unit/test_agent_id.sh
```

### How the runner discovers tests

1. For each category directory, finds all files (executable or `.sh`)
2. Sorts files alphabetically
3. Runs each with `bash "$test_file"` — exit code 0 = PASS, non-zero = FAIL
4. Accumulates `TOTAL_TESTS`, `PASSED_TESTS`, `FAILED_TESTS`, `SKIPPED_TESTS`
5. Prints summary with green/red/yellow counts

### Test counters and results

```bash
TEST_RESULTS["category/test_name"]="PASS"|"FAIL"
TOTAL_TESTS       # total count
PASSED_TESTS      # exit-0 count
FAILED_TESTS      # non-zero exit count
SKIPPED_TESTS     # skipped (Docker not available, etc.)
```

### Current test coverage

28 test files, all passing (1 skip: Docker consistency test requires live Docker daemon).

| Suite | Key areas covered |
|-------|------------------|
| validation | Agent ID format, directory structure, YAML validity |
| unit | `validate_agent_id`, `create_agent_structure`, `log()`, `agent_log()` |
| integration | Agent create/delete cycle, crew create/join/leave |
| e2e | Full agent run in container (requires Docker) |
| security | Secret file permissions, ICC settings, cap_drop config |

### test-helpers.sh utilities

```bash
# Assert equality
assert_eq "expected" "actual" "test description"

# Assert file exists
assert_file_exists "/path/to/file"

# Assert directory exists
assert_dir_exists "/path/to/dir"

# Assert command succeeds
assert_success "command args"

# Create test agent ID
TEST_ID="pfx-$(date +%s | tail -c 5)"
```

---

## 15. Skills System (216+ Skills)

Skills live in `skills/skills/<skill-name>/SKILL.md`. Each skill contains instructions, examples, and optionally scripts.

### How agents load skills

1. Agent's `skills/` directory contains symlinks to core skills or owned skills
2. `scripts/crew-join.sh` calls `skills-install.sh --quiet <agent_id>` after crew join
3. `tools/agent-bootstrap.sh link <agent_id>` creates symlinks to all core skills
4. Hermes brain MCP server's `agent_skills_list()` enumerates `agents/<id>/skills/`

### Skill structure

```
skills/skills/<name>/
└── SKILL.md            Instructions, examples, trigger words
```

### Agent-owned skills

```
agents/<id>/skills/
├── github -> ../../skills/skills/github    (symlink to core)
├── custom-skill/                           (agent-owned skill)
│   └── SKILL.md
```

### Skill scanner

`tools/agent-toolkit/skill-scanner.sh` / `skill_scanner.py`:
- SQLite-backed index of all discovered skills
- Searches by keyword, category, or trigger phrase
- Used internally to suggest relevant skills to agents

### Bootstrap commands for skills

```bash
# Link all core skills to agent
./tools/agent-toolkit/agent-bootstrap.sh link <agent_id>

# Remove skill symlinks
./tools/agent-toolkit/agent-bootstrap.sh unlink <agent_id>
```

---

## 16. Plugin System

Plugins live in `plugins/` and integrate via hook points.

### Plugin manifest (`plugin.yaml`)

```yaml
name: <plugin_name>
version: <semver>
description: <description>
provides_hooks:
  - pre_llm_call
  - pre_tool_call
```

### Available hook points

| Hook | Triggered |
|------|----------|
| `pre_llm_call` | Before every LLM API call |
| `pre_tool_call` | Before every tool execution |

### `plugins/tool-enforcement/plugin.yaml`

```yaml
name: tool-enforcement
version: 2.0.0
description: Tool guidance, chmod 700 prohibition, path enforcement, and violation logging
provides_hooks:
  - pre_llm_call
  - pre_tool_call
```

This plugin:
- Blocks agents from changing `.secrets/` permissions (`chmod 700` prohibition)
- Enforces allowed tool paths
- Logs all tool violations

### `plugins/backup-protocol/`

Full backup and restore documentation. See `plugins/backup-protocol/README.md`.

### `plugins/crews/crewsscripts/`

Crew templates, blueprints, and scripted workflows for common crew configurations.

---

## 17. Agent Toolkit (agent-bootstrap.sh)

`tools/agent-toolkit/agent-bootstrap.sh` — The main lifecycle CLI for creating, scanning, and managing agents from the toolkit layer.

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--openclaw` | `-o` | Use OpenClaw agent structure |
| `--dry-run` | `-n` | Preview actions without executing |
| `--force` | `-f` | Overwrite existing files (backs up first) |
| `--yes` | `-y` | Skip all confirmation prompts |

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init <name>` | Create new agent with interactive setup | `./agent-bootstrap.sh -o init titan` |
| `scan` | Health check all agents | `./agent-bootstrap.sh scan` |
| `sync` | Reconcile files; offer Docker generation | `./agent-bootstrap.sh sync` |
| `configure <name>` | Interactive bot token + provider setup | `./agent-bootstrap.sh configure titan` |
| `config` | Generate `agents-config-generated.json` | `./agent-bootstrap.sh config` |
| `docker [dir]` | Generate `docker/Dockerfile`, `entrypoint.sh`, `docker-compose.yml` | `./agent-bootstrap.sh docker` |
| `repair <name>` | Fix broken agent config | `./agent-bootstrap.sh repair titan` |
| `link <name>` | Symlink core skills to agent | `./agent-bootstrap.sh link titan` |
| `unlink <name>` | Remove core skill symlinks from agent | `./agent-bootstrap.sh unlink titan` |
| `list` | Show all agents with status | `./agent-bootstrap.sh list` |
| `delete <name>` | Remove agent (backs up first) | `./agent-bootstrap.sh delete titan` |

### `init` — What gets created

```
agents/<name>/
  SOUL.md, USER.md, AGENTS.md, HEARTBEAT.md
  config.yaml, .env, agent.json
  memory/, sessions/, skills/, tools/, logs/, .secrets/, .backups/
```

### `scan` — Health check output

```
── Scanning: titan ──
  ✓ HERMES_HOME exists
  ✓ config.yaml: 4750 bytes
  ✓ .env: 69 lines
  ✓ Bot token configured
  ✓ API key configured
  ✓ .secrets/ permissions: 700
  ✓ Skills: 12 linked, 3 owned

Summary: 1 healthy, 1 warnings, 1 errors
```

### `docker` — Generated files

```
docker/
├── Dockerfile          Node.js + Python; installs openclaw + hermes-agent
├── entrypoint.sh       Per-agent MCP config injection + gateway start
├── docker-compose.yml  One service per agent; bind-mounted from host
└── hermes-agent/       Hermes source copy (build context)
```

Architecture:
- Agent homes bind-mounted: `agents/<name>/ -> /data/agents/<name>/` (read-write)
- `agent_brain_mcp.py` bind-mounted from toolkit (single source)
- `openclaw.json` bind-mounted from host config
- No Docker volumes — host filesystem IS the agent workspace

### `config` — Generated file

`agents-config-generated.json`:
```json
{
  "agents": {
    "list": [
      { "id": "titan", "name": "titan", "telegram_token": "..." }
    ]
  },
  "mcp": {
    "servers": { "brain": { "type": "stdio" } }
  }
}
```

### Supported API providers

| Provider | Environment variable | Key source |
|----------|---------------------|-----------|
| Nous Research | `NOUS_API_KEY` | inference-api.nousresearch.com |
| OpenRouter | `OPENROUTER_API_KEY` | openrouter.ai/keys |
| OpenAI | `OPENAI_API_KEY` | platform.openai.com |
| Anthropic | `ANTHROPIC_API_KEY` | console.anthropic.com |
| Telegram | `TELEGRAM_BOT_TOKEN` | @BotFather on Telegram |

### Environment variables (toolkit context)

| Variable | Default | Purpose |
|----------|---------|---------|
| `HERMES_HOME` | `~/.hermes` | Base Hermes directory |
| `OPENCLAW_ROOT` | `~/.openclaw` | OpenClaw directory |
| `AGENTS_ROOT` | _(unset)_ | Override agent directory root |
| `HERMES_BIN` | auto-detected | Path to `hermes` binary |
| `AGENT_ID` | _(required in container)_ | Agent identifier |
| `TELEGRAM_BOT_TOKEN` | _(required in container)_ | Telegram bot token |
| `PYTHONPATH` | auto-set | Include hermes-agent source |

---

## 18. MCP Brain Server

**Script:** `tools/agent-toolkit/agent_brain_mcp.py`

Python MCP server running inside each container. Receives tool calls from the OpenClaw Gateway and executes the Hermes agent loop.

### Available MCP tools

| Tool | Input | Output | Description |
|------|-------|--------|-------------|
| `agent_chat` | `message`, `max_turns`?, `system_prompt`? | `{response, turns, model}` | Full agent loop with tool calling |
| `agent_memory_get` | `query`?, `limit`? | `{count, memories[]}` | Search/retrieve memory files |
| `agent_memory_set` | `content`, `filename`? | `{ok, path, bytes}` | Store memory to file |
| `agent_skills_list` | _(none)_ | `{count, skills[]}` | List available skills |
| `agent_insights` | `days`? | `{sessions, tokens, cost}` | Usage analytics |
| `agent_sessions` | `limit`? | `{count, sessions[]}` | List recent sessions |
| `agent_identity` | _(none)_ | `{soul, user, config}` | Read all identity files |

### `agent_chat` processing pipeline

```
agent_chat("Deploy the latest version to staging")
  1. Build system prompt:
     ├── SOUL.md (personality)
     ├── USER.md (user context)
     ├── MEMORY.md (persistent memory)
     ├── skills context
     └── tool definitions
  2. Call LLM API (nous/openrouter/anthropic/openai)
  3. If tool call returned:
     ├── terminal: shell commands
     ├── read_file / write_file
     ├── web_search
     ├── browser automation
     └── 40+ other tools
  4. Send tool result back to LLM (loop)
  5. Repeat until final response (max_turns=15)
  6. Return final response
```

### 40+ available tools (Hermes agent)

| Category | Tools |
|----------|-------|
| Shell | `terminal`, `bash` |
| Files | `read_file`, `write_file`, `list_files`, `delete_file`, `find_file` |
| Web | `web_search`, `web_fetch`, `browser`, `screenshot` |
| Memory | `memory_read`, `memory_write`, `memory_search` |
| Code | `code_execution`, `python_repl`, `javascript_repl` |
| System | `system_info`, `env_read`, `process_list` |
| Git | `git_status`, `git_commit`, `git_diff` |
| APIs | `http_request`, `curl` |

---

## 19. Docker Build System

### `build.sh` — One-shot build

```bash
bash build.sh
```

Builds all Docker images for the framework. Run this locally; Docker daemon is not available in Replit's sandbox (kernel namespace restriction).

### `docker-compose.yml` — Services

Four named services:

| Service | Container name | Purpose |
|---------|---------------|---------|
| `openclaw-gateway` | `openclaw-gateway` | Main API gateway (port 18789) |
| `framework` | `framework` | Core framework service |
| `test-e2e-agent` | `test-e2e-agent` | E2E test agent |
| `crew-agent-1` | `crew-agent-1` | Crew agent template |

### Network

```yaml
networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"   # ICC disabled
```

### Gateway healthcheck

```yaml
healthcheck:
  test: ["CMD", "curl", "-fsS", "http://localhost:18789/healthz"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### `.dockerignore` — What is excluded from images

**Always excluded (security):**
- `.env`, `.env.*`, `*.env`, `*.secret`, `*.key`, `*.pem`, `*.enc`
- Any file matching `*token*`, `*secret*`, `*password*`, `*private*key*`, `*api*key*`
- `.git/`, `.gitignore`, `.gitmodules`

**Always excluded (size/cleanliness):**
- `*.md`, `*.rst`, `*.txt` (docs)
- `node_modules/`, `__pycache__/`, `*.pyc`
- `venv/`, `env/`, `.venv/`
- `*.log`, `*.tmp`, `.cache/`
- `build/`, `dist/`, `*.egg-info/`
- IDE files: `.idea/`, `.vscode/`, `*.swp`
- OS files: `.DS_Store`, `Thumbs.db`

**Exceptions — what IS included:**
```dockerignore
!config/runtime.yaml
!config/gateway.yaml
!agents/*/config.yaml
!agents/*/config.yml
!entrypoint.sh
!lib/
!lib/common.sh
!plugins/*/plugin.yaml
!plugins/*/plugin.yml
!docker-compose.yml
!Dockerfile
!scripts/
```

### Hardened container config (optional)

```yaml
services:
  my-agent:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
```

---

## 20. Security Model

### Defense layers

| Layer | Mechanism |
|-------|-----------|
| Network | ICC disabled (`enable_icc: false`), bridge isolation |
| Container | `cap_drop: ALL`, `read_only: true`, `no-new-privileges:true` |
| Filesystem | `.secrets/` mode 700, `.env` mode 600 |
| Secrets | AES-256-CBC encryption via openssl |
| Build | `.dockerignore` blocks all secrets, tokens, keys from images |
| Tools | `tool-enforcement` plugin blocks chmod 700 operations, logs violations |
| Runtime | Read-only filesystem + tmpfs for `/tmp` |

### File permissions

| Path | Mode | Access |
|------|------|--------|
| `agents/<id>/.secrets/` | 700 | Owner only (read, write, execute) |
| `agents/<id>/.env` | 600 | Owner read-write only |
| `agents/<id>/agent.json` | 644 | Owner rw, group/world read |
| `agents/<id>/config.yaml` | 644 | Owner rw, group/world read |
| `agents/<id>/*.md` | 644 | Owner rw, group/world read |

### What NEVER goes in Docker images

- `.env` files
- API keys (any file matching `*api*key*`)
- Tokens (any file matching `*token*`)
- Certificates (`*.pem`, `*.key`)
- Encrypted files (`*.enc`)
- Git history

### Secrets management workflow

```bash
# Store API key (goes to .env, mode 600)
echo 'NOUS_API_KEY=sk-xxx' >> agents/myagent/.env

# Store runtime secret (goes to .secrets/, mode 700)
echo 'my-secret' > agents/myagent/.secrets/my-secret

# Encrypt backup of secrets (AES-256-CBC)
./scripts/backup-interactive.sh backup --encrypt
```

### Security scanner

`scripts/system/security-scanner.sh` checks:
- `.secrets/` permissions (must be 700)
- `.env` permissions (must be 600)
- ICC status in `docker-compose.yml`
- `cap_drop` in agent configs
- `read_only` in agent configs
- No secrets in identity files (SOUL.md, MEMORY.md, USER.md)

### `hemlock-doctor.sh security` checks

```bash
./scripts/system/hemlock-doctor.sh security
```

Validates:
- `runtime.security.read_only == true`
- `runtime.security.cap_drop == true`
- `runtime.security.icc == false`
- ICC disabled in Docker network config
- Per-agent security settings for all configured agents

---

## 21. Self-Healing & Retry System

All critical operations in the framework are wrapped with self-healing and retry logic from `lib/common.sh`.

### Retry pattern

```bash
# Try command up to 3 times, with 1 second between attempts
# Falls back to fallback_cmd if all attempts fail
retry_with_fallback "primary_cmd" "fallback_cmd" 3 1
```

Used in:
- `backup_directory()` — `retry_with_fallback "mkdir -p $dest" "echo 'mkdir failed'"`
- `cmd_backup()` — destination creation and permission fixing
- `phase_llama_build()` — tries GPU build, falls back to CPU build

### Self-healing wrapper

```bash
with_self_healing "operation_name"
```

Monitors the wrapped operation. If it fails:
1. Logs the failure with timestamp and operation name
2. Attempts automatic remediation based on operation type
3. Retries the operation
4. If remediation fails, logs and continues (does not crash the framework)

Used in:
- `backup_directory()` — wraps entire backup operation
- `cmd_backup()` — wraps entire backup command
- `scripts/agent-control.sh` — wraps start/stop operations

### Self-healing behaviors

| Scenario | Auto-remediation |
|----------|----------------|
| Missing destination directory | `mkdir -p` with retry |
| Permission denied on destination | `chmod u+w` with retry |
| llama-build GPU failure | Falls back to CPU-only build |
| Agent start failure | Logs; triggers `agent_log` entry |
| Backup rsync errors | Suppresses non-fatal errors; continues |

---

## 22. GitHub Integration

The framework uses `GITHUB_TOKEN` for pushing the clean repository.

### Setup

The `GITHUB_TOKEN` secret is stored in Replit Secrets (not in any file).

### Fix-LFS-Push script

`scripts/fix-lfs-push.sh` — Used to push to GitHub after removing large LFS files:

```bash
GITHUB_TOKEN=$GITHUB_TOKEN bash scripts/fix-lfs-push.sh
```

This script:
1. Configures git with GITHUB_TOKEN for authentication
2. Pushes to `main` branch
3. Required because the repo previously had a 1.5GB `model.safetensors` file removed via `git filter-branch`

### Git backup integration

When `BACKUP_TYPE=git`:
```bash
./scripts/backup-interactive.sh init
# Select: 4) git
# Enter git URL

./scripts/backup-interactive.sh backup
# Runs: git add -A && git commit -m "backup: <timestamp> mode:<mode>" && git push
```

---

## 23. Complete Q&A

### Installation & Setup

**Q: What are the system requirements?**

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| OS | Ubuntu 22.04+ / Debian 12+ | Any Linux with kernel 5.4+ |
| RAM | 4GB | 8GB+ recommended for local models |
| Disk | 20GB | More for models (Qwen3-0.6B GGUF ~400MB Q4_K_M) |
| CPU | x86_64 or ARM64 | AVX2 recommended for llama.cpp |
| Docker | 20.10+ | Required for container runtime |
| Docker Compose | 2.0+ | `docker compose` (v2) preferred |
| Node.js | 22+ | OpenClaw gateway |
| Python | 3.11+ | Hermes brain |
| Git | 2.0+ | Source management |

**Q: Can I run this without Docker?**

Docker is required for the container runtime (agent containers run as `oc-<id>`). The framework CLI (`runtime.sh`) and scripts run on the host. You cannot run individual agents without Docker except in development/test mode.

**Q: How do I do a fresh start?**

```bash
rm -f .cache/.first_run_completed
./runtime.sh initialize
```

**Q: Can I use GPUs?**

Yes. The hardware scanner (`scripts/system/hardware-scanner.sh`) auto-detects:
- NVIDIA GPUs (via `nvidia-smi`)
- AMD GPUs (via `rocminfo`)
- Apple Silicon (M1/M2/M3 via Metal)
- AVX/AVX2/AVX512 CPU extensions

The llama-build script configures the correct build flags automatically.

**Q: Why can't Docker run in Replit?**

Replit's sandbox uses kernel namespace restrictions that prevent the Docker daemon from starting (`fork/exec /proc/self/exe: operation not permitted`). Build images locally with `bash build.sh` and push them, or use an external CI/CD system.

---

### Agent Management

**Q: What are valid agent IDs?**

- 3–16 characters
- Must start with a lowercase letter (`a-z`)
- Allowed: `a-z`, `0-9`, `_`, `-`
- Invalid: starts with digit, contains uppercase, spaces, or special chars
- Valid examples: `myagent`, `agent-1`, `dev_bot`, `titan`, `a1b`

**Q: How many agents can I run?**

No hard limit. Each agent uses one Docker container. Practical limits depend on RAM (each container ~200-500MB) and CPU.

**Q: How do I change an agent's model?**

```bash
# Edit agent config
vim agents/<id>/config.yaml
# Change: model: "nous/xiaomi/mimo-v2-pro"

# Or set via override at run time
./scripts/agent-run.sh <id> DEFAULT_MODEL=claude-3-sonnet MODEL_BACKEND=openrouter

# Restart agent
./scripts/agent-restart.sh <id>
```

**Q: How do I give an agent a Telegram bot?**

```bash
echo 'TELEGRAM_BOT_TOKEN=<your-token>' >> agents/<id>/.env
docker compose build oc-<id>
./scripts/agent-control.sh restart <id>
```

**Q: What is SOUL.md and how does it affect behavior?**

`SOUL.md` is injected as the system prompt prefix for every conversation. It defines identity, purpose, personality, values, and hard rules. Edit it freely — changes take effect on the next conversation without a restart (bind-mounted live).

**Q: What is the difference between `agent-control.sh` and `agent-run.sh`?**

| Script | Uses | Best for |
|--------|------|---------|
| `agent-control.sh start/stop/restart` | `docker-compose -f docker-compose.yml` | Managing pre-defined services in `docker-compose.yml` |
| `agent-run.sh` | `docker compose -p "$AGENT_ID"` | Spawning agents dynamically with env overrides |

They use different project scoping (`-p $AGENT_ID` vs the global compose file).

**Q: How do I view agent logs?**

```bash
./scripts/agent-logs.sh <agent_id>     # stream live
cat logs/runtime.log                    # system log
cat logs/<agent_id>.log                 # per-agent log
```

**Q: How do I back up a single agent?**

```bash
./scripts/backup-interactive.sh backup --agents <agent_id> --agent full
```

**Q: How do I move an agent to another machine?**

```bash
# Export (source)
./scripts/agent-export.sh <agent_id> /tmp/export/ --compress

# Transfer
scp /tmp/export.tar.gz user@target:/tmp/

# Import (target)
./scripts/agent-import.sh /tmp/export.tar.gz <agent_id>
```

**Q: What files are preserved during import/export?**

Import uses `cp -ra "$SOURCE/." "$DEST/"` — the trailing `/.` syntax ensures all hidden files are copied: `.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env`, `.env.enc`.

---

### Crew System

**Q: What is a crew?**

A crew is a named group of agents that share a communication channel (`CREW_CHANNEL` env var). When agents are in the same crew, they can coordinate through the shared channel.

**Q: What are valid crew names?**

3–21 characters, alphanumeric.

**Q: How do crews communicate?**

Each agent in a crew has `CREW_CHANNEL=crew-<crew_name>` injected as a Docker environment variable. The OpenClaw Gateway uses this to route crew-scoped messages.

**Q: What happens to agents when a crew is dissolved?**

1. Agent containers are stopped
2. `CREW_CHANNEL` is removed from each agent's `docker-compose.yml` environment
3. Crew YAML is updated to `status: dissolved` with timestamp
4. Agent directories and data are untouched
5. Agents can be restarted individually or added to new crews

**Q: How do I see which agents are in a crew?**

```bash
cat crews/<crew_name>/crew.yaml
# OR
./runtime.sh crew-status <crew_name>
# OR
./scripts/crew-monitor.sh <crew_name> --status
```

---

### Memory System

**Q: How does agent memory work?**

Memory operates at multiple levels:
1. **Identity files** (SOUL.md, USER.md, MEMORY.md) — loaded every conversation
2. **Daily memory** (`data/memory/YYYY-MM-DD.md`) — daily context
3. **Structured memory** (`memory/notes/`, `memory/skills-learned.md`) — categorized notes
4. **Sessions** (`sessions/*.jsonl`) — conversation transcripts
5. **Injected context** (`tools/memory-context.md`) — aggregated by `tool-inject-memory.sh`

**Q: How does memory-context.md get created?**

```bash
./scripts/tool-inject-memory.sh <agent_id>
# OR
./runtime.sh inject-memory <agent_id>
```

**Q: When does MEMORY.md auto-update?**

The Hermes brain MCP server detects "insights" in conversation turns and automatically calls `agent_memory_set()` to update `MEMORY.md`. No manual action needed.

**Q: How do I inject only today's memory?**

```bash
./scripts/tool-inject-memory.sh --daily-only <agent_id>
```

**Q: How do I inject memory for a specific date?**

```bash
./scripts/tool-inject-memory.sh --date 2026-04-15 <agent_id>
```

---

### Backup System

**Q: What is the difference between backup modes?**

| Mode | Use case |
|------|---------|
| `plan-history` | Quick backup of just configs and identity — fastest, smallest |
| `docker-full` | Complete backup including Docker images and volumes — largest |
| `combo` | Configurable mix — use for most production scenarios |

**Q: How do I set up automatic backups?**

```bash
./scripts/backup-interactive.sh init
# When prompted "Setup automatic timer? [Y/n]": Y
# When prompted "Timer interval (hours, default 6)": 6
```

**Q: How is encryption done?**

AES-256-CBC via OpenSSL:
```bash
openssl enc -aes-256-cbc -salt -in file -out file.enc -pass file:backups/.backup-key
```

Encrypted files: `.env`, `auth.json`, `.secrets/*` in each agent directory.

**Q: How do I restore from backup?**

```bash
# Find backup
ls backups/

# Restore specific agent
cp -ra backups/backup-<timestamp>/agents/<id>/ agents/<id>/

# Restore crew
cp -ra backups/backup-<timestamp>/crews/<name>/ crews/<name>/

# Verify
./scripts/backup-interactive.sh validate
```

**Q: What is in BACKUP_MANIFEST.txt?**

```
Backup Manifest
Timestamp: 2026-05-03T12:00:00Z
Mode: combo
Type: local
Crew selection: all
Crew level: configs
Agent selection: all
Agent level: full
Include hidden: true
Include git: false

Components:
  Agent: myagent: 147 files, 2.3M
  Crew: devteam: 12 files, 45K
```

---

### Diagnostics

**Q: How do I run a full health check?**

```bash
./scripts/system/hemlock-doctor.sh check
# OR
./runtime.sh doctor check
```

**Q: How do I auto-fix common issues?**

```bash
./scripts/runtime-doctor.sh --fix
```

**Q: How do I get JSON output from diagnostics?**

```bash
./scripts/system/hemlock-doctor.sh check --json
./scripts/system/hemlock-doctor.sh info --json
./scripts/system/hemlock-doctor.sh dependencies --json
```

**Q: What does the health score mean?**

- **90-100%:** Excellent — system fully operational
- **70-89%:** Good — minor missing components
- **50-69%:** Fair — some issues to address
- **< 50%:** Poor — significant problems require attention

---

### Security

**Q: How do I ensure `.secrets/` is properly protected?**

```bash
chmod 700 agents/<id>/.secrets/
./scripts/system/hemlock-doctor.sh security
```

**Q: How do I rotate the gateway token?**

```bash
NEW_TOKEN=$(openssl rand -hex 32)
sed -i "s/token: .*/token: \"$NEW_TOKEN\"/" config/runtime.yaml
sed -i "s/OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$NEW_TOKEN/" .env
./runtime.sh restart-agent openclaw-gateway
```

---

### Docker & Deployment

**Q: Why does `docker build` fail in Replit?**

Replit's sandbox kernel prevents Docker daemon operations. Build images on your local machine or a CI server using `bash build.sh`, then push to a registry and pull on the target server.

**Q: How do I build Docker images?**

```bash
bash build.sh
# OR
docker compose build
```

**Q: How do I update an agent without downtime?**

```bash
# Edit identity files — instant effect (bind-mounted)
vim agents/<id>/SOUL.md

# For Dockerfile changes: rebuild
docker compose build oc-<id>
docker compose up -d --no-deps oc-<id>
```

---

## 24. Troubleshooting Decision Trees

### Agent won't start

```
Agent won't start
  │
  ├─ Check: ./scripts/agent-logs.sh <id>
  │   ├─ "no such file or directory: docker-compose.yml"
  │   │    Fix: ./agent-bootstrap.sh docker
  │   │
  │   ├─ "TELEGRAM_BOT_TOKEN not set"
  │   │    Fix: echo 'TELEGRAM_BOT_TOKEN=...' >> agents/<id>/.env
  │   │
  │   ├─ "Cannot connect to Docker daemon"
  │   │    Fix: sudo systemctl start docker
  │   │
  │   └─ "agent.json: no such file"
  │        Fix: ./agent-bootstrap.sh -o init <id>
  │
  └─ Check: ./scripts/runtime-doctor.sh --docker
       └─ Fix issues found; then: ./scripts/agent-run.sh <id>
```

### Agent not responding on Telegram

```
No response
  │
  ├─ Check container running: docker ps | grep oc-<id>
  │   └─ Not running: ./scripts/agent-control.sh start <id>
  │
  ├─ Check gateway: docker exec oc-<id> ps aux | grep openclaw
  │   └─ Not running: docker compose restart oc-<id>
  │
  ├─ Check token: docker exec oc-<id> env | grep TELEGRAM
  │   └─ Wrong token: edit .env, restart agent
  │
  └─ Check logs: ./scripts/agent-logs.sh <id>
```

### Memory context not updating

```
Memory not updating
  │
  ├─ Check tools dir: ls agents/<id>/tools/
  │   └─ memory-context.md missing:
  │        ./scripts/tool-inject-memory.sh <id>
  │
  ├─ Check source files: ls agents/<id>/data/
  │   └─ Missing SOUL.md / MEMORY.md:
  │        ./scripts/agent-create.sh <id>
  │
  └─ Check size limits: du -sh agents/<id>/data/
      └─ Over 50MB: Use --daily-only flag or trim MEMORY.md
```

### Backup failing

```
Backup fails
  │
  ├─ "Cannot create destination": df -h (check disk space)
  │
  ├─ "rsync: command not found": apt install rsync
  │
  ├─ "Cannot write to destination": chmod u+w <backup_dir>
  │
  └─ "Encryption key not found":
       ./scripts/backup-interactive.sh init
```

### Health score is low

```
Low health score
  │
  ├─ ./scripts/system/hemlock-doctor.sh dependencies
  │    Install missing: git, make, cmake, python3, jq
  │
  ├─ ./scripts/system/hemlock-doctor.sh agents
  │    Fix: ./agent-bootstrap.sh -o init <id>
  │
  ├─ ./scripts/system/hemlock-doctor.sh configuration
  │    Fix: ./scripts/runtime-doctor.sh --fix
  │
  └─ Not initialized: ./runtime.sh initialize
```

---

## 25. Glossary

| Term | Definition |
|------|-----------|
| **Agent** | An autonomous AI entity with its own identity, memory, skills, and Docker container (`oc-<id>`) |
| **Agent ID** | 3–16 char lowercase identifier: `^[a-z][a-z0-9_-]{2,15}$` |
| **AGENTS_DIR** | `agents/` — root directory for all agent workspaces |
| **Builder Code** | Hardwired identifier `bc_26ulyc23` embedded in all agent.json files |
| **CREW_CHANNEL** | Docker env var injected into crew members; value is `crew-<crew_name>` |
| **Crew** | Named group of agents sharing a CREW_CHANNEL; 3–21 char alphanumeric name |
| **CREWS_DIR** | `crews/` — root directory for all crew configurations |
| **Gateway** | OpenClaw Node.js process handling Telegram/API adapters and session management |
| **GGUF** | File format for quantized LLM models used by llama.cpp |
| **Hermes Brain** | Python MCP server (`agent_brain_mcp.py`) providing the agent's reasoning loop |
| **ICC** | Inter-Container Communication — disabled in this framework for security |
| **Identity files** | SOUL.md, USER.md, IDENTITY.md, AGENTS.md, HEARTBEAT.md, TOOLS.md |
| **LOG_DIR** | `logs/` — directory for runtime.log and per-agent logs |
| **MCP** | Model Context Protocol — communication between Gateway and Brain server |
| **Memory context** | `agents/<id>/tools/memory-context.md` — aggregated by tool-inject-memory.sh |
| **MEMORY.md** | Persistent memory file; auto-updated by brain on insight detection |
| **nous/mistral-large** | Default LLM model configured in runtime.yaml |
| **OpenClaw** | The gateway platform (Node.js) at the top of the message routing stack |
| **Q4_K_M** | 4-bit quantization method; default for Qwen3-0.6B in Hemlock |
| **RUNTIME_ROOT** | Project root directory; auto-detected by scripts |
| **Self-healing** | `with_self_healing()` wrapper that auto-retries and remediates failed operations |
| **SKILL.md** | Instruction file for a skill module in `skills/skills/<name>/` |
| **Skills** | Modular capability modules (216+ available) loaded by agents |
| **SOUL.md** | Primary identity file defining agent personality and constraints |
| **tmpfs** | In-memory temporary filesystem mounted at `/tmp` in containers |
| **tool-enforcement** | Plugin (v2.0.0) enforcing tool usage policies via pre_llm_call/pre_tool_call hooks |

---

## 26. Changelog

### v3.4.0 (2026-05-03)

- Comprehensive encyclopedia README.md rewrite — all functions, flags, configs, Q&A
- `docker-compose.yml` rebuilt from scratch with 4 named services
- `build.sh` one-shot Docker build script added
- `scripts/system/first-run.sh` — 5-phase initialization fully documented
- `scripts/system/hemlock-doctor.sh` — full command reference (1,722 lines)
- All script flags and internal functions documented exhaustively
- Q&A section: 30+ answered questions across all subsystems
- Troubleshooting decision trees for all common failure modes

### v3.3.x

- `scripts/backup-interactive.sh` — AES-256-CBC encryption, cron scheduling, 7-test suite
- `scripts/crew-join.sh` / `crew-leave.sh` / `crew-dissolve.sh` — full crew lifecycle
- `scripts/tool-inject-memory.sh` — 10MB per-file / 50MB total size limits
- `lib/common.sh` — `with_self_healing()` and `retry_with_fallback()` added

### v3.2.x

- `tools/agent-toolkit/agent-bootstrap.sh` — full lifecycle CLI
- `tools/agent-toolkit/agent_brain_mcp.py` — 7 MCP tools
- 216+ skills in `skills/skills/`
- `plugins/tool-enforcement/` v2.0.0 with pre_llm_call hook

### v3.1.x

- GitHub integration — `GITHUB_TOKEN`, `scripts/fix-lfs-push.sh`
- Removed 1.5GB `model.safetensors` from git history via `filter-branch`
- First-run hardware detection and llama.cpp auto-build

### v3.0.x

- Initial production release
- Docker-based multi-agent architecture
- OpenClaw gateway + Hermes brain MCP protocol
- 28 tests (validation/unit/integration/e2e/security)

---

*This encyclopedia documents every function, flag, configuration option, and operational detail of the Hemlock Enterprise Agent Framework. For live help, run `./runtime.sh --help` or `./scripts/system/hemlock-doctor.sh diagnose`.*

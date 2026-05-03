# Hemlock — Enterprise Agent Framework

> **Self-Maintaining · Self-Healing · Production-Ready**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-27.x-2496ED?logo=docker)](https://www.docker.com/)
[![Python 3.11](https://img.shields.io/badge/Python-3.11-blue.svg)](https://www.python.org/)
[![Tests](https://img.shields.io/badge/Tests-28%20passing-brightgreen.svg)](#testing)
[![Skills](https://img.shields.io/badge/Skills-216%2B-purple.svg)](#skills-library)

**Hemlock** is an enterprise-grade framework for deploying, orchestrating, and managing **OpenClaw/Hermes** agents in isolated Docker containers. It provides a complete, self-contained system for individual agents and multi-agent crew collaboration with zero manual maintenance.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Directory Structure](#directory-structure)
4. [Quick Start](#quick-start)
5. [Agent Management](#agent-management)
6. [Crew Management](#crew-management)
7. [Docker Operations](#docker-operations)
8. [Configuration Reference](#configuration-reference)
9. [Security Model](#security-model)
10. [Skills Library](#skills-library)
11. [Plugin System](#plugin-system)
12. [Testing](#testing)
13. [Self-Healing & Monitoring](#self-healing--monitoring)
14. [Tooling Reference](#tooling-reference)
15. [Changelog](#changelog)
16. [License](#license)

---

## Overview

Hemlock wraps OpenClaw's agent runtime with a full operational layer:

| Capability | Description |
|---|---|
| Agent Lifecycle | Create, import, export, delete, and monitor agents |
| Crew Orchestration | Multi-agent collaboration via shared crew channels |
| Docker Integration | Build, run, export, and import agents as container images |
| Memory Injection | SOUL, USER, IDENTITY, MEMORY, AGENTS context injection |
| Self-Healing | Auto-fix permissions, missing directories, stub configs |
| Backup & Restore | Interactive backup with compression and encryption |
| 216+ Skills | Validated skill library for agent capabilities |
| Test Suite | 28 test files across unit, integration, e2e, and validation |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Hemlock Enterprise Framework                       │
│                                                                           │
│  ┌───────────────────┐        ┌──────────────────────────────────────┐   │
│  │   runtime.sh      │        │         openclaw-gateway             │   │
│  │   (CLI / Dispatch)│        │    WebSocket hub · Port 18789        │   │
│  │                   │        └──────────────┬───────────────────────┘   │
│  │  agent-create     │                       │  WS connections            │
│  │  agent-delete     │        ┌──────────────▼───────────────────────┐   │
│  │  agent-import     │        │            agents_net                │   │
│  │  agent-export     │        │     (bridge, ICC disabled)           │   │
│  │  crew-create      │        └──┬──────────────────────┬────────────┘   │
│  │  inject-memory    │           │                      │                │
│  │  backup / restore │    ┌──────▼──────┐        ┌──────▼──────┐        │
│  └───────────────────┘    │  oc-agent-1 │  ...   │ oc-agent-N  │        │
│                            │  read_only  │        │  read_only  │        │
│  ┌───────────────────┐    │  cap_drop   │        │  cap_drop   │        │
│  │  lib/common.sh    │    │  tmpfs /tmp │        │  tmpfs /tmp │        │
│  │  (shared utils)   │    └─────────────┘        └─────────────┘        │
│  │                   │                                                    │
│  │  logging          │    ┌──────────────────────────────────────────┐   │
│  │  retry/fallback   │    │        hemlock-framework                 │   │
│  │  self-healing     │    │  Management container · runtime.sh CLI   │   │
│  │  env detection    │    └──────────────────────────────────────────┘   │
│  └───────────────────┘                                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Summary

| Component | File | Purpose |
|---|---|---|
| CLI Orchestrator | `runtime.sh` | Master dispatch for all operations |
| Container Entry | `entrypoint.sh` | Connects Hermes to Gateway, starts agent |
| Common Library | `lib/common.sh` | Logging, retry, self-healing, env detection |
| Framework Image | `Dockerfile` | Base image for framework container |
| Agent Image | `Dockerfile.agent` | Per-agent container image |
| Crew Image | `Dockerfile.crew` | Portable crew export image |
| Export Image | `Dockerfile.export` | Standalone agent export image |
| Orchestration | `docker-compose.yml` | Multi-service bring-up |
| Make Targets | `Makefile` | Shorthand for all Docker operations |
| Runtime Config | `config/runtime.yaml` | Gateway, agent, security defaults |
| Gateway Config | `config/gateway.yaml` | Gateway connection settings |

---

## Directory Structure

```
hemlock/
│
├── runtime.sh                  # Master CLI — all operations start here
├── entrypoint.sh               # Docker container entrypoint (Hermes startup)
├── Makefile                    # Docker build/deploy shorthand
├── docker-compose.yml          # Multi-service orchestration
├── Dockerfile                  # Framework base image (multi-stage)
├── Dockerfile.agent            # Individual agent image
├── Dockerfile.crew             # Crew export image
├── Dockerfile.export           # Standalone agent export image
├── docker-config.yaml          # Docker registry/image configuration
├── .env.template               # Environment variable template (copy to .env)
├── .dockerignore               # Build context exclusions
├── .gitignore                  # Git exclusions (models, secrets, archives)
│
├── config/                     # Runtime configuration
│   ├── runtime.yaml            # Global runtime settings (gateway, security, logging)
│   └── gateway.yaml            # Gateway connection configuration
│
├── lib/                        # Shared shell libraries
│   └── common.sh               # Logging, retry, self-healing, env detection
│
├── scripts/                    # All operational scripts
│   ├── agent-create.sh         # Create agent (SOUL.md, config.yaml, .secrets/, .env.enc)
│   ├── agent-delete.sh         # Delete agent with safety checks and --force flag
│   ├── agent-export.sh         # Export agent directory (preserves hidden files)
│   ├── agent-import.sh         # Import agent directory (preserves hidden files)
│   ├── agent-control.sh        # Start/stop/restart individual agents
│   ├── agent-run.sh            # Run agent in foreground
│   ├── agent-stop.sh           # Stop a running agent
│   ├── agent-restart.sh        # Restart an agent
│   ├── agent-monitor.sh        # Monitor agent health and status
│   ├── agent-logs.sh           # Tail agent logs
│   ├── crew-create.sh          # Create crew (crew.yaml, SOUL.md, channel)
│   ├── crew-start.sh           # Start crew and all member agents
│   ├── crew-stop.sh            # Stop crew and all member agents
│   ├── crew-monitor.sh         # Monitor crew health
│   ├── crew-list.sh            # List all crews and their agents
│   ├── crew-blueprint.sh       # Generate crew blueprints
│   ├── crew-dissolve.sh        # Dissolve a crew (remove channel + config)
│   ├── crew-export.sh          # Export crew as portable archive
│   ├── crew-import.sh          # Import crew from archive
│   ├── crew-join.sh            # Add agent to existing crew
│   ├── crew-leave.sh           # Remove agent from crew
│   ├── backup.sh               # Non-interactive backup
│   ├── backup-interactive.sh   # Interactive backup with options
│   ├── restore.sh              # Restore from backup
│   ├── tool-inject-memory.sh   # Inject SOUL/USER/IDENTITY/MEMORY/AGENTS contexts
│   ├── autonomy.sh             # Autonomous operation mode
│   ├── memory.sh               # Memory management utilities
│   ├── migrate-agent.sh        # Migrate agent to new format/version
│   ├── skills-install.sh       # Install/update skill library
│   ├── validate-all-skills.sh  # Validate entire skills library
│   ├── validate.sh             # General framework validation
│   ├── runtime-validate.sh     # Validate runtime configuration
│   ├── runtime-doctor.sh       # Diagnose and fix runtime issues
│   ├── health-check.sh         # System-wide health check
│   ├── clean.sh                # Remove stale agents, logs, temp files
│   ├── enforce.sh              # Enforce compliance rules
│   ├── security-check.sh       # Security audit
│   ├── security-harden.sh      # Apply security hardening
│   ├── setup.sh                # Initial setup (legacy)
│   ├── fix-lfs-push.sh         # Fix GitHub LFS push authentication
│   ├── create_crew.py          # Python crew creation utility
│   ├── docker/                 # Docker-specific operations
│   │   ├── build-images.sh     # Build all framework Docker images
│   │   ├── export-agent.sh     # Export agent as Docker image
│   │   ├── export-crew.sh      # Export crew as Docker image
│   │   ├── import-agent.sh     # Import agent from Docker image
│   │   ├── import-crew.sh      # Import crew from Docker image
│   │   ├── backup-docker.sh    # Backup Docker volumes
│   │   ├── restore-docker.sh   # Restore Docker volumes
│   │   ├── docker-compose.yml  # Alternate compose reference
│   │   └── entrypoint.sh       # Docker entrypoint variant
│   ├── system/                 # System initialization
│   │   ├── first-run.sh        # First-time setup (Qwen3 + llama.cpp)
│   │   ├── hardware-scanner.sh # Detect hardware capabilities
│   │   ├── hemlock-doctor.sh   # Full system diagnostic
│   │   ├── llama-build.sh      # Build llama.cpp from source
│   │   ├── model-manager.sh    # Manage local model files
│   │   └── security-scanner.sh # Security vulnerability scan
│   ├── self-healing/
│   │   └── health_check.sh     # Self-healing health monitor
│   ├── py/                     # Python utilities
│   │   └── crew_blueprint.py   # Crew blueprint generator
│   └── config/
│       └── backup-config.yaml  # Backup configuration defaults
│
├── agents/                     # Agent workspaces (one dir per agent)
│   ├── README.md               # Agent directory guide
│   └── {agent-id}/
│       ├── config.yaml         # Agent model, memory, tool configuration
│       ├── data/               # Memory and identity files
│       │   ├── SOUL.md         # Core identity and purpose
│       │   ├── AGENTS.md       # Multi-agent coordination rules
│       │   ├── USER.md         # User context (optional)
│       │   ├── IDENTITY.md     # Identity definition (optional)
│       │   └── MEMORY.md       # Persistent memory (optional)
│       ├── config/             # Additional config overrides
│       ├── skills/             # Agent-specific skill overrides
│       ├── tools/              # Injected tool contexts
│       │   └── memory-context.md  # Injected at runtime
│       ├── logs/               # Agent-specific logs
│       ├── .secrets/           # Encrypted secrets (not in git)
│       ├── .hermes/            # Hermes runtime state (not in git)
│       ├── .archive/           # Archived memory snapshots (not in git)
│       ├── .backups/           # Local agent backups (not in git)
│       └── .env.enc            # Encrypted environment variables
│
├── crews/                      # Crew definitions
│   └── {crew-name}/
│       ├── crew.json           # Crew configuration (agents, channel, settings)
│       ├── SOUL.md             # Crew collective identity
│       ├── workflows/          # Workflow definitions (JSON)
│       ├── rules/              # Compliance and behavior rules
│       └── blueprints/         # Agent blueprint overrides for this crew
│
├── plugins/                    # Plugin system
│   ├── backup-protocol/        # Automated backup plugin
│   │   ├── backup.sh           # Backup protocol implementation
│   │   └── README.md
│   ├── crews/
│   │   ├── project-manager/    # Project manager crew templates
│   │   │   ├── SOUL.md         # Project manager crew identity
│   │   │   └── templates/      # Checklist and review templates
│   │   └── rules/              # Global crew rules
│   ├── scripts/                # Plugin utility scripts
│   │   ├── enforce.sh          # Rule enforcement
│   │   ├── memory-log.sh       # Memory logging
│   │   ├── memory-promote.sh   # Memory promotion
│   │   ├── secret.sh           # Secret management
│   │   └── TOOLS-GUIDE.md      # Plugin tools guide
│   └── tool-enforcement/       # Tool enforcement plugin (Python)
│       ├── __init__.py
│       └── plugin.yaml
│
├── skills/                     # Agent skill library
│   ├── skills/                 # 216+ individual skills (each with SKILL.md)
│   │   ├── docker-management/  # Docker operations skill
│   │   ├── autonomous-crew/    # Multi-agent crew skill
│   │   ├── hermes-agent/       # Hermes agent skill
│   │   ├── mlops/              # ML operations skills
│   │   ├── github/             # GitHub integration
│   │   ├── memory-tiering/     # Memory management
│   │   └── ...                 # 200+ more skills
│   └── LTC/                    # Long-term context skill management
│       ├── SKILL.md
│       ├── SKILL_SPECIFICATION.md
│       └── SKILLS_ANALYSIS_REPORT.md
│
├── tools/                      # Agent toolkit
│   └── agent-toolkit/
│       ├── agent-bootstrap.sh  # Agent bootstrap utility
│       ├── agent_brain_mcp.py  # MCP brain integration
│       ├── skill_scanner.py    # Skill discovery and validation
│       ├── skill-scanner.sh    # Shell skill scanner
│       ├── logger.py           # Structured logger
│       ├── jsonfmt.py          # JSON formatter
│       ├── switch-model.sh     # Switch active model
│       ├── update-mcp-brains.py # Update MCP configurations
│       ├── autonomy-protocol.md # Autonomy rules
│       ├── SKILL-SCANNER.md    # Skill scanner guide
│       └── README.md
│
├── tests/                      # Full test suite (28 test files)
│   ├── run_all.sh              # Master test runner
│   ├── run-all-tests.sh        # Alternative runner
│   ├── test-helpers.sh         # Shared test utilities
│   ├── README.md               # Testing guide
│   │
│   ├── unit/                   # Unit tests (fast, no external deps)
│   │   ├── test_agent-create.sh
│   │   ├── test_agent-import-export.sh
│   │   ├── test_backup-restore.sh
│   │   ├── test_common_lib.sh
│   │   ├── test_crew-create.sh
│   │   ├── test_crew-lifecycle.sh
│   │   ├── test_delete_agent.sh
│   │   ├── test_first_run.sh
│   │   ├── test_hemlock_doctor.sh
│   │   ├── test_model_manager.sh
│   │   ├── test_runtime_commands.sh
│   │   ├── test_runtime.sh
│   │   ├── test_security_scanner.sh
│   │   ├── test_system_scripts.sh
│   │   ├── test-hardware-scanner.sh
│   │   ├── test-helpers.sh
│   │   ├── test-llama-build.sh
│   │   └── test_agent_management.sh
│   │
│   ├── integration/            # Integration tests
│   │   ├── test_agent-lifecycle.sh
│   │   ├── test_backup_system.sh
│   │   ├── test_config_validation.sh
│   │   ├── test_consistency-checks.sh
│   │   ├── test_crew-lifecycle.sh
│   │   ├── test_docker-management.sh
│   │   ├── test_framework-baseline.sh
│   │   ├── test_hidden-files.sh
│   │   ├── test_script_interactions.sh
│   │   ├── test_system_integration.sh
│   │   └── test-helpers.sh
│   │
│   ├── e2e/                    # End-to-end workflow tests
│   │   ├── test_agent.sh
│   │   ├── test_complete_workflow.sh
│   │   ├── test_hidden_files.sh
│   │   ├── test_memory_injection.sh
│   │   ├── test_self_healing.sh
│   │   └── run_tests.sh
│   │
│   ├── validation/             # Structure and permission validators
│   │   ├── validate_permissions.sh
│   │   ├── validate_skills.sh
│   │   └── validate_structure.sh
│   │
│   └── security/
│       └── test_permissions.sh
│
├── docs/                       # Documentation and references
│   ├── README.md               # Docs index
│   ├── blueprints/             # Crew and agent blueprints
│   ├── checkpoints/            # Checkpoint snapshots
│   ├── knowledge-base/         # Framework knowledge base (JSON)
│   └── references/             # External references and links
│
├── logs/                       # Runtime logs (not in git)
│   ├── runtime.log             # Main runtime log
│   └── {agent-id}.log          # Per-agent logs
│
├── models/                     # Local model storage (not in git)
│   └── gguf/                   # GGUF quantized models
│
└── backups/                    # Local backup archives (not in git)
```

---

## Quick Start

### Prerequisites

| Requirement | Minimum Version |
|---|---|
| Docker | 20.10+ |
| Docker Compose | 2.0+ (plugin) or `docker-compose` 1.29+ |
| Python | 3.11+ (for framework tools) |
| Bash | 4.0+ |

### 1. Configure Environment

```bash
cp .env.template .env
# Edit .env — set OPENCLAW_GATEWAY_TOKEN to a secure value
nano .env
```

### 2. Build the Framework Image

```bash
make build-framework
# OR directly:
docker build --target framework -t hemlock/framework:1.0.0 -f Dockerfile .
```

### 3. Start All Services

```bash
make up
# Starts: openclaw-gateway, hemlock-framework, test-e2e-agent, crew-agent-1
```

### 4. Verify Everything Is Running

```bash
make ps           # List running containers
make logs         # Tail all service logs
./tests/run_all.sh  # Run full test suite
```

### 5. Create Your First Agent

```bash
./scripts/agent-create.sh --id my-agent --model nous/mistral-large --name "My Agent"
make build-agent my-agent
```

### 6. Shut Down

```bash
make down
```

---

## Agent Management

### Agent Lifecycle

| Stage | Command | Description |
|---|---|---|
| Create | `./scripts/agent-create.sh --id <id> --model <model>` | Scaffold agent directory |
| Build | `make build-agent <id>` | Build Docker image |
| Run | `make up` | Start via docker-compose |
| Import | `./scripts/agent-import.sh --source <path> --target <id>` | Import from directory/archive |
| Export | `./scripts/agent-export.sh --id <id> --dest <path>` | Export to directory/archive |
| Monitor | `./scripts/agent-monitor.sh --id <id>` | Live health and status |
| Logs | `./scripts/agent-logs.sh --id <id>` | Tail agent logs |
| Delete | `./runtime.sh delete-agent <id> [--force]` | Fully remove agent |

### Creating an Agent

```bash
# Create with model and optional name
./scripts/agent-create.sh --id my-agent --model nous/mistral-large --name "Research Agent"

# This creates:
#   agents/my-agent/
#   ├── config.yaml         (model, memory, tool config)
#   ├── SOUL.md             (identity at repo root for injection)
#   ├── data/SOUL.md        (identity in agent data dir)
#   ├── data/AGENTS.md      (multi-agent coordination rules)
#   ├── .secrets/           (encrypted secrets dir)
#   └── .env.enc            (encrypted env vars)
```

### Agent Configuration (`config.yaml`)

```yaml
agent:
  id: my-agent
  name: My Research Agent
  model: nous/mistral-large
  personality: default
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
```

### Memory Contexts

Each agent supports five memory contexts injected into `tools/memory-context.md`:

| File | Purpose |
|---|---|
| `data/SOUL.md` | Core identity, purpose, and values |
| `data/USER.md` | User-specific context and preferences |
| `data/IDENTITY.md` | Identity definition and persona |
| `data/MEMORY.md` | Persistent cross-session memory |
| `data/AGENTS.md` | Multi-agent coordination rules |

Inject memory for a specific agent:
```bash
./runtime.sh inject-memory my-agent
# OR inject for all agents:
./runtime.sh inject-all-memory
```

### Hidden Files

All agent import/export/delete operations fully preserve hidden files:

| Directory | Purpose |
|---|---|
| `.secrets/` | Encrypted API keys and credentials |
| `.hermes/` | Hermes runtime state and cache |
| `.archive/` | Archived memory snapshots |
| `.backups/` | Local agent backup copies |
| `.env.enc` | Encrypted environment variables |

### Importing an Agent

```bash
# Import from a local directory (hidden files preserved with cp -ra)
./scripts/agent-import.sh --source /path/to/agent --target my-agent

# Import from Docker image
./scripts/docker/import-agent.sh my-agent:latest
```

### Exporting an Agent

```bash
# Export to directory
./scripts/agent-export.sh --id my-agent --dest /path/to/export

# Export as Docker image
make export-agent my-agent
# Creates: openclaw/agent-my-agent:1.0.0 and :latest

# Push to registry
docker push openclaw/agent-my-agent:latest
```

### Deleting an Agent

```bash
# Interactive (prompts for confirmation)
./runtime.sh delete-agent my-agent

# Non-interactive (for automation/GUI)
./runtime.sh delete-agent my-agent --force

# What gets removed:
#   agents/my-agent/          (entire directory, including hidden files)
#   logs/my-agent*.log        (all agent logs)
#   docker-compose.yml entry  (service reference)
```

---

## Crew Management

A **crew** is a named group of agents collaborating over a shared WebSocket channel via the OpenClaw Gateway.

### Create a Crew

```bash
./scripts/crew-create.sh my-crew agent1 agent2 agent3 \
  --duration 86400 \
  --owner myuser \
  --private

# Creates:
#   crews/my-crew/
#   ├── crew.json       (agents, channel, settings)
#   └── SOUL.md         (crew collective identity)
```

### Crew Operations

| Operation | Command |
|---|---|
| Create | `./scripts/crew-create.sh <name> [agents...]` |
| Start | `./scripts/crew-start.sh <name>` |
| Stop | `./scripts/crew-stop.sh <name>` |
| Monitor | `./scripts/crew-monitor.sh <name>` |
| List | `./runtime.sh list-crews` |
| Activate | `./runtime.sh activate-crew <name>` |
| Deactivate | `./runtime.sh deactivate-crew <name>` |
| Export | `make export-crew <name>` |
| Dissolve | `./scripts/crew-dissolve.sh <name>` |

### Build a Crew Image

```bash
make build-crew my-crew
# OR:
docker build -t crew-my-crew:1.0.0 -f Dockerfile.crew \
  --build-arg CREW_ID=my-crew .
```

### Run a Crew Container

```bash
docker run -d \
  --name my-crew \
  -e OPENCLAW_GATEWAY_URL=ws://gateway:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=your_token \
  -e CREW_CHANNEL=crew-my-crew \
  crew-my-crew:1.0.0
```

---

## Docker Operations

### Makefile Reference

#### Build

```bash
make build                    # Build all images (via docker compose)
make build-framework          # Build hemlock/framework:1.0.0
make build-agents             # Build all per-agent images
make build-agent <AGENT_ID>   # Build image for specific agent
make build-crew <CREW>        # Build crew export image
```

#### Deploy

```bash
make up                       # Start all services (detached)
make up-logs                  # Start all services (attached, show logs)
make down                     # Stop and remove containers
make restart                  # Restart all services
make clean                    # Remove containers, networks, volumes
make clean-all                # docker system prune -f
```

#### Monitoring

```bash
make logs                     # Tail all service logs
make logs-service <SERVICE>   # Tail one service's logs
make ps                       # List running containers + health
make images                   # List all hemlock/openclaw images
make shell-service <SERVICE>  # Open shell in a running container
make test                     # Run health checks on all containers
```

#### Export / Import

```bash
make export                   # Export all agents as Docker images
make export-agent <AGENT_ID>  # Export one agent image
make export-crews             # Export all crews
make export-crew <CREW>       # Export one crew image
make import <IMAGE>           # Import agent from Docker image
make import-crew <IMAGE>      # Import crew from Docker image
```

#### Registry

```bash
make push                     # Build and push all images to registry
make push-crew <IMAGE>        # Push a crew image
make pull                     # Pull all images from registry
```

### Build Images Directly

```bash
# Framework (multi-stage, --target framework)
docker build --target framework \
  -t hemlock/framework:1.0.0 \
  -t hemlock/framework:latest \
  -f Dockerfile .

# Agent image
docker build \
  --build-arg AGENT_ID=my-agent \
  --build-arg MODEL=nous/mistral-large \
  -t hemlock/agent-my-agent:1.0.0 \
  -f Dockerfile.agent .

# Crew export image
docker build \
  --build-arg CREW_ID=my-crew \
  -t crew-my-crew:1.0.0 \
  -f Dockerfile.crew .

# Standalone agent export (bundles data + tools into image)
docker build \
  --build-arg AGENT_ID=my-agent \
  -t hemlock/export-my-agent:1.0.0 \
  -f Dockerfile.export .
```

### Adding an Agent to docker-compose.yml

Copy the template block at the bottom of `docker-compose.yml` and replace `AGENT_ID`:

```yaml
  oc-my-agent:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: my-agent
        MODEL: nous/mistral-large
    image: hemlock/agent-my-agent:1.0.0
    container_name: oc-my-agent
    environment:
      - AGENT_ID=my-agent
      - MODEL=nous/mistral-large
      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - ./agents/my-agent/data:/app/data
      - ./agents/my-agent/config:/app/config
    networks:
      - agents_net
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:size=64m
    depends_on:
      - openclaw-gateway
    restart: unless-stopped
```

---

## Configuration Reference

### Environment Variables (`.env`)

| Variable | Required | Default | Description |
|---|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | Yes | — | Shared authentication token for all agents |
| `OPENCLAW_GATEWAY_BIND` | No | `lan` | Gateway bind mode |
| `OPENCLAW_GATEWAY_PORT` | No | `18789` | Gateway WebSocket port |
| `DEFAULT_AGENT_MODEL` | No | `nous/mistral-large` | Default model for new agents |
| `FRAMEWORK_VERSION` | No | `1.0.0` | Image tag for builds |
| `REGISTRY` | No | `docker.io/openclaw` | Docker registry for push/pull |
| `GITHUB_TOKEN` | No | — | GitHub PAT for git push operations |

### `config/runtime.yaml`

```yaml
runtime:
  gateway:
    port: 18789
    token: "change_this_to_a_secure_token"
    bind: "lan"
  agents:
    default_model: "nous/mistral-large"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
    tmpfs: true
    tmpfs_size: "64m"
  logging:
    level: "info"
    max_size: "10m"
    max_files: 5
```

### `config/gateway.yaml`

```yaml
gateway:
  url: ws://openclaw-gateway:18789
  token: ${OPENCLAW_GATEWAY_TOKEN}
  bind: lan
  port: 18789
  timeout: 30
```

### Agent `config.yaml`

```yaml
agent:
  id: my-agent
  name: My Agent
  model: nous/mistral-large
  personality: default
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
```

### Crew `crew.json`

```json
{
  "crew_id": "uuid-here",
  "name": "my-crew",
  "channel": "crew-my-crew",
  "agents": ["agent1", "agent2"],
  "template": "project-manager",
  "settings": {
    "duration": 86400,
    "private": true
  }
}
```

---

## Security Model

### Container Hardening (All Agent Services)

| Setting | Value | Effect |
|---|---|---|
| `read_only: true` | On | Container filesystem is read-only |
| `cap_drop: ALL` | On | All Linux capabilities dropped |
| `tmpfs /tmp` | 64 MB | In-memory temp (no disk writes) |
| Network ICC | Disabled | Containers cannot talk to each other directly |
| Gateway auth | Token | Every agent must present valid token |

### Network Isolation

```yaml
networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
```

All agents communicate **only through the openclaw-gateway**, never peer-to-peer.

### Secrets Management

- Gateway token in `.env` — never committed to git
- Agent secrets in `agents/{id}/.secrets/` — listed in `.gitignore`
- Encrypted env vars in `agents/{id}/.env.enc` — listed in `.gitignore`
- No hardcoded credentials in any Dockerfile or config

### Files Never Committed to Git

```
.env
agents/*/.secrets/
agents/*/.hermes/
agents/*/.archive/
agents/*/.backups/
agents/*/.env.enc
logs/
scripts/models/
models/
*.safetensors
*.gguf
*.bin
*.tar.gz
```

---

## Skills Library

The framework ships with **216+ validated skills** in `skills/skills/`, organized by category:

| Category | Skills |
|---|---|
| AI/ML | `llama-cpp`, `vllm`, `axolotl`, `unsloth`, `trl-fine-tuning`, `flash-attention`, `gguf` |
| Autonomous Agents | `autonomous-crew`, `hermes-agent`, `autonomy-protocol`, `claude-code`, `codex` |
| Coding | `coding-agent`, `github`, `github-pr-workflow`, `debug-tracer`, `systematic-debugging` |
| Data Science | `data-science`, `faiss`, `chroma`, `qdrant`, `pinecone`, `weights-and-biases` |
| DevOps | `docker-management`, `devops`, `mlops`, `modal`, `lambda-labs` |
| Research | `arxiv`, `research-paper-writing`, `llm-wiki`, `blogwatcher` |
| Productivity | `notion`, `linear`, `google-workspace`, `powerpoint`, `nano-pdf` |
| Security | `red-teaming`, `security`, `sherlock`, `oss-forensics` |
| Blockchain | `blockchain`, `solana`, `base`, `farcaster-agent` |
| Creative | `creative-ideation`, `excalidraw`, `manim-video`, `p5js`, `ascii-art` |
| Memory | `memory-tiering`, `agent-memory`, `index-cache`, `honcho` |
| Communication | `email`, `telephony`, `imessage`, `himalaya` |
| Media | `youtube-content`, `gif-search`, `songsee`, `whisper` |

Each skill lives in its own directory with a `SKILL.md` describing usage, configuration, and examples.

### Validate Skills

```bash
./scripts/validate-all-skills.sh
# OR:
./tests/validation/validate_skills.sh
```

---

## Plugin System

Plugins extend the framework with additional automation. They live in `plugins/` and are automatically available.

| Plugin | Type | Purpose |
|---|---|---|
| `backup-protocol` | Shell | Automated backup scheduling and execution |
| `crews/project-manager` | Templates | Project manager crew with templates and checklists |
| `tool-enforcement` | Python | Enforce agent tool usage policies |
| `scripts/*` | Shell | Memory logging, secret management, rule enforcement |

### List Plugins

```bash
./runtime.sh list-plugins
```

---

## Testing

The framework has **28 test files** covering all major subsystems. All tests pass with 0 failures (1 skip: Docker consistency test when Docker is unavailable in CI).

### Run All Tests

```bash
./tests/run_all.sh

# By category:
./tests/run_all.sh validation   # Structure, permissions, skills (fastest)
./tests/run_all.sh unit         # Unit tests (no external deps)
./tests/run_all.sh integration  # Integration tests (Docker optional)
./tests/run_all.sh e2e          # End-to-end workflow tests
```

### Test Coverage

| Category | Files | What's Covered |
|---|---|---|
| Unit | 14 | Agent create/delete/import/export, crew create/lifecycle, runtime commands, backup/restore, common lib, hardware scanner, security scanner, model manager, first-run |
| Integration | 10 | Agent lifecycle, backup system, config validation, consistency checks, crew lifecycle, Docker management, framework baseline, hidden files, script interactions, system integration |
| E2E | 6 | Full agent workflow, hidden files, memory injection, self-healing, agent operations |
| Validation | 3 | Structure, permissions, skills library |
| Security | 1 | File permissions |

### Individual Test Examples

```bash
# Unit: Agent creation with auto-shortened IDs
./tests/unit/test_agent-create.sh

# Unit: Delete agent (--force flag, cleanup verification)
./tests/unit/test_delete_agent.sh

# Integration: Full agent import → run → export → delete lifecycle
./tests/integration/test_agent-lifecycle.sh

# Integration: Crew create → start → monitor → stop lifecycle
./tests/integration/test_crew-lifecycle.sh

# Integration: Docker management (dry-run when Docker unavailable)
./tests/integration/test_docker-management.sh

# E2E: Hidden files preserved across all operations
./tests/e2e/test_hidden_files.sh
```

### Agent/Crew ID Constraints

| Entity | Max Length | Pattern | Example |
|---|---|---|---|
| Agent ID | 16 chars | `^[a-z][a-z0-9-]{0,15}$` | `utc-$(date +%s \| tail -c 5)` |
| Crew name | 3–21 chars | `^[a-z][a-z0-9-]{2,20}$` | `crew-$(date +%s \| tail -c 5)` |

---

## Self-Healing & Monitoring

### Auto-Healing Capabilities (`lib/common.sh`)

| Issue | Auto-Fix |
|---|---|
| Permission `700` on files | Reset to `755` |
| Missing required directory | `mkdir -p` with fallback |
| Failed command | Retry with exponential backoff (up to 3 attempts) |
| Fallback functions | Automatic failover to alternative implementation |

### Health Checks

```bash
# Full system diagnostic
./scripts/system/hemlock-doctor.sh

# Runtime validation
./scripts/runtime-doctor.sh

# Security audit
./scripts/security-check.sh

# Hardware scan (for local model recommendations)
./scripts/system/hardware-scanner.sh
```

### Framework Self-Update

The framework includes an auto-update script (`.auto-update.sh`) that checks and applies updates every 24 hours when enabled.

---

## Tooling Reference

### `runtime.sh` — Master CLI

```
Usage: ./runtime.sh <command> [options]

Agent Management:
  create-agents               Create agents from plugin templates
  delete-agent <id>           Delete agent (--force skips confirmation)
  finalize-agents             Update and finalize existing agents
  list-agents                 List all agents with status

Crew Management:
  create-crew <name>          Create a new crew
  activate-crew <name>        Validate and show activation instructions
  deactivate-crew <name>      Deactivate a crew
  list-crews                  List all crews

Backup Management:
  backup                      Interactive backup
  restore                     Restore from backup
  backup-status               Show backup status
  backup-init                 Initialize backup configuration
  backup-validate             Validate backup integrity
  validate-modules            Check module download capability

Tool Injection:
  inject-memory <agent>       Inject memory contexts for one agent
  inject-all-memory           Inject memory for all agents

System:
  setup                       Basic setup (legacy)
  initialize                  First-time initialization (Qwen3 + llama.cpp)
  update                      Update all agents and crews
  status                      System status overview
  self-check                  Run full system diagnostics

Plugin Management:
  list-plugins                List all plugins
  enable-plugin <name>        Enable a plugin
  disable-plugin <name>       Disable a plugin

Docker (via runtime.sh → scripts/docker/):
  build-framework             Build framework Docker image
  build-agent <id>            Build agent Docker image
  build-crew <name>           Build crew Docker image
  export-agent <id>           Export agent as Docker image
  import-agent <image>        Import agent from Docker image
  up                          Start all Docker services
  down                        Stop all Docker services
  logs [service]              Show Docker service logs
  ps                          List running containers

Options:
  --help, -h                  Show help
  --quiet, -q                 Suppress output
  --verbose, -v               Verbose output
  --dry-run                   Test without making changes
  --force, -f                 Force operation (skip prompts)
  --skip-init                 Skip first-run initialization
```

### Key Script Reference

| Script | Usage | Description |
|---|---|---|
| `scripts/agent-create.sh` | `--id <id> --model <model> [--name <name>]` | Create agent workspace |
| `scripts/agent-delete.sh` | `--id <id> [--force]` | Delete agent completely |
| `scripts/agent-import.sh` | `--source <path> --target <id>` | Import agent (hidden files preserved) |
| `scripts/agent-export.sh` | `--id <id> --dest <path>` | Export agent (hidden files preserved) |
| `scripts/crew-create.sh` | `<name> [agents...] [--private]` | Create crew |
| `scripts/crew-start.sh` | `<name>` | Start crew |
| `scripts/crew-stop.sh` | `<name>` | Stop crew |
| `scripts/tool-inject-memory.sh` | `<agent-id>` or `--all` | Inject memory contexts |
| `scripts/backup-interactive.sh` | `[--full] [--compress] [--encrypt]` | Interactive backup |
| `scripts/docker/build-images.sh` | `[framework\|agent\|agents\|push\|list]` | Build Docker images |
| `scripts/system/hemlock-doctor.sh` | — | Full system diagnostic |
| `scripts/runtime-doctor.sh` | — | Runtime health check |

---

## Changelog

### v1.0.0 — Current (May 2026)

#### Core Framework
- Full agent lifecycle: create, import, export, delete with hidden file support
- `agent-delete.sh` — safety checks, crew membership check, `--force` flag
- `agent-import.sh` / `agent-export.sh` — `cp -ra "$SOURCE/."` pattern preserves `.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env.enc`
- `crew-stop.sh` — new script for stopping crews and all member agents
- `runtime.sh` — `delete-agent`, `crew-start`, `crew-stop`, `crew-monitor` routing; Docker dry-run stubs

#### Docker
- `docker-compose.yml` — rebuilt with real agent IDs, template block for new agents, correct service names
- `Dockerfile` — multi-stage build (`base` → `builder` → `framework`), directory-based `COPY`
- `.dockerignore` — exceptions for `docker-compose.yml`, `Dockerfile`, `lib/`, `scripts/` so build context is complete

#### Testing
- 28 test files, all passing (1 skip: Docker consistency in non-Docker env)
- Agent IDs auto-shortened: `pfx-$(date +%s | tail -c 5)` (≤ 9 chars, within 16-char limit)
- Crew IDs: `cname-$(date +%s | tail -c 5)` (within 3–21 char limit)
- Integration tests use `mktemp` for export dirs, Docker import fallback via `cp -ra`
- Crew lifecycle test creates crew dir directly as fallback when `crew-create.sh` skips

#### Git / Repository
- `.gitignore` — added `scripts/models/`, `models/`, `*.safetensors`, `*.gguf`, `*.bin`, `*.tar.gz`
- Removed 1.5 GB `model.safetensors` from git history via `filter-branch`
- `scripts/fix-lfs-push.sh` — push helper using `GITHUB_TOKEN` env var

---

## License

MIT License — see `LICENSE` file for details.

---

## Support

```bash
# Built-in help
./runtime.sh --help

# Full system diagnostic
./scripts/system/hemlock-doctor.sh

# Run full test suite
./tests/run_all.sh

# Check docs
ls docs/
```

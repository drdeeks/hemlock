# Hemlock - Enterprise Agent Framework

> **Self-Maintaining, Self-Healing, Production-Ready Agent Framework**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Docker Ready](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker)](https://www.docker.com/)
[![Python 3.11](https://img.shields.io/badge/Python-3.11-blue.svg)](https://www.python.org/)

**Hemlock** is an enterprise-grade framework for deploying and managing **OpenClaw** and **Hermes** agents in isolated Docker containers. It provides a complete, self-contained system for agent orchestration with **zero manual maintenance**.

---

## Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Agent Management](#-agent-management)
- [Crew Management](#-crew-management)
- [Docker Operations](#-docker-operations)
- [Configuration](#-configuration)
- [Security](#-security)
- [Troubleshooting](#-troubleshooting)
- [license](#-license)

---

## 🚀 Features

### Core Capabilities
- **Self-Healing**: Automatic recovery from errors and misconfigurations
- **Self-Updating**: auto-checks and applies updates every 24 hours
- **Zero Manual Updates**: Framework maintains itself automatically
- **Production-Ready**: Hardened security, read-only filesystems, capability dropping

### Docker-Centric Design
- **Isolated Containers**: Each agent runs in its own secure container
- **Multi-Architecture**: Works on x86_64, ARM64
- **Portable**: Export agents and crews as Docker images
- **Scalable**: Spawn unlimited agents on demand

### Agent Framework
- **289+ Validated Skills**: Full skill library with validation
- **Memory Injection**: SOUL, USER, IDENTITY, MEMORY, AGENTS contexts
- **Multi-Agent Orchestration**: Crew-based collaboration
- **Health Monitoring**: Built-in health checks for all services

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Hemlock Framework                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────┐     ┌─────────────────────────┐   │
│  │      Framework            │     │        Gateway           │   │
│  │  ┌─────────────────────┐ │     │    (openclaw/gateway)   │   │
│  │  │  Dockerfile         │ │     │    Port: 18789          │   │
│  │  │  entrypoint.sh      │ │     └─────────────────────────┘   │
│  │  │  runtime.sh        │ │              ▲                      │
│  │  │  lib/common.sh     │ │              │                      │
│  │  └─────────────────────┘ │              │ WS Connection       │
│  │  config/               │              │                      │
│  │  scripts/              │              ▼                      │
│  └─────────────────────────┘     ┌─────────────────────────┐   │
│                                        │      Agents         │   │
│                                        │  ┌─────────────────┐ │   │
│                                        │  │  oc-agent-1    │ │   │
│                                        │  │  oc-agent-2    │ │   │
│                                        │  │  ...           │ │   │
│                                        │  └─────────────────┘ │   │
│                                        └─────────────────────────┘   │
│                                                                   │
│  Network: agents_net (ICC disabled, bridge driver)                 │
│  Security: read_only=true, cap_drop=ALL, tmpfs=/tmp                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure
```
hemlock/
├── docker-compose.yml      # Main orchestration
├── Dockerfile              # Framework base image
├── Dockerfile.agent        # Individual agent image
├── Dockerfile.crew         # Crew export image
├── Dockerfile.export       # Agent export image
├── entrypoint.sh           # Container entrypoint
├── runtime.sh              # CLI orchestrator
│
├── config/
│   ├── runtime.yaml        # Runtime configuration
│   └── gateway.yaml        # Gateway settings
│
├── lib/
│   └── common.sh           # Shared utilities
│
├── scripts/                # Core scripts
│   ├── agent-create.sh     # Create new agents
│   ├── agent-delete.sh     # Delete agents
│   ├── agent-export.sh     # Export agents
│   ├── agent-import.sh     # Import agents
│   ├── crew-create.sh      # Create new crews
│   ├── backup-interactive.sh # Backup system
│   ├── tool-inject-memory.sh # Memory injection
│   ├── docker/            # Docker operations
│   └── ...
│
├── agents/                 # Agent workspaces
│   └── {agent-id}/
│       ├── config.yaml    # Agent configuration
│       └── data/          # Memory & identity files
│
├── crews/                  # Crew definitions
│   └── {crew-name}/
│       ├── crew.yaml      # Crew configuration
│       ├── workflows/     # Workflow definitions
│       └── rules/         # Compliance rules
│
├── plugins/               # Plugin system
├── skills/                # Skill library (289+)
├── tools/                 # Toolkit
└── tests/                 # Test suite
```

---

## ⚡ Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+
- Python 3.11+ (for framework image builds)

### 1. Configure Environment
```bash
cp .env.template .env
# Edit .env and set your OPENCLAW_GATEWAY_TOKEN
```

### 2. Build Framework
```bash
make build-framework
# OR: docker build -t hemlock-framework -f Dockerfile .
```

### 3. Start All Services
```bash
make up
# Starts: gateway + test-e2e-agent + crew-agent-1 + framework
```

### 4. Verify Deployment
```bash
make ps          # List running containers
make logs       # View all service logs
make test       # Run health checks
```

### 5. Stop Services
```bash
docker-compose down
```

---

## 🤖 Agent Management

### Create a New Agent
```bash
# With Docker integration
./scripts/agent-create.sh --id my-agent --model nous/mistral-large --name "My Agent"

# Without Docker (config only)
./scripts/agent-create.sh --id my-agent --model nous/mistral-large --name "My Agent"
# Then: make build-agent my-agent
```

### Agent Configuration
Each agent requires:
- `config.yaml` - Model, memory settings, tool configuration
- `SOUL.md` - Core identity and purpose
- `USER.md` - User context
- `IDENTITY.md` - Identity definition
- `MEMORY.md` - Persistent memory
- `AGENTS.md` - Multi-agent coordination rules

### Build Agent Image
```bash
# Single agent
docker build -t my-agent -f Dockerfile.agent \
  --build-arg AGENT_ID=my-agent \
  --build-arg MODEL=nous/mistral-large \
  .

# Or use Make
make build-agent my-agent
```

### Run Agent
```bash
# Via docker-compose (auto-managed)
make up

# Manual Docker run
docker run -d \
  --name my-agent \
  -e AGENT_ID=my-agent \
  -e MODEL=nous/mistral-large \
  -e OPENCLAW_GATEWAY_URL=ws://gateway:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=your_token \
  my-agent
```

### Export Agent as Docker Image
```bash
make export-agent my-agent
# Creates: my-agent:latest, my-agent:1.0.0

# Push to registry
docker push my-agent:latest
```

### Delete an Agent
```bash
# Delete with confirmation
./runtime.sh delete-agent my-agent

# Delete without confirmation (for GUI/automation)
./runtime.sh delete-agent my-agent --force

# Direct script usage
./scripts/agent-delete.sh --id my-agent --force
```

> **Note:** Deletion removes the agent directory, log files, and docker-compose references. Use with caution.

---

## 🗑️ Agent Lifecycle Management

Hemlock now supports complete agent lifecycle operations:

| Operation | Command | Description |
|-----------|---------|-------------|
| Create | `./runtime.sh create-agents` | Create agent from templates |
| Import | `./scripts/agent-import.sh --source <path> --target <id>` | Import agent (includes hidden files) |
| Export | `./scripts/agent-export.sh --id <id> --dest <path>` | Export agent (includes hidden files) |
| Delete | `./runtime.sh delete-agent <id> [--force]` | Delete agent |
| List | `./runtime.sh list-agents` | List all agents |

### Hidden Files Support
All agent operations now properly handle hidden files and directories (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, etc.).

---

## 👥 Crew Management

### Create a Crew
```bash
./scripts/crew-create.sh my-crew agent1 agent2 agent3 \
  --duration 86400 \
  --owner myuser \
  --private
```

This creates:
- `crews/my-crew/crew.yaml` - Crew configuration
- `crews/my-crew/SOUL.md` - Crew identity
- Auto-adds agents to crew channel

### Build Crew Image
```bash
make build-crew my-crew
# OR: docker build -t crew-my-crew -f Dockerfile.crew --build-arg CREW_ID=my-crew .
```

### Start Crew
```bash
# Via Make (recommended)
make up

# Manual
docker run -d \
  --name my-crew \
  -e CREW_CHANNEL=crew-my-crew \
  crew-my-crew:latest
```

### Export Crew
```bash
make export-crew my-crew
# Creates portable crew image with all agents and configurations
```

---

## 🐳 Docker Operations

### Makefile Commands
```bash
# Build
make build              # Build all images
make build-framework   # Build framework image
make build-agents      # Build all agent images
make build-agent AGENT_ID  # Build specific agent
make build-crew CREW   # Build crew image

# Deployment
make up                # Start all services (daemon)
make up-logs          # Start with logs attached
make down             # Stop all services
make restart          # Restart all services
make clean            # Remove containers, networks, volumes

# Export/Import
make export           # Export all agents
make export-agent AGENT_ID  # Export specific agent
make export-crews     # Export all crews
make export-crew CREW # Export specific crew
make import IMAGE     # Import from registry

# Registry
make push             # Push all images
make push-crew IMAGE  # Push crew image
make pull             # Pull all images

# Monitoring
make logs             # Show all logs
make logs-service NAME # Show service logs
make ps               # List containers
make images           # List images
```

### Docker Compose Commands
```bash
# Manage services
docker-compose up -d              # Start in background
docker-compose down                # Stop and remove
docker-compose build               # Rebuild images
docker-compose logs -f             # Follow logs

# Individual service
docker-compose logs -f openclaw-gateway
docker-compose exec framework sh    # Shell access
docker-compose restart test-e2e-agent
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | ✅ | - | Gateway authentication token |
| `DEFAULT_AGENT_MODEL` | ❌ | nous/mistral-large | Default model for new agents |
| `FRAMEWORK_VERSION` | ❌ | 1.0.0 | Framework version tag |
| `OPENCLAW_GATEWAY_BIND` | ❌ | lan | Gateway network binding |
| `OPENCLAW_GATEWAY_PORT` | ❌ | 18789 | Gateway port |

### Configuration Files

**`config/runtime.yaml`** - Framework runtime settings:
```yaml
runtime:
  agents_dir: /app/agents
  crews_dir: /app/crews
  plugins_dir: /app/plugins
  skills_dir: /app/skills
  log_level: INFO
```

**`config/gateway.yaml`** - Gateway configuration:
```yaml
gateway:
  url: ws://openclaw-gateway:18789
  token: ${OPENCLAW_GATEWAY_TOKEN}
  bind: lan
  port: 18789
  timeout: 30
```

---

## 🔒 Security

### Container Security (All Services)
- **Read-Only Filesystem**: `read_only: true` - No writes to container FS
- **Capability Dropping**: `cap_drop: ALL` - No elevated privileges
- **ICC Disabled**: Inter-container communication blocked
- **Isolated Network**: Custom bridge network with ICC disabled
- **tmpfs Mounts**: `/tmp` mounted in memory (64MB limit)
- **Health Checks**: All services have health monitoring

### Network Security
```yaml
networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
    internal: false
```

### Secrets Management
- Gateway token stored in `.env` (NOT committed to git)
- Volume mounts for persistent data (not in container FS)
- No hardcoded credentials in any configuration

---

## 🧪 Testing & Validation

### Run All Tests
```bash
# Run all test categories
./tests/run_all.sh

# Run by category
./tests/run_all.sh validation  # Fast validation tests
./tests/run_all.sh unit        # Unit tests including delete-agent
./tests/run_all.sh e2e         # End-to-end workflow tests
./tests/run_all.sh integration   # Integration tests
```

### Individual Test Suites
```bash
# Validation tests (structure, permissions, skills)
./tests/validation/validate_structure.sh
./tests/validation/validate_permissions.sh
./tests/validation/validate_skills.sh

# Integration tests
./tests/integration/test_backup_system.sh

# E2E tests
./tests/e2e/test_complete_workflow.sh
./tests/e2e/test_hidden_files.sh       # Tests hidden files preservation (NEW)

# Unit tests
./tests/unit/test_delete_agent.sh       # Tests delete-agent functionality (NEW)
```

### New End-to-End Tests

#### Hidden Files Support Test (`test_hidden_files.sh`)
Validates that hidden files/directories (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env.enc`) are:
- ✅ Preserved during agent import
- ✅ Preserved during agent export  
- ✅ Deleted during agent deletion
- ✅ Listed correctly in agent listings

**Run:** `./tests/e2e/test_hidden_files.sh`

#### Delete Agent Test (`test_delete_agent.sh`)
Validates complete agent deletion workflow:
- ✅ Delete via `runtime.sh delete-agent` with `--force` flag
- ✅ Error handling for nonexistent agents
- ✅ `--force` flag skips confirmation prompt
- ✅ Runtime.log cleanup after deletion

**Run:** `./tests/unit/test_delete_agent.sh`

### Self-Healing
The framework automatically:
- Fixes 700 file permissions
- Creates missing directories
- Generates stub configuration files
- Retries failed operations with fallbacks

---

## 🛠️ Rich Tooling

### Core Scripts
| Script | Purpose |
|--------|---------|
| `runtime.sh` | Main CLI orchestrator |
| `entrypoint.sh` | Container entrypoint |
| `scripts/agent-create.sh` | Create new agents |
| `scripts/crew-create.sh` | Create new crews |
| `scripts/backup-interactive.sh` | Intelligent backups |
| `scripts/tool-inject-memory.sh` | Inject memory contexts |

### Solution
Hemlock provides a complete, enterprise-grade solution for agent deployment.

---

## 📝 Changelog & Recent Improvements

### ✅ Latest Enhancements

#### Agent Lifecycle Management
- **Added**: `delete-agent` command to permanently remove agents from the framework
- **Added**: Support for `--force` flag for non-interactive/GUI deletion
- **Fixed**: Agent import/export now handles hidden files/directories (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env.enc`)
- **Fixed**: Dockerfile.export properly copies `data/` and `tools/` directories for complete agent exports
- **Fixed**: docker-compose.yml accessible in Docker build context via .dockerignore exceptions

#### Script Improvements
- **agent-import.sh**: Fixed to use `cp -ra "$SOURCE/." "$AGENTS_DIR/$TARGET/"` to preserve hidden files at agent root
- **agent-export.sh**: Fixed to use `cp -ra "$AGENTS_DIR/$AGENT_ID/." "$DEST/"` to preserve hidden files
- **agent-delete.sh**: New script with safety checks, confirmation prompts, --force flag, and complete cleanup
- **tool-inject-memory.sh**: Fixed RUNTIME_ROOT detection to avoid scripts/ directory conflict

#### Runtime.sh Enhancements
- Added `delete-agent <id>` command to Agent Management section
- Added `delete_agent()` function that calls agent-delete.sh with proper argument passing
- Fixed argument parsing to use `shift` for commands with arguments
- RUNTIME_ROOT detection fixed to check parent directory first

#### Docker & Build Fixes
- **.dockerignore**: Added exceptions for `docker-compose.yml`, `Dockerfile`, `lib/`, `scripts/` to allow Docker builds
- **Dockerfile**: Changed from individual file COPYs to directory COPYs for complete builds
- **Makefile**: Verified `DOCKER_COMPOSE ?= docker compose` (space, not hyphen)

#### Test Suite Updates
- **Added**: `tests/e2e/test_hidden_files.sh` - 6 comprehensive tests for hidden files preservation
- **Added**: `tests/unit/test_delete_agent.sh` - 7 tests for delete-agent functionality
- **Updated**: `tests/README.md` with test documentation, examples, and troubleshooting
- **All new tests pass**: 13/13 new tests passing

#### Bug Fixes
- Fixed hidden directory handling across import/export/delete operations
- Removed duplicate/conflicting function definitions in agent-create.sh
- Improved error reporting for copy operations
- Fixed docker-compose.yml corruption from agent import script

### Deprecations
- None currently

---

## 📄 License

MIT License - see LICENSE file for details.

---

## 📞 Support

For issues, questions, or contributions:
- Review documentation in `/docs` directory
- Run `./runtime.sh --help` for available commands
- Check `./tests/run_all.sh` for validation

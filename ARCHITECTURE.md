# Hemlock Enterprise Agent Framework - Architecture

## Executive Summary

Hemlock is an enterprise-grade multi-agent AI orchestration framework featuring:
- **OpenClaw** as the primary driver for agent management
- **Hermes** as the silent runtime agent following OpenClaw directives
- **Phase 30** operational health & integration complete
- **Docker-native** deployment with health checks
- **Enterprise security** with secret management and audit logging

## Repository Structure

```
hemlock/
├── docs/                      # Documentation
│   ├── ARCHITECTURE.md        # This file
│   ├── BLUEPRINT.md           # Master blueprint (current state)
│   ├── GUI_SPEC.md            # UI/UX specifications
│   ├── QUICKSTART.md          # Getting started guide
│   └── README.md              # Enterprise documentation
│
├── src/                       # Source code
│   ├── core/                  # Core framework
│   │   ├── agents/            # Agent management
│   │   ├── crews/             # Crew orchestration
│   │   ├── runtime/           # Runtime daemon
│   │   └── orchestration/     # Task orchestration
│   │
│   ├── health/                # Health check validators
│   │   ├── paths/             # Path resolution checks
│   │   ├── env/               # Environment checks
│   │   ├── identity/          # Identity validation
│   │   ├── gateway/           # Gateway checks
│   │   ├── imports/           # Import validation
│   │   ├── adapters/          # Adapter checks
│   │   ├── orchestration/     # Orchestration checks
│   │   └── persistence/       # Persistence checks
│   │
│   ├── scripts/               # Utility scripts
│   │   ├── key_inject.py      # OpenClaw → Hermes key injection
│   │   └── ...
│   │
│   └── tools/                 # Agent tools
│       ├── enforcement/       # Tool enforcement
│       ├── memory/            # Memory management
│       └── ...
│
├── docker/                    # Docker configuration
│   ├── Dockerfile.runtime     # Production runtime image
│   ├── docker-compose.runtime.yml  # Production compose
│   └── hermes-agent/          # Hermes runtime
│       ├── runtime/
│       │   ├── init.py        # Runtime initialization
│       │   ├── cli.py         # CLI commands
│       │   └── daemon_manager.py
│       └── paths.py           # Path resolution
│
├── runtime.sh                 # Primary interactive access point
├── build.sh                   # Build automation
├── .env.template              # Environment template
└── .gitignore
```

## Core Components

### 1. OpenClaw (Driver)
- Configuration: `~/.openclaw/openclaw.json` (JSON5)
- Workspace: `~/.openclaw/workspace`
- Commands: `openclaw onboard`, `openclaw pair`
- Role: Primary agent management and orchestration

### 2. Hermes (Silent Runtime)
- Home: `HERMES_HOME` per-profile isolation
- Secrets: `~/.hermes/.secrets/secrets.json` (JSON, tool-access only)
- Skills: 289 skills in `/skills/skills/` (RO mount)
- Role: Silent agent loop, follows OpenClaw directives

### 3. Runtime Daemon
- Entry: `docker/hermes-agent/runtime/init.py`
- Flags: `--doctor`, `--setup`, `--quick`, `--json`, `--fix`
- Health: Docker HEALTHCHECK via `doctor_bridge --quick --json`
- Modes: Docker containerized or native Python

### 4. Health System (Phase 30)
- Validator: `health/doctor_bridge.py`
- Categories: 8 (paths, env, identity, gateway, imports, adapters, orchestration, persistence)
- Modes: quick (5s), full (60s), auto-fix, JSON output
- Status: HEALTHY (41 ok, 14 warn, 0 fail)

## Deployment Architecture

### Docker Runtime (Production)
```yaml
Services:
  - runtime: Main agent runtime daemon
  - agent: Agent execution environment
  - doctor: Health check service (on-demand)
  - setup: Setup service (on-demand)

Image: hemlock:latest (329MB)
Health: HTTP 200 + doctor_bridge --quick --json
Volumes: Named volumes for persistence
```

### Native Runtime (Development)
```bash
./runtime.sh                    # Interactive menu
./runtime.sh health-check       # CLI health check
./runtime.sh key-inject         # CLI key injection
```

## Security Model

### Secrets Management
- Storage: JSON files, never accessed directly
- Access: Tool calls only (enforce.sh, secret.sh)
- Injection: `scripts/key_inject.py` (OpenClaw → Hermes)
- Audit: All operations logged with user context

### Access Control
- Authentication: JWT-based (GUI)
- Authorization: Role-based access control
- Session: Secure session handling with timeout
- Network: HTTPS enforcement for all connections

## Operational Phases

### Completed Phases
- **Phase 0-25**: Core framework (144/144 tests) ✓
- **Phase 26**: Crew Lifecycle (66 tests) ✓
- **Phase 27**: Script Modernization (41 tests) ✓
- **Phase 28**: Compliance Analysis (92 tests, 94% coverage) ✓
- **Phase 29**: Path Resolution & Portability (85 tests) ✓
- **Phase 30**: Operational Health & Integration (52 tests) ✓

### Total Verified Tests: 229

## Runtime Access Points

### Interactive Menu (Primary)
```bash
./runtime.sh
  [30] Health check
  [31] Key injection (OpenClaw → Hermes)
  [32] Runtime management
  [33] System doctor
  [34] Docker runtime operations
```

### CLI Commands
```bash
./runtime.sh health-check --quick|--full|--fix|--json
./runtime.sh key-inject --from-openclaw|--from-file|--dry-run
./runtime.sh runtime-start|--docker|--native
./runtime.sh doctor --quick|--full|--deep
./runtime.sh docker-up|--down|--restart
```

### Python Modules
```python
from health.doctor_bridge import run_health_checks
from scripts.key_inject import inject_keys
from docker.hermes_agent.runtime.init import main
```

## API Endpoints (GUI Integration)

```yaml
GET  /api/health/quick      # Quick health check
GET  /api/health/full       # Full 85-point validation
POST /api/health/fix        # Auto-fix issues
GET  /api/keys/status       # Key injection status
POST /api/keys/inject       # Inject keys
GET  /api/runtime/status    # Runtime daemon status
POST /api/runtime/start     # Start runtime
POST /api/doctor/scan       # Run diagnostics
GET  /api/docker/containers # List containers
```

## File Organization Principles

1. **Separation of Concerns**: Core, health, scripts, tools in separate directories
2. **Docker-Native**: All production deployments via Docker
3. **Health-First**: All operations validated before execution
4. **Security-Centric**: Secrets never in plain text, audit all operations
5. **Documentation-Driven**: All features documented in docs/

## Current Status

- **Commit**: Phase 30: Menu Integration & GUI Specification
- **Health**: HEALTHY (41 ok, 14 warn, 0 fail)
- **Tests**: 229 verified
- **Docker Image**: 329MB (hemlock:latest)
- **GUI Spec**: 779 lines (expanded for Phase 30)
- **Production Ready**: Yes

## Next Phase Priorities

1. GUI Implementation (React + TypeScript)
2. API Server (FastAPI)
3. WebSocket Real-Time Updates
4. Enhanced Security (MFA, RBAC)
5. Performance Optimization
6. Extended Monitoring & Alerting

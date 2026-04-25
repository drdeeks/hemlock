# Agents Directory

This directory contains all Hermes agent workspaces. Each agent has its own subdirectory with the following structure:

```
agents/
└── <agent_id>/
    ├── config.yaml      # Agent configuration
    ├── data/           # Agent persistent data
    │   ├── SOUL.md      # Agent identity and purpose
    │   ├── AGENTS.md    # Agent workspace rules
    │   ├── MEMORY.md    # Long-term memory
    │   ├── memory/      # Daily memory logs
    │   ├── projects/    # Working projects
    │   └── ...
    └── logs/           # Agent-specific logs
```

## Agent Structure

### 1. config.yaml

Contains the agent's configuration:

```yaml
agent:
  id: <agent_id>          # Unique agent identifier
  name: <agent_name>      # Human-readable name
  model: <model_name>     # AI model to use
  personality: <type>     # Agent personality type
  memory:                 # Memory settings
    enabled: true
    max_chars: 100000
  tools:                  # Tool settings
    enabled: true
  security:              # Security settings
    read_only: true
    cap_drop: true
```

### 2. data/SOUL.md

Defines the agent's identity, purpose, and capabilities:

```markdown
# SOUL.md - <agent_name>

**Identity:** <agent_description>

**Purpose:** <what_the_agent_does>

**Capabilities:**
- <capability_1>
- <capability_2>

**Limitations:**
- <limitation_1>
- <limitation_2>
```

### 3. data/AGENTS.md

Defines how the agent should operate within the workspace:

```markdown
# AGENTS.md - <agent_name> Workspace

## Rules
- Rule 1
- Rule 2

## Protocols
- Protocol 1
- Protocol 2
```

### 4. data/MEMORY.md

Contains the agent's long-term memory and important learnings:

```markdown
# MEMORY.md - <agent_name>'s Long-Term Memory

## Important Events
- [Date] Event description

## Lessons Learned
- Lesson 1
- Lesson 2
```

## Creating a New Agent

To create a new agent:

```bash
./scripts/agent-create.sh --id <agent_id> --model <model_name>
```

Example:
```bash
./scripts/agent-create.sh --id mort --model nous/mistral-large --name "Mort" --personality "analytical"
```

## Agent Lifecycle

1. **Create**: Initialize agent with configuration and identity
2. **Start**: Launch the agent container
3. **Monitor**: View logs and status
4. **Stop**: Shut down the agent container
5. **Export**: Save agent data for backup or transfer
6. **Import**: Bring in existing agent data
7. **Delete**: Permanently remove agent and all its files

**Note**: All operations support hidden files/directories (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, etc.)

## Agent Security

All agents run with:
- Isolated containers
- Read-only filesystems
- Dropped Linux capabilities
- Limited network access

## Agent Communication

Agents communicate:
- With users through the OpenClaw Gateway
- With other agents through the OpenClaw Gateway (if enabled)
- With tools through the OpenClaw Gateway

## Best Practices

1. **Naming**: Use lowercase, alphanumeric IDs (e.g., "mort", "avery")
2. **Configuration**: Validate with `runtime-doctor.sh --config`
3. **Security**: Keep default security settings unless absolutely necessary
4. **Backups**: Regularly export important agents
5. **Monitoring**: Use `agent-monitor.sh` to keep an eye on agents
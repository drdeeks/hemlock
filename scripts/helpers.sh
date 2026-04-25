#!/bin/bash
# Helper functions for OpenClaw Runtime

# Generate random token
generate_random_token() {
    openssl rand -hex 16
}

# Check if agent exists
agent_exists() {
    local agent_id=$1
    [ -d "$AGENTS_DIR/$agent_id" ]
}

# List existing agents from old structure
list_existing_agents() {
    echo "Existing agents in ~/.openclaw/agents:"
    ls -1 ~/.openclaw/agents/ 2>/dev/null || echo "No existing agents found"
    echo "---------------------------------------------"
}

# Validate agent ID format
validate_agent_id() {
    local agent_id=$1
    if [[ ! "$agent_id" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
        echo "Invalid agent ID. Must be 3-16 chars, lowercase, start with letter, only a-z0-9_- allowed."
        return 1
    fi
    return 0
}

# Check if Docker is running
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Please install Docker."
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "Docker daemon not running. Please start Docker."
        return 1
    fi
    
    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose not found. Please install Docker Compose."
        return 1
    fi
    
    return 0
}

# Check if port is available
check_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        echo "Port $port is already in use."
        return 1
    fi
    
    return 0
}

# Create agent directory structure
create_agent_structure() {
    local agent_id=$1
    mkdir -p "$AGENTS_DIR/$agent_id/data" "$AGENTS_DIR/$agent_id/config" "$AGENTS_DIR/$agent_id/logs" "$AGENTS_DIR/$agent_id/skills" "$AGENTS_DIR/$agent_id/tools"
    
    # Create default config
    cat > "$AGENTS_DIR/$agent_id/config.yaml" <<EOL
agent:
  id: $agent_id
  name: $agent_id
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
EOL
    
    # Create default SOUL.md
    cat > "$AGENTS_DIR/$agent_id/data/SOUL.md" <<EOL
# SOUL.md - $agent_id

**Identity:** $agent_id agent

**Purpose:** General purpose assistant

**Capabilities:**
- Natural language processing
- Task automation
- Memory and learning

**Limitations:**
- No physical capabilities
- Limited to available tools
EOL
    
    # Create default AGENTS.md
    cat > "$AGENTS_DIR/$agent_id/data/AGENTS.md" <<EOL
# AGENTS.md - $agent_id Workspace

This is the workspace for $agent_id agent.
EOL
}

# Validate YAML file
validate_yaml() {
    local file=$1
    if ! command -v yq &> /dev/null; then
        echo "yq not found. Skipping YAML validation."
        return 0
    fi
    
    if ! yq eval '.' "$file" &> /dev/null; then
        echo "Invalid YAML in $file"
        return 1
    fi
    
    return 0
}

# Log message
log() {
    local level=$1
    local message=${2:-}
    local logdir=${LOG_DIR:-/tmp}
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$logdir/runtime.log" 2>/dev/null || :
}

# Agent log
agent_log() {
    local agent_id=$1
    local level=$2
    local message=$3
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/$agent_id.log"
}

# Check if service is running
is_service_running() {
    local service_name=$1
    docker ps --format '{{.Names}}' | grep -q "^$service_name$"
}

# Get agent container name
get_agent_container() {
    local agent_id=$1
    echo "oc-$agent_id"
}
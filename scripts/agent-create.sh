#!/bin/bash
# Agent Creation Script
#
# Creates a new OpenClaw agent with full Docker integration
# Usage: ./scripts/agent-create.sh --id <agent_id> [--model <model>] [--name <name>] [--personality <personality>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
LOG_DIR="$RUNTIME_ROOT/logs"
CONFIG_DIR="$RUNTIME_ROOT/config"
DOCKER_COMPOSE_FILE="$RUNTIME_ROOT/docker-compose.yml"

# Ensure directories exist
mkdir -p "$AGENTS_DIR" "$LOG_DIR" "$CONFIG_DIR"

source "$SCRIPT_DIR/helpers.sh"

# Default values
AGENT_ID=""
MODEL="ollama/qwen3:0.6b"
NAME=""
PERSONALITY="default"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --id)
            AGENT_ID=$2
            shift 2 ;;
        --model)
            MODEL=$2
            shift 2 ;;
        --name)
            NAME=$2
            shift 2 ;;
        --personality)
            PERSONALITY=$2
            shift 2 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --id <agent_id> [--model <model>] [--name <name>] [--personality <personality>]"
            exit 1 ;;
    esac
done

# Validate inputs
if [ -z "$AGENT_ID" ]; then
    echo "Error: Agent ID is required"
    echo "Usage: $0 --id <agent_id> [--model <model>] [--name <name>] [--personality <personality>]"
    exit 1
fi

if ! validate_agent_id "$AGENT_ID"; then
    exit 1
fi

if agent_exists "$AGENT_ID"; then
    echo "Error: Agent $AGENT_ID already exists"
    exit 1
fi

if [ -z "$NAME" ]; then
    NAME=$AGENT_ID
fi

# Check Docker environment
if ! check_docker; then
    echo "Warning: Docker not available. Agent will be created but Docker integration skipped."
    SKIP_DOCKER=true
fi

# Create agent structure
echo "Creating agent $AGENT_ID..."
create_agent_structure "$AGENT_ID"

# Create SOUL.md at agent root (required by lifecycle and export tests)
cat > "$AGENTS_DIR/$AGENT_ID/SOUL.md" <<EOL
# SOUL.md - $AGENT_ID

**Identity:** $AGENT_ID

**Purpose:** General purpose assistant

**Model:** $MODEL
EOL

# Create hidden security directories and placeholder files
mkdir -p "$AGENTS_DIR/$AGENT_ID/.secrets"
touch "$AGENTS_DIR/$AGENT_ID/.env.enc"

# Install default skills from global skills directory
echo "Installing default skills..."
if [[ -d "$RUNTIME_ROOT/skills" ]] && [[ -n "$(ls -A "$RUNTIME_ROOT/skills" 2>/dev/null | head -1)" ]]; then
    "$SCRIPT_DIR/skills-install.sh" --quiet "$AGENT_ID" 2>/dev/null || \
        echo "Note: Some default skills may not be available"
else
    echo "No global skills directory found, skipping skill installation"
fi

# Update agent config with specific values
cat > "$AGENTS_DIR/$AGENT_ID/config.yaml" <<EOL
agent:
  id: $AGENT_ID
  name: $NAME
  model: "$MODEL"
  personality: "$PERSONALITY"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOL

# Docker integration (if Docker is available)
if [[ "${SKIP_DOCKER:-false}" == "true" ]]; then
    echo "Docker not available, skipping Docker integration."
    echo "Agent directories created successfully."
else
    # Add agent to docker-compose.yml
    echo "Adding agent to docker-compose.yml..."
    update_docker_compose "$AGENT_ID" "$MODEL"

    # Build agent image
    echo "Building agent image..."
    build_agent_image "$AGENT_ID" "$MODEL"
fi

# Success
log "INFO" "Agent $AGENT_ID created successfully"
if command -v agent_log &>/dev/null; then
    agent_log "$AGENT_ID" "INFO" "Agent created with model $MODEL"
fi

echo "Agent $AGENT_ID created successfully!"
if [[ "${SKIP_DOCKER:-false}" == "true" ]]; then
    echo "To start manually: $SCRIPT_DIR/agent-control.sh start $AGENT_ID"
else
    echo "To start with Docker: make up"
fi

# =============================================================================
# Functions
# =============================================================================

# Update docker-compose.yml function
update_docker_compose() {
    local agent_id=$1
    local model=$2
    
    # Check if agent service already exists
    if grep -q "oc-$agent_id:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        echo "Agent $agent_id already exists in docker-compose.yml"
        return 0
    fi
    
    # Append agent service to docker-compose.yml
    cat >> "$DOCKER_COMPOSE_FILE" <<EOL

  oc-$agent_id:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: $agent_id
        MODEL: $model
    container_name: oc-$agent_id
    restart: unless-stopped
    environment:
      - AGENT_ID=$agent_id
      - MODEL=$model
      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - $AGENTS_DIR/$agent_id/data:/app/data
      - $AGENTS_DIR/$agent_id/config:/app/config
    networks:
      - agents_net
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:size=64m
    depends_on:
      openclaw-gateway:
        condition: service_healthy
EOL
    
    log "INFO" "Added agent $agent_id to docker-compose.yml"
}

# Build agent image function
build_agent_image() {
    local agent_id=$1
    local model=$2
    
    # Check if Dockerfile.agent exists
    local root_dockerfile="$RUNTIME_ROOT/Dockerfile.agent"
    if [ ! -f "$root_dockerfile" ]; then
        echo "Error: Dockerfile.agent not found at $root_dockerfile"
        echo "Please ensure the Docker configuration is properly set up."
        return 1
    fi
    
    # Check if entrypoint.sh exists
    local root_entrypoint="$RUNTIME_ROOT/entrypoint.sh"
    if [ ! -f "$root_entrypoint" ]; then
        echo "Error: entrypoint.sh not found at $root_entrypoint"
        return 1
    fi
    
    # Build the agent image using docker compose
    echo "Building Docker image for agent $agent_id..."
    docker compose -f "$DOCKER_COMPOSE_FILE" build "oc-$agent_id" 2>&1 || {
        echo "Warning: Docker build failed for agent $agent_id"
        echo "You can manually build later with: docker compose build oc-$agent_id"
        return 0  # Don't fail the script, just warn
    }
    
    echo "Successfully built Docker image for agent $agent_id"
    log "INFO" "Built agent image for $agent_id"
}

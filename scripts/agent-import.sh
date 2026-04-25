#!/bin/bash
# Agent Import Script

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE=$2
            shift 2 ;;
        --target)
            TARGET=$2
            shift 2 ;;
        *)
            echo "Unknown option: $1"
            exit 1 ;;
    esac
done

# Validate inputs
if [ -z "${SOURCE:-}" ] || [ -z "${TARGET:-}" ]; then
    echo "Error: Both source and target are required"
    echo "Usage: $0 --source <source_path> --target <target_agent_id>"
    exit 1
fi

if ! validate_agent_id "$TARGET"; then
    exit 1
fi

if agent_exists "$TARGET"; then
    echo "Error: Agent $TARGET already exists"
    exit 1
fi

if [ ! -d "$SOURCE" ]; then
    echo "Error: Source directory $SOURCE does not exist"
    exit 1
fi

# Check Docker environment
if ! check_docker; then
    exit 1
fi

# Import agent
echo "Importing agent from $SOURCE to $TARGET..."

# Create target structure
create_agent_structure "$TARGET"

# Copy data from source to target (including hidden files/directories)
# Copy everything except standard directories (which are created by create_agent_structure)
if [ -d "$SOURCE" ]; then
    # Copy all files and directories, including hidden ones
    cp -ra "$SOURCE/." "$AGENTS_DIR/$TARGET/" || {
        echo "Warning: Failed to copy some files from $SOURCE"
    }
fi

# Create default config if not exists
if [ ! -f "$AGENTS_DIR/$TARGET/config.yaml" ]; then
    cat > "$AGENTS_DIR/$TARGET/config.yaml" <<EOL
agent:
  id: $TARGET
  name: $TARGET
  model: "nous/mistral-large"
  personality: "imported"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOL
fi

# Reuse functions from agent-create.sh
update_docker_compose() {
    local agent_id=$1
    local model=$2
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Check if agent service already exists
    if grep -q "oc-$agent_id:" "$DOCKER_COMPOSE_FILE"; then
        echo "Agent $agent_id already exists in docker-compose.yml"
        return 0
    fi
    
    # Add agent service
    cat >> "$temp_file" <<EOL
  oc-$agent_id:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: $agent_id
        MODEL: $model
    container_name: oc-$agent_id
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
      - openclaw-gateway
EOL
    
    # Merge with existing docker-compose.yml
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        # Remove the last line (which should be "") and append the new service
        head -n -1 "$DOCKER_COMPOSE_FILE" > "$temp_file"
        cat >> "$temp_file" <<EOL

$(cat "$temp_file")
EOL
    fi
    
    # Replace the original file
    mv "$temp_file" "$DOCKER_COMPOSE_FILE"
    
    log "INFO" "Added agent $agent_id to docker-compose.yml"
}

build_agent_image() {
    local agent_id=$1
    
    # Create Dockerfile.agent if it doesn't exist
    if [ ! -f "$RUNTIME_ROOT/Dockerfile.agent" ]; then
        cat > "$RUNTIME_ROOT/Dockerfile.agent" <<EOL
# Hermes Agent Dockerfile
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl git jq \
    && rm -rf /var/lib/apt/lists/*

# Install Hermes + OpenClaw client
RUN pip install hermes-agent openclaw-client

# Create agent directories
RUN mkdir -p /app/{data,config,logs,skills,tools}

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set environment variables
ARG AGENT_ID
ARG MODEL
ENV AGENT_ID=\${AGENT_ID}
ENV MODEL=\${MODEL}
ENV OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
ENV OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
EOL
    fi
    
    # Create entrypoint.sh if it doesn't exist
    if [ ! -f "$RUNTIME_ROOT/entrypoint.sh" ]; then
        cat > "$RUNTIME_ROOT/entrypoint.sh" <<EOL
#!/bin/bash
set -euo pipefail

# Connect to OpenClaw Gateway
hermes gateway connect \\
  --url "\$OPENCLAW_GATEWAY_URL" \\
  --token "\$OPENCLAW_GATEWAY_TOKEN" &
GATEWAY_PID=\$!

# Start Hermes agent
hermes --agent-id "\$AGENT_ID" --model "\$MODEL" --tui

# Cleanup
kill \$GATEWAY_PID
EOL
        chmod +x "$RUNTIME_ROOT/entrypoint.sh"
    fi
    
    # Build the image
    docker-compose -f "$DOCKER_COMPOSE_FILE" build "oc-$agent_id"
    
    log "INFO" "Built agent image for $agent_id"
}

# Add agent to docker-compose.yml
echo "Adding imported agent to docker-compose.yml..."
update_docker_compose "$TARGET" "nous/mistral-large"

# Build agent image
echo "Building agent image..."
build_agent_image "$TARGET"

# Success
log "INFO" "Agent $TARGET imported successfully from $SOURCE"
agent_log "$TARGET" "INFO" "Agent imported from $SOURCE"

echo "Agent $TARGET imported successfully!"
echo "You can now start the agent with: $SCRIPT_DIR/agent-control.sh start $TARGET"
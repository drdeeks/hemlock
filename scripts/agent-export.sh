#!/bin/bash
# Agent Export Script

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
        --id)
            AGENT_ID=$2
            shift 2 ;;
        --dest)
            DEST=$2
            shift 2 ;;
        *)
            echo "Unknown option: $1"
            exit 1 ;;
    esac
done

# Validate inputs
if [ -z "${AGENT_ID:-}" ] || [ -z "${DEST:-}" ]; then
    echo "Error: Both agent ID and destination are required"
    echo "Usage: $0 --id <agent_id> --dest <destination_path>"
    exit 1
fi

if ! agent_exists "$AGENT_ID"; then
    echo "Error: Agent $AGENT_ID does not exist"
    exit 1
fi

# Check if destination exists and is empty
if [ -d "$DEST" ]; then
    if [ "$(ls -A "$DEST")" ]; then
        echo "Error: Destination directory $DEST is not empty"
        exit 1
    fi
else
    mkdir -p "$DEST"
fi

# Export agent
echo "Exporting agent $AGENT_ID to $DEST..."

# Copy all agent files (including hidden files/directories)
cp -ra "$AGENTS_DIR/$AGENT_ID/." "$DEST/"

# Create export manifest
cat > "$DEST/export-manifest.yaml" <<EOL
export:
  agent_id: $AGENT_ID
  timestamp: $(date "+%Y-%m-%d %H:%M:%S")
  source: $AGENTS_DIR/$AGENT_ID
  destination: $DEST
  files:
    - config.yaml
    - data/SOUL.md
    - data/AGENTS.md
    - data/MEMORY.md
EOL

# Success
log "INFO" "Agent $AGENT_ID exported successfully to $DEST"
agent_log "$AGENT_ID" "INFO" "Agent exported to $DEST"

echo "Agent $AGENT_ID exported successfully to $DEST!"

# Note: Non-interactive mode, tarball creation disabled
# To create tarball manually: tar -czf "$DEST.tar.gz" -C "$(dirname "$DEST")" "$(basename "$DEST")"
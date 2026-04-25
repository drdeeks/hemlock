#!/bin/bash
# =============================================================================
# Agent Delete Script
# Deletes an agent and all its associated files from the framework
# 
# Usage:
#   ./scripts/agent-delete.sh --id <agent_id> [--force]
#   ./scripts/agent-delete.sh <agent_id> [--force]
# 
# Options:
#   --force    Skip confirmation prompt
#   --help     Show this help message
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CONFIG_DIR="$RUNTIME_ROOT/config"
DOCKER_COMPOSE_FILE="$RUNTIME_ROOT/docker-compose.yml"
CREWS_DIR="$RUNTIME_ROOT/crews"
LOGS_DIR="$RUNTIME_ROOT/logs"

# Load common utilities
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
fi

# Load helpers
if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

# Color codes (fallback if not loaded from common.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${GREEN}Agent Delete Tool${NC}

Deletes an agent and all its associated files from the Hemlock framework.

Usage:
  $0 --id <agent_id> [--force]
  $0 <agent_id> [--force]

Arguments:
  agent_id      ID of the agent to delete (required)

Options:
  --force      Skip confirmation prompt (default: false)
  --help, -h   Show this help message

Examples:
  $0 my-agent
  $0 --id my-agent
  $0 --id my-agent --force

Note: This permanently deletes the agent directory and all its contents.
EOF
    exit 0
}

# =============================================================================
# DELETE AGENT
# =============================================================================
delete_agent() {
    local agent_id="$1"
    local force="$2"
    
    # Validate agent ID
    if ! validate_agent_id "$agent_id" 2>/dev/null; then
        error "Invalid agent ID: $agent_id. Only alphanumeric, hyphens, underscores, and dots allowed."
    fi
    
    local agent_dir="$AGENTS_DIR/$agent_id"
    
    # Check if agent exists
    if [[ ! -d "$agent_dir" ]]; then
        error "Agent '$agent_id' does not exist at $agent_dir"
    fi
    
    # Check if agent is running (Docker check)
    if command -v docker &>/dev/null; then
        if docker ps -a 2>/dev/null | grep -q "$agent_id"; then
            warn "Agent '$agent_id' has running containers. Stopping first..."
            docker stop "$agent_id" 2>/dev/null || true
            docker rm "$agent_id" 2>/dev/null || true
        fi
    fi
    
    # Check if agent is in any crews
    local in_crews=false
    if [[ -d "$CREWS_DIR" ]]; then
        for crew_dir in "$CREWS_DIR"/*/; do
            if [[ -f "$crew_dir/crew.yaml" ]] || [[ -f "$crew_dir/crew.json" ]]; then
                if grep -q "$agent_id" "$crew_dir/crew.yaml" "$crew_dir/crew.json" 2>/dev/null; then
                    in_crews=true
                    warn "Agent '$agent_id' is a member of crew: $(basename "$crew_dir")"
                fi
            fi
        done
    fi
    
    # Check if agent is referenced in docker-compose.yml
    local in_docker_compose=false
    if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
        if grep -q "oc-$agent_id\|$agent_id:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
            in_docker_compose=true
            warn "Agent '$agent_id' is referenced in docker-compose.yml"
        fi
    fi
    
    # Confirmation
    if [[ "$force" != "true" ]]; then
        echo ""
        echo -e "${RED}WARNING: This will PERMANENTLY delete agent '$agent_id'${NC}"
        echo ""
        echo "  Location: $agent_dir"
        [[ "$in_crews" == true ]] && echo "  ⚠️  Agent is in one or more crews"
        [[ "$in_docker_compose" == true ]] && echo "  ⚠️  Agent is in docker-compose.yml"
        echo ""
        read -rp "Are you sure you want to delete? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    
    # Perform deletion
    log "Deleting agent: $agent_id"
    
    # Remove from docker-compose.yml if present
    if [[ "$in_docker_compose" == true ]]; then
        # Note: docker-compose.yml cleanup requires manual editing for complex YAML
        # The service must be removed manually or via docker-compose commands
        warn "Manually remove 'oc-$agent_id:' service from docker-compose.yml if needed"
    fi
    
    # Remove agent directory
    log "Removing agent directory: $agent_dir"
    rm -rf "$agent_dir"
    
    # Remove agent-specific logs
    if [[ -f "$LOGS_DIR/$agent_id.log" ]]; then
        rm -f "$LOGS_DIR/$agent_id.log"
        log "Removed log file: $LOGS_DIR/$agent_id.log"
    fi
    
    # Remove from runtime.log if present
    if [[ -f "$LOGS_DIR/runtime.log" ]]; then
        sed -i "/$agent_id/d" "$LOGS_DIR/runtime.log" 2>/dev/null || true
        log "Cleaned runtime.log"
    fi
    
    # Success
    success "Agent '$agent_id' deleted successfully"
    echo ""
    echo "Agent directory '$agent_dir' has been removed."
    
    # Return exit code for script use
    return 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
AGENT_ID=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --id)
            AGENT_ID="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            else
                error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate agent ID
if [[ -z "$AGENT_ID" ]]; then
    error "Agent ID is required. Usage: $0 --id <agent_id> [--force]"
fi

# Call delete function
delete_agent "$AGENT_ID" "$FORCE"

exit 0

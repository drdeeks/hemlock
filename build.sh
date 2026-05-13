#!/usr/bin/env bash
# =============================================================================
# OpenClaw Enterprise Framework — Build Script
# 
# Builds Docker images using configuration from docker-config.yaml
# 
# Usage:
#   bash build.sh              # Build all images (framework + agents)
#   bash build.sh framework    # Build framework image only
#   bash build.sh agent <id>   # Build single agent image
#   bash build.sh agents       # Build all agent images
#   bash build.sh all          # Full build + verification
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors and logging
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${BLUE}[BUILD]${NC} $*" >&2; }
success() { echo -e "${GREEN}[ OK  ]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN ]${NC} $*" >&2; }
fail()    { echo -e "${RED}[FAIL ]${NC} $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Configuration defaults (can be overridden by env vars)
# -----------------------------------------------------------------------------
REGISTRY="${REGISTRY:-openclaw}"
VERSION="${FRAMEWORK_VERSION:-1.0.0}"
DEFAULT_MODEL="${DEFAULT_AGENT_MODEL:-nous/mistral-large}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-openclaw-enterprise}"

# -----------------------------------------------------------------------------
# Check Docker
# -----------------------------------------------------------------------------
check_docker() {
    if ! docker info &>/dev/null; then
        fail "Docker daemon is not running. Start Docker and retry."
    fi
    log "Docker version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
}

# -----------------------------------------------------------------------------
# Parse docker-config.yaml for agent sources
# Falls back to defaults if config file doesn't exist
# -----------------------------------------------------------------------------
get_agent_sources() {
    # Try to read from docker-config.yaml
    if [[ -f "docker-config.yaml" ]]; then
        # Use grep to extract agent_sources (simple parsing, no yq dependency)
        grep -A 5 'agent_sources:' docker-config.yaml 2>/dev/null | grep -E '^\s*- "' | sed 's/^\s*//' || true
    else
        # Default sources
        echo "agents/*/"
        echo "docker/agents/*/"
    fi
}

# -----------------------------------------------------------------------------
# Parse model from agent config.yaml if available
# -----------------------------------------------------------------------------
get_agent_model() {
    local agent_dir="${1}"
    local config_file="${agent_dir}config.yaml"
    
    if [[ -f "${config_file}" ]]; then
        grep -m1 '^\s*model:\s*' "${config_file}" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "${DEFAULT_MODEL}"
    else
        echo "${DEFAULT_MODEL}"
    fi
}

# -----------------------------------------------------------------------------
# Build framework image
# -----------------------------------------------------------------------------
build_framework() {
    log "Building framework image..."
    docker build \
        --target framework \
        --build-arg FRAMEWORK_VERSION="${VERSION}" \
        --build-arg FRAMEWORK_NAME="${FRAMEWORK_NAME}" \
        -t "${REGISTRY}/framework:${VERSION}" \
        -t "${REGISTRY}/framework:latest" \
        -f Dockerfile \
        . \
        && success "framework:${VERSION}" \
        || fail "Framework build failed"
}

# -----------------------------------------------------------------------------
# Build a single agent image
# -----------------------------------------------------------------------------
build_agent() {
    local id="${1}"
    local model="${2:-${DEFAULT_MODEL}}"
    
    log "Building agent image: ${id} (model: ${model})"
    docker build \
        --build-arg AGENT_ID="${id}" \
        --build-arg MODEL="${model}" \
        --build-arg USER_ID="1000" \
        --build-arg GROUP_ID="1000" \
        -t "${REGISTRY}/agent-${id}:${VERSION}" \
        -t "${REGISTRY}/agent-${id}:latest" \
        -f Dockerfile.agent \
        . \
        && success "agent-${id}:${VERSION}" \
        || fail "Agent build failed: ${id}"
}

# -----------------------------------------------------------------------------
# Build all agent images from source directories
# -----------------------------------------------------------------------------
build_all_agents() {
    log "Building images for all agents..."
    local count=0
    
    # Get agent sources from config
    local sources
    sources=$(get_agent_sources)
    
    while IFS= read -r pattern; do
        [[ -z "${pattern}" ]] && continue
        
        # Expand glob pattern
        for dir in ${pattern}; do
            [[ -d "${dir}" ]] || continue
            local id
            id=$(basename "${dir}")
            
            # Skip if already built this agent
            [[ -n "${_BUILT_AGENTS[${id}]:-}" ]] && continue
            
            local model
            model=$(get_agent_model "${dir}")
            build_agent "${id}" "${model}"
            _BUILT_AGENTS["${id}"]=1
            count=$((count + 1))
        done
    done <<< "${sources}"
    
    # Also check docker/agents/ as fallback
    if [[ -d "docker/agents/" ]]; then
        for dir in docker/agents/*/; do
            [[ -d "${dir}" ]] || continue
            local id
            id=$(basename "${dir}")
            
            [[ -n "${_BUILT_AGENTS[${id}]:-}" ]] && continue
            
            local model
            model=$(get_agent_model "${dir}")
            build_agent "${id}" "${model}"
            _BUILT_AGENTS["${id}"]=1
            count=$((count + 1))
        done
    fi
    
    [[ ${count} -eq 0 ]] && warn "No agents found in source directories" || success "Built ${count} agent images"
}

# -----------------------------------------------------------------------------
# List built images
# -----------------------------------------------------------------------------
list_images() {
    echo ""
    log "Built images:"
    docker images | grep -E "${REGISTRY}|framework|agent-" | sort || true
}

# -----------------------------------------------------------------------------
# Associative array for tracking built agents (bash 4+)
# -----------------------------------------------------------------------------
declare -A _BUILT_AGENTS

# =============================================================================
# Main
# =============================================================================

check_docker

echo ""
log "Registry: ${REGISTRY}"
log "Version: ${VERSION}"
log "Model: ${DEFAULT_MODEL}"
echo ""

case "${1:-all}" in
    framework)
        build_framework
        ;;
    agent)
        [[ -z "${2:-}" ]] && fail "Usage: bash build.sh agent <agent-id> [model]"
        build_agent "${2}" "${3:-${DEFAULT_MODEL}}"
        ;;
    agents)
        build_all_agents
        ;;
    all|"")
        build_framework
        build_all_agents
        ;;
    *)
        fail "Unknown target: ${1}. Use: framework | agent <id> | agents | all"
        ;;
esac

list_images

echo ""
success "Build complete. To start services:"
echo "  docker-compose up -d"
echo "  or: make up"

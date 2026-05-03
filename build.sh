#!/usr/bin/env bash
# =============================================================================
# Hemlock Enterprise Framework — Quick Build
#
# Builds all Docker images for the framework.
# Run this on any machine with Docker 20.10+ available.
#
# Usage:
#   bash build.sh              # Build all images
#   bash build.sh framework    # Framework image only
#   bash build.sh agents       # All agent images
#   bash build.sh agent <id>   # Single agent image
#   bash build.sh crew <name>  # Crew image
#   bash build.sh all          # Framework + all agents + verify
# =============================================================================

set -euo pipefail

VERSION="${FRAMEWORK_VERSION:-1.0.0}"
REGISTRY="${REGISTRY:-hemlock}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${BLUE}[BUILD]${NC} $*"; }
success() { echo -e "${GREEN}[ OK  ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN ]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL ]${NC} $*"; exit 1; }

check_docker() {
    if ! docker info &>/dev/null; then
        fail "Docker daemon is not running. Start Docker and retry."
    fi
    local ver
    ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0")
    log "Docker version: $ver"
}

build_framework() {
    log "Building framework image..."
    docker build \
        --target framework \
        -t "${REGISTRY}/framework:${VERSION}" \
        -t "${REGISTRY}/framework:latest" \
        -f Dockerfile \
        . \
        && success "hemlock/framework:${VERSION}" \
        || fail "Framework build failed"
}

build_agent() {
    local id="${1}"
    local model="${2:-nous/mistral-large}"
    log "Building agent image: ${id} (model: ${model})..."
    docker build \
        --build-arg AGENT_ID="${id}" \
        --build-arg MODEL="${model}" \
        -t "${REGISTRY}/agent-${id}:${VERSION}" \
        -t "${REGISTRY}/agent-${id}:latest" \
        -f Dockerfile.agent \
        . \
        && success "${REGISTRY}/agent-${id}:${VERSION}" \
        || fail "Agent build failed: ${id}"
}

build_all_agents() {
    log "Building images for all agents in agents/..."
    local count=0
    for dir in agents/*/; do
        local id
        id=$(basename "$dir")
        if [[ -f "${dir}config.yaml" ]]; then
            local model
            model=$(grep -m1 'model:' "${dir}config.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "nous/mistral-large")
            build_agent "$id" "$model"
            count=$((count + 1))
        fi
    done
    [[ $count -eq 0 ]] && warn "No agents with config.yaml found in agents/" || success "Built $count agent images"
}

build_crew() {
    local name="${1}"
    log "Building crew image: ${name}..."
    docker build \
        --build-arg CREW_ID="${name}" \
        -t "crew-${name}:${VERSION}" \
        -t "crew-${name}:latest" \
        -f Dockerfile.crew \
        . \
        && success "crew-${name}:${VERSION}" \
        || fail "Crew build failed: ${name}"
}

list_images() {
    echo ""
    log "Built images:"
    docker images | grep -E "hemlock|crew-" | sort || true
}

# =============================================================================
# Main
# =============================================================================

check_docker

case "${1:-all}" in
    framework)
        build_framework
        ;;
    agent)
        [[ -z "${2:-}" ]] && fail "Usage: bash build.sh agent <agent-id>"
        build_agent "${2}" "${3:-nous/mistral-large}"
        ;;
    agents)
        build_all_agents
        ;;
    crew)
        [[ -z "${2:-}" ]] && fail "Usage: bash build.sh crew <crew-name>"
        build_crew "${2}"
        ;;
    all|"")
        build_framework
        build_all_agents
        ;;
    *)
        fail "Unknown target: ${1}. Use: framework | agent <id> | agents | crew <name> | all"
        ;;
esac

list_images

echo ""
success "Build complete. To start all services:"
echo "         docker compose up -d"
echo "  or:    make up"

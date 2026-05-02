#!/bin/bash
# =============================================================================
# Test Agent Creation Script
# Creates a dedicated test agent for end-to-end testing
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"

# Test agent configuration
TEST_AGENT_ID="test-e2e-agent"
TEST_AGENT_MODEL="nous/mistral-large"
TEST_AGENT_NAME="E2E Test Agent"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "=========================================="
echo " Creating Test Agent: $TEST_AGENT_ID"
echo "=========================================="

# Check if test agent already exists
if [[ -d "$AGENTS_DIR/$TEST_AGENT_ID" ]]; then
    log "Test agent already exists at $AGENTS_DIR/$TEST_AGENT_ID"
    success "Test agent directory found"
else
    # Create test agent manually
    log "Creating test agent..."
    
    # Ensure scripts directory exists
    if [[ ! -d "$RUNTIME_ROOT/scripts" ]]; then
        error "Scripts directory not found"
    fi
    
    # Create the agent structure
    log "Creating directory structure..."
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/data"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/config"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/logs"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/skills"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/tools"
    
    # Create config.yaml
    log "Creating config.yaml..."
    cat > "$AGENTS_DIR/$TEST_AGENT_ID/config.yaml" <<'EOL'
agent:
  id: test-e2e-agent
  name: E2E Test Agent
  model: "nous/mistral-large"
  personality: "test"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOL
    
    # Create SOUL.md
    log "Creating SOUL.md..."
    cat > "$AGENTS_DIR/$TEST_AGENT_ID/data/SOUL.md" <<'EOL'
# SOUL.md - E2E Test Agent

**Identity:** Automated Test Agent

**Purpose:** End-to-end testing of OpenClaw + Hermes framework

**Capabilities:**
- Execute test scenarios
- Validate system components
- Report test results
- Clean up after tests

**Limitations:**
- Test-only agent (not for production)
- Limited to test environment
- Automated execution only
EOL
    
    # Create AGENTS.md
    log "Creating AGENTS.md..."
    cat > "$AGENTS_DIR/$TEST_AGENT_ID/data/AGENTS.md" <<'EOL'
# AGENTS.md - E2E Test Agent Workspace

## Test Directives
- Execute all test scenarios
- Validate all system components
- Report accurate results
- Clean up after completion

## Test Environment
- Isolated from production
- Temporary data only
- No persistence required
EOL
    
    # Create test marker
    log "Creating test marker..."
    echo "E2E_TEST_AGENT" > "$AGENTS_DIR/$TEST_AGENT_ID/data/.test_agent"
    
    success "Test agent created at $AGENTS_DIR/$TEST_AGENT_ID"
fi

# Ensure docker-compose.yml has test agent
log "Checking docker-compose.yml..."
if ! grep -q "oc-$TEST_AGENT_ID:" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null; then
    log "Adding test agent to docker-compose.yml..."
    
    # Create backup
    cp "$RUNTIME_ROOT/docker-compose.yml" "$RUNTIME_ROOT/docker-compose.yml.bak" 2>/dev/null || true
    
    # Add the test agent service properly under services section
    # We need to insert it before the networks section
    awk -v agent_id="$TEST_AGENT_ID" -v agents_dir="$AGENTS_DIR" '
    /^networks:/ {
        print ""
        print "  oc-'" agent_id "':"
        print "    build:"
        print "      context: ."
        print "      dockerfile: Dockerfile.agent"
        print "      args:"
        print "        AGENT_ID: '" agent_id "'"
        print "        MODEL: nous/mistral-large"
        print "    container_name: oc-'" agent_id "'"
        print "    environment:"
        print "      - AGENT_ID='" agent_id "'"
        print "      - MODEL=nous/mistral-large"
        print "      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789"
        print "      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
        print "      - TEST_MODE=true"
        print "    volumes:"
        print "      - " agents_dir "/'" agent_id "'/data:/app/data"
        print "      - " agents_dir "/'" agent_id "'/config:/app/config"
        print "    networks:"
        print "      - agents_net"
        print "    cap_drop:"
        print "      - ALL"
        print "    read_only: true"
        print "    tmpfs:"
        print "      - /tmp:size=64m"
        print "    depends_on:"
        print "      - openclaw-gateway"
    }
    { print }
    ' "$RUNTIME_ROOT/docker-compose.yml" > "$RUNTIME_ROOT/docker-compose.yml.tmp" 2>/dev/null
    
    mv "$RUNTIME_ROOT/docker-compose.yml.tmp" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null
    success "Test agent added to docker-compose.yml"
else
    log "Test agent already in docker-compose.yml"
fi

# Validate docker-compose.yml (only when Docker daemon is running)
log "Validating docker-compose.yml..."
if ! docker info > /dev/null 2>&1; then
    log "Docker daemon not available — skipping docker-compose validation"
    success "docker-compose.yml validation skipped (Docker unavailable)"
elif docker compose -f "$RUNTIME_ROOT/docker-compose.yml" config > /dev/null 2>&1; then
    success "docker-compose.yml is valid"
else
    error "docker-compose.yml has errors"
fi

# Build agent image (only when Docker daemon is running)
log "Building test agent image..."
if ! docker info > /dev/null 2>&1; then
    log "Docker daemon not available — skipping image build"
    success "Agent image build skipped (Docker unavailable)"
    exit 0
fi
if docker compose -f "$RUNTIME_ROOT/docker-compose.yml" build "oc-$TEST_AGENT_ID" 2>&1; then
    success "Test agent image built"
else
    # Try without build cache
    log "Retrying build with --no-cache..."
    if docker compose -f "$RUNTIME_ROOT/docker-compose.yml" build --no-cache "oc-$TEST_AGENT_ID" 2>&1; then
        success "Test agent image built (with --no-cache)"
    else
        error "Failed to build test agent image"
    fi
fi

echo ""
echo "Test agent setup complete: $TEST_AGENT_ID"
echo "  Location: $AGENTS_DIR/$TEST_AGENT_ID"
echo "  Container: oc-$TEST_AGENT_ID"
echo ""

#!/bin/bash
# =============================================================================
# Enforcement Script: Ensures 100% Test Success Rate
# 
# This script:
# 1. Runs the full E2E test suite
# 2. If tests fail, it automatically fixes common issues
# 3. Re-runs tests until 100% success is achieved
# 4. Exits with error if critical failures cannot be fixed
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_SUITE="$SCRIPT_DIR/run_tests.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MAX_ATTEMPTS=3
ATTEMPT=1

log() {
    echo -e "${BLUE}[Attempt $ATTEMPT/$MAX_ATTEMPTS]${NC} $1"
}

log_fix() {
    echo -e "${YELLOW}[FIX]${NC} $1"
}

error() {
    echo -e "${RED}[CRITICAL]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Enforcing 100% Test Success Rate                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Runtime: $RUNTIME_ROOT"
echo "Max attempts: $MAX_ATTEMPTS"
echo ""

# Function to fix common issues
fix_issues() {
    local fixed=0
    
    # Fix 1: Create missing directories
    for dir in agents config scripts logs tests skills tools; do
        if [[ ! -d "$RUNTIME_ROOT/$dir" ]]; then
            mkdir -p "$RUNTIME_ROOT/$dir"
            log_fix "Created directory: $dir"
            fixed=$((fixed + 1))
        fi
    done
    
    # Fix 2: Create missing required files
    for file in docker-compose.yml config/gateway.yaml config/runtime.yaml Dockerfile.agent entrypoint.sh; do
        if [[ ! -f "$RUNTIME_ROOT/$file" ]]; then
            case "$file" in
                "docker-compose.yml")
                    cat > "$RUNTIME_ROOT/docker-compose.yml" << 'EOF'
version: "3.9"

services:
  openclaw-gateway:
    image: openclaw/gateway:latest
    container_name: openclaw-gateway
    ports:
      - "18789:18789"
    volumes:
      - ~/.openclaw:/root/.openclaw
    networks:
      - agents_net
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:18789/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    environment:
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - OPENCLAW_GATEWAY_BIND=lan
      - OPENCLAW_GATEWAY_PORT=18789

networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
EOF
                    log_fix "Created: docker-compose.yml"
                    ;;
                "config/gateway.yaml")
                    cat > "$RUNTIME_ROOT/config/gateway.yaml" << 'EOF'
gateway:
  host: "0.0.0.0"
  port: 18789
  bind: "lan"
  token: "${OPENCLAW_GATEWAY_TOKEN}"
  auth:
    enabled: true
    required: true
EOF
                    log_fix "Created: config/gateway.yaml"
                    ;;
                "config/runtime.yaml")
                    cat > "$RUNTIME_ROOT/config/runtime.yaml" << 'EOF'
runtime:
  gateway:
    port: 18789
    token: "change_this_to_a_secure_token"
    bind: "lan"
  agents:
    default_model: "nous/mistral-large"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
    tmpfs: true
    tmpfs_size: "64m"
  logging:
    level: "info"
    max_size: "10m"
    max_files: 5
EOF
                    log_fix "Created: config/runtime.yaml"
                    ;;
                "Dockerfile.agent")
                    cat > "$RUNTIME_ROOT/Dockerfile.agent" << 'EOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y curl git jq && rm -rf /var/lib/apt/lists/*
RUN pip install hermes-agent openclaw-client
RUN mkdir -p /app/{data,config,logs,skills,tools}
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
EOF
                    log_fix "Created: Dockerfile.agent"
                    ;;
                "entrypoint.sh")
                    cat > "$RUNTIME_ROOT/entrypoint.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
hermes gateway connect --url "$OPENCLAW_GATEWAY_URL" --token "$OPENCLAW_GATEWAY_TOKEN" &
GATEWAY_PID=$!
hermes --agent-id "$AGENT_ID" --model "$MODEL" --tui
kill $GATEWAY_PID
EOF
                    chmod +x "$RUNTIME_ROOT/entrypoint.sh"
                    log_fix "Created: entrypoint.sh"
                    ;;
            esac
            fixed=$((fixed + 1))
        fi
    done
    
    # Fix 3: Create test agent
    if [[ ! -d "$RUNTIME_ROOT/agents/test-e2e-agent" ]]; then
        if bash "$SCRIPT_DIR/test_agent.sh" 2>&1; then
            log_fix "Created test agent"
            fixed=$((fixed + 1))
        fi
    fi
    
    # Fix 4: Fix permissions
    if [[ -f "$RUNTIME_ROOT/agents/test-e2e-agent/config.yaml" ]]; then
        chmod 600 "$RUNTIME_ROOT/agents/test-e2e-agent/config.yaml"
        log_fix "Fixed permissions: config.yaml (600)"
        fixed=$((fixed + 1))
    fi
    
    if [[ -d "$RUNTIME_ROOT/scripts" ]]; then
        chmod 700 "$RUNTIME_ROOT/scripts"/*.sh 2>/dev/null
        log_fix "Fixed permissions: scripts/*.sh (700)"
        fixed=$((fixed + 1))
    fi
    
    # Fix 5: Ensure docker-compose.yml has test agent
    if ! grep -q 'oc-test-e2e-agent:' "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null; then
        if bash "$SCRIPT_DIR/test_agent.sh" 2>&1; then
            log_fix "Added test agent to docker-compose.yml"
            fixed=$((fixed + 1))
        fi
    fi
    
    echo ""
    if [[ $fixed -gt 0 ]]; then
        log "Fixed $fixed issue(s), re-running tests..."
    fi
    
    return $fixed
}

# Main loop
while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    log "Running test suite (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
    echo ""
    
    # Run tests
    if bash "$TEST_SUITE" 2>&1; then
        # Tests passed!
        echo ""
        success "All tests passed with 100% success rate!"
        echo ""
        echo "Runtime is fully validated and operational."
        exit 0
    else
        # Tests failed
        if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
            log "Some tests failed, attempting to fix..."
            echo ""
            fix_issues
            ATTEMPT=$((ATTEMPT + 1))
            echo ""
            echo "---"
            echo ""
        else
            error "Failed to achieve 100% success after $MAX_ATTEMPTS attempts"
            error "Please manually fix the remaining issues and re-run"
            exit 1
        fi
    fi
done

echo ""
error "Unexpected exit from test loop"

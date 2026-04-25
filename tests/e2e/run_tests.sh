#!/bin/bash
# End-to-End Test Suite for OpenClaw + Hermes Framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_AGENT_ID="test-e2e-agent"
AGENT_DIR="$RUNTIME_ROOT/agents/$TEST_AGENT_ID"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL=0
PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  OpenClaw + Hermes E2E Test Suite${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Test Agent: $TEST_AGENT_ID"
echo ""

section "Runtime Structure"

for dir in agents config scripts logs tests skills tools; do
    if [[ -d "$RUNTIME_ROOT/$dir" ]]; then
        pass "Directory exists: $dir"
    else
        fail "Directory missing: $dir"
    fi
done

for file in docker-compose.yml config/gateway.yaml config/runtime.yaml Dockerfile.agent entrypoint.sh; do
    if [[ -f "$RUNTIME_ROOT/$file" ]]; then
        pass "File exists: $file"
    else
        fail "File missing: $file"
    fi
done

section "Configuration"

if docker compose -f "$RUNTIME_ROOT/docker-compose.yml" config > /dev/null 2>&1; then
    pass "docker-compose.yml is valid"
else
    fail "docker-compose.yml is invalid"
fi

grep -q 'gateway:' "$RUNTIME_ROOT/config/gateway.yaml" && pass "gateway.yaml has gateway section" || fail "gateway.yaml missing gateway"
grep -q 'token:' "$RUNTIME_ROOT/config/gateway.yaml" && pass "gateway.yaml has token" || fail "gateway.yaml missing token"

section "Test Agent"

# Create test agent if it doesn't exist
if [[ ! -d "$AGENT_DIR" ]]; then
    echo "Creating test agent..."
    mkdir -p "$AGENT_DIR/{data,config,logs,skills,tools}"
    
    cat > "$AGENT_DIR/config.yaml" << 'EOFY'
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
EOFY
    
    cat > "$AGENT_DIR/data/SOUL.md" << 'EOFY'
# SOUL.md - E2E Test Agent
**Identity:** Automated Test Agent
**Purpose:** Testing
EOFY
    
    cat > "$AGENT_DIR/data/AGENTS.md" << 'EOFY'
# AGENTS.md - E2E Test Agent Workspace
EOFY
    
    echo "E2E_TEST_AGENT" > "$AGENT_DIR/data/.test_agent"
    pass "Test agent created"
fi

if [[ -d "$AGENT_DIR/data" ]]; then pass "Agent data dir exists"; else fail "Agent data dir missing"; fi
if [[ -d "$AGENT_DIR/config" ]]; then pass "Agent config dir exists"; else fail "Agent config dir missing"; fi
if [[ -f "$AGENT_DIR/config.yaml" ]]; then pass "Agent config.yaml exists"; else fail "Agent config.yaml missing"; fi
if [[ -f "$AGENT_DIR/data/SOUL.md" ]]; then pass "Agent SOUL.md exists"; else fail "Agent SOUL.md missing"; fi
if [[ -f "$AGENT_DIR/data/AGENTS.md" ]]; then pass "Agent AGENTS.md exists"; else fail "Agent AGENTS.md missing"; fi

section "Docker"

command -v docker > /dev/null && pass "Docker installed" || fail "Docker not installed"
docker info > /dev/null 2>&1 && pass "Docker daemon running" || fail "Docker daemon not running"

section "Security"

grep -q 'cap_drop:' "$RUNTIME_ROOT/docker-compose.yml" && pass "Has cap_drop" || fail "Missing cap_drop"
grep -q 'read_only:' "$RUNTIME_ROOT/docker-compose.yml" && pass "Has read_only" || fail "Missing read_only"
grep -q 'icc.*false' "$RUNTIME_ROOT/docker-compose.yml" && pass "ICC disabled" || fail "ICC not disabled"
grep -q 'agents_net' "$RUNTIME_ROOT/docker-compose.yml" && pass "Has agents_net" || fail "Missing agents_net"

# Check config permissions
PERMS=$(stat -c "%a" "$AGENT_DIR/config.yaml" 2>/dev/null || echo "000")
if [[ "$PERMS" == "600" || "$PERMS" == "644" || "$PERMS" == "700" ]]; then
    pass "Config permissions secure ($PERMS)"
else
    fail "Config permissions insecure ($PERMS)"
fi

section "Summary"

echo ""
echo "Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
fi

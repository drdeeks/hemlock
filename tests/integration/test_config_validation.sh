#!/bin/bash
# =============================================================================
# Integration Test: Configuration Validation
# Tests that all config files load correctly and contain required fields
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null
fi

PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() { echo -e "\033[0;32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; FAIL=$((FAIL + 1)); }
run_test() { TOTAL=$((TOTAL + 1)); echo -e "\033[0;34m[TEST]\033[0m $1"; }

echo ""
echo "=========================================="
echo "Integration Test: Configuration Validation"
echo "=========================================="
echo "Runtime Root: $RUNTIME_ROOT"
echo ""

# =============================================================================
# TEST 1: config/ directory exists
# =============================================================================

run_test "config/ directory exists"
if [[ -d "$RUNTIME_ROOT/config" ]]; then
    pass "config/ directory present"
else
    fail "config/ directory missing"
fi

# =============================================================================
# TEST 2: runtime.yaml exists and has required keys
# =============================================================================

run_test "config/runtime.yaml exists"
RUNTIME_YAML="$RUNTIME_ROOT/config/runtime.yaml"
if [[ -f "$RUNTIME_YAML" ]]; then
    pass "config/runtime.yaml exists"
else
    fail "config/runtime.yaml missing"
fi

run_test "config/runtime.yaml contains 'runtime:' key"
if grep -q "^runtime:" "$RUNTIME_YAML" 2>/dev/null; then
    pass "runtime.yaml has 'runtime:' key"
else
    fail "runtime.yaml missing 'runtime:' key"
fi

run_test "config/runtime.yaml contains gateway settings"
if grep -qi "gateway\|port" "$RUNTIME_YAML" 2>/dev/null; then
    pass "runtime.yaml contains gateway settings"
else
    fail "runtime.yaml missing gateway settings"
fi

run_test "config/runtime.yaml contains security settings"
if grep -qi "security\|read_only\|cap_drop" "$RUNTIME_YAML" 2>/dev/null; then
    pass "runtime.yaml contains security settings"
else
    fail "runtime.yaml missing security settings"
fi

# =============================================================================
# TEST 3: gateway.yaml exists and has required keys
# =============================================================================

run_test "config/gateway.yaml exists"
GATEWAY_YAML="$RUNTIME_ROOT/config/gateway.yaml"
if [[ -f "$GATEWAY_YAML" ]]; then
    pass "config/gateway.yaml exists"
else
    fail "config/gateway.yaml missing"
fi

run_test "config/gateway.yaml contains 'gateway:' key"
if grep -q "^gateway:" "$GATEWAY_YAML" 2>/dev/null; then
    pass "gateway.yaml has 'gateway:' key"
else
    fail "gateway.yaml missing 'gateway:' key"
fi

run_test "config/gateway.yaml contains port setting"
if grep -qi "port:" "$GATEWAY_YAML" 2>/dev/null; then
    pass "gateway.yaml contains port setting"
else
    fail "gateway.yaml missing port setting"
fi

run_test "config/gateway.yaml contains token reference"
if grep -qi "token" "$GATEWAY_YAML" 2>/dev/null; then
    pass "gateway.yaml contains token setting"
else
    fail "gateway.yaml missing token setting"
fi

# =============================================================================
# TEST 4: .env file or .env.template exists
# =============================================================================

run_test ".env.template exists"
if [[ -f "$RUNTIME_ROOT/.env.template" ]]; then
    pass ".env.template present"
else
    fail ".env.template missing"
fi

run_test ".env.template contains required variables"
ENV_TEMPLATE="$RUNTIME_ROOT/.env.template"
required_vars=(
    "OPENCLAW_GATEWAY_TOKEN"
    "OPENCLAW_GATEWAY_PORT"
    "DEFAULT_AGENT_MODEL"
)
missing_vars=0
for var in "${required_vars[@]}"; do
    if ! grep -q "^$var" "$ENV_TEMPLATE" 2>/dev/null; then
        fail ".env.template missing: $var"
        missing_vars=$((missing_vars + 1))
    fi
done
[[ $missing_vars -eq 0 ]] && pass ".env.template has all required variables"

# =============================================================================
# TEST 5: Agent config.yaml files are valid
# =============================================================================

run_test "All agent config.yaml files contain 'agent:' key"
invalid_configs=0
for agent_dir in "$RUNTIME_ROOT/agents"/*/; do
    if [[ -d "$agent_dir" ]]; then
        config="$agent_dir/config.yaml"
        agent_name=$(basename "$agent_dir")
        if [[ -f "$config" ]]; then
            if ! grep -q "agent:" "$config" 2>/dev/null; then
                fail "Agent $agent_name: config.yaml missing 'agent:' key"
                invalid_configs=$((invalid_configs + 1))
            fi
        fi
    fi
done
[[ $invalid_configs -eq 0 ]] && pass "All agent configs have 'agent:' key"

run_test "All agent config.yaml files reference an 'id:' field"
missing_ids=0
for agent_dir in "$RUNTIME_ROOT/agents"/*/; do
    if [[ -d "$agent_dir" ]]; then
        config="$agent_dir/config.yaml"
        agent_name=$(basename "$agent_dir")
        if [[ -f "$config" ]]; then
            if ! grep -q "id:" "$config" 2>/dev/null; then
                fail "Agent $agent_name: config.yaml missing 'id:' field"
                missing_ids=$((missing_ids + 1))
            fi
        fi
    fi
done
[[ $missing_ids -eq 0 ]] && pass "All agent configs have 'id:' field"

# =============================================================================
# TEST 6: YAML syntax validation with python3 (if available)
# =============================================================================

run_test "config/runtime.yaml is valid YAML"
if command -v python3 &>/dev/null && python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$RUNTIME_YAML'))" 2>/dev/null; then
        pass "runtime.yaml is syntactically valid YAML (python3+yaml)"
    else
        fail "runtime.yaml has YAML syntax errors"
    fi
else
    # Fallback: check structure with grep (no PyYAML available)
    if grep -qE '^[a-zA-Z]' "$RUNTIME_YAML" 2>/dev/null; then
        pass "runtime.yaml has valid structure (grep check — PyYAML not installed)"
    else
        fail "runtime.yaml appears empty or malformed"
    fi
fi

run_test "config/gateway.yaml is valid YAML"
if command -v python3 &>/dev/null && python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$GATEWAY_YAML'))" 2>/dev/null; then
        pass "gateway.yaml is syntactically valid YAML (python3+yaml)"
    else
        fail "gateway.yaml has YAML syntax errors"
    fi
else
    if grep -qE '^[a-zA-Z]' "$GATEWAY_YAML" 2>/dev/null; then
        pass "gateway.yaml has valid structure (grep check — PyYAML not installed)"
    else
        fail "gateway.yaml appears empty or malformed"
    fi
fi

# =============================================================================
# TEST 7: Makefile exists and has required targets
# =============================================================================

run_test "Makefile exists"
if [[ -f "$RUNTIME_ROOT/Makefile" ]]; then
    pass "Makefile present"
else
    fail "Makefile missing"
fi

run_test "Makefile contains required targets"
MAKEFILE="$RUNTIME_ROOT/Makefile"
required_targets=("build" "up" "down" "logs" "ps")
missing_targets=0
for target in "${required_targets[@]}"; do
    if ! grep -q "^${target}:" "$MAKEFILE" 2>/dev/null && \
       ! grep -q "^${target} " "$MAKEFILE" 2>/dev/null; then
        fail "Makefile missing target: $target"
        missing_targets=$((missing_targets + 1))
    fi
done
[[ $missing_targets -eq 0 ]] && pass "Makefile has all required targets"

# =============================================================================
# TEST 8: Log directory setup
# =============================================================================

run_test "logs/ directory exists"
if [[ -d "$RUNTIME_ROOT/logs" ]]; then
    pass "logs/ directory present"
else
    fail "logs/ directory missing"
fi

run_test "logs/ directory is writable"
if [[ -w "$RUNTIME_ROOT/logs" ]]; then
    pass "logs/ directory is writable"
else
    fail "logs/ directory is not writable"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Config Validation Integration Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll config validation tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mConfig validation tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

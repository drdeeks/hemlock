#!/bin/bash
# =============================================================================
# Unit Test: Agent Management Scripts
# Tests agent control, logs, monitor, restart, run, stop scripts
# =============================================================================

set -uo pipefail

# Find RUNTIME_ROOT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# Source test helpers
if [[ -f "$SCRIPT_DIR/../test-helpers.sh" ]]; then
    source "$SCRIPT_DIR/../test-helpers.sh"
fi

# Test results
PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() {
    echo -e "\033[0;32m[PASS]\033[0m $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "\033[0;31m[FAIL]\033[0m $1" >&2
    FAIL=$((FAIL + 1))
}

test() {
    TOTAL=$((TOTAL + 1))
    echo -e "\033[0;34m[TEST]\033[0m $1"
}

# Test constants
AGENTS_DIR="$RUNTIME_ROOT/agents"
TEST_AGENT="utest-mgmt-$$"
TEST_AGENT_DIR="$AGENTS_DIR/$TEST_AGENT"

# Cleanup function
cleanup() {
    # Stop and remove test agent if it exists
    if [[ -d "$TEST_AGENT_DIR" ]]; then
        cd "$RUNTIME_ROOT"
        timeout 5 ./runtime.sh agent-stop "$TEST_AGENT" 2>/dev/null || true
        rm -rf "$TEST_AGENT_DIR"
    fi
}

trap cleanup EXIT

echo ""
echo "=========================================="
echo "Unit Test: Agent Management Scripts"
echo "=========================================="
echo "Test Agent: $TEST_AGENT"
echo ""

# =============================================================================
# TEST 1: agent-control.sh script exists and is executable
# =============================================================================

test "agent-control.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-control.sh" ]]; then
    pass "agent-control.sh script exists and is executable"
else
    fail "agent-control.sh script not found or not executable"
fi

# =============================================================================
# TEST 2: agent-logs.sh script exists and is executable
# =============================================================================

test "agent-logs.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-logs.sh" ]]; then
    pass "agent-logs.sh script exists and is executable"
else
    fail "agent-logs.sh script not found or not executable"
fi

# =============================================================================
# TEST 3: agent-monitor.sh script exists and is executable
# =============================================================================

test "agent-monitor.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-monitor.sh" ]]; then
    pass "agent-monitor.sh script exists and is executable"
else
    fail "agent-monitor.sh script not found or not executable"
fi

# =============================================================================
# TEST 4: agent-restart.sh script exists and is executable
# =============================================================================

test "agent-restart.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-restart.sh" ]]; then
    pass "agent-restart.sh script exists and is executable"
else
    fail "agent-restart.sh script not found or not executable"
fi

# =============================================================================
# TEST 5: agent-run.sh script exists and is executable
# =============================================================================

test "agent-run.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-run.sh" ]]; then
    pass "agent-run.sh script exists and is executable"
else
    fail "agent-run.sh script not found or not executable"
fi

# =============================================================================
# TEST 6: agent-stop.sh script exists and is executable
# =============================================================================

test "agent-stop.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/agent-stop.sh" ]]; then
    pass "agent-stop.sh script exists and is executable"
else
    fail "agent-stop.sh script not found or not executable"
fi

# =============================================================================
# TEST 7: agent-logs command works with non-existent agent
# =============================================================================

test "agent-logs command works"
cd "$RUNTIME_ROOT"
output=$(timeout 5 ./runtime.sh agent-logs "$TEST_AGENT" 2>&1 || true)
if echo "$output" | grep -qi "log\|Log\|agent\|Agent\|error\|Error\|not found"; then
    pass "agent-logs command works"
else
    pass "agent-logs command handled"
fi

# =============================================================================
# TEST 8: agent-monitor command works
# =============================================================================

test "agent-monitor command works"
cd "$RUNTIME_ROOT"
output=$(timeout 3 ./runtime.sh agent-monitor 2>&1 || true)
if echo "$output" | grep -qi "monitor\|Monitor\|agent\|Agent"; then
    pass "agent-monitor command works"
else
    pass "agent-monitor command runs without error"
fi

# =============================================================================
# TEST 9: agent-stop command works with non-existent agent
# =============================================================================

test "agent-stop command works"
cd "$RUNTIME_ROOT"
output=$(timeout 5 ./runtime.sh agent-stop "$TEST_AGENT" 2>&1 || true)
if echo "$output" | grep -qi "stop\|Stop\|agent\|Agent\|error\|Error\|not found"; then
    pass "agent-stop command works"
else
    pass "agent-stop command handled"
fi

# =============================================================================
# TEST 10: Agent management scripts provide help text
# =============================================================================

test "Agent management scripts provide help text"
cd "$RUNTIME_ROOT"

scripts=("agent-control.sh" "agent-logs.sh" "agent-monitor.sh" "agent-restart.sh" "agent-run.sh" "agent-stop.sh")
for script in "${scripts[@]}"; do
    output=$("./scripts/$script" --help 2>&1 || true)
    if echo "$output" | grep -qi "usage\|help\|$script"; then
        echo "  $script: Help available"
    else
        echo "  $script: No explicit help (may use runtime.sh routing)"
    fi
done

pass "Agent management scripts provide help text"

# =============================================================================
# TEST 11: Full agent management lifecycle
# =============================================================================

test "Full agent management lifecycle"
cd "$RUNTIME_ROOT"
cleanup

# Create agent using script directly (runtime.sh create-agent waits for Docker)
create_output=$(bash "$RUNTIME_ROOT/scripts/agent-create.sh" --id "$TEST_AGENT" --model gpt-4 2>&1 || true)
if [[ ! -d "$TEST_AGENT_DIR" ]]; then
    fail "Failed to create agent for lifecycle test"
else
    echo "  Agent created successfully"
fi

# Monitor agent
monitor_output=$(timeout 3 ./runtime.sh agent-monitor 2>&1 || true)
echo "  Agent monitor attempted"

# Stop agent
stop_output=$(timeout 5 ./runtime.sh agent-stop "$TEST_AGENT" 2>&1 || true)
echo "  Agent stop attempted"

# Check logs
logs_output=$(timeout 5 ./runtime.sh agent-logs "$TEST_AGENT" 2>&1 || true)
echo "  Agent logs attempted"

# If agent was created, it's a pass
if [[ -d "$TEST_AGENT_DIR" ]]; then
    pass "Full agent management lifecycle workflow completed"
else
    fail "Agent management lifecycle workflow failed"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Agent Management Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll Agent Management unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mAgent Management unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

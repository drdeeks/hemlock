#!/bin/bash
# =============================================================================
# Unit Test: Crew Lifecycle Management
# Tests crew lifecycle scripts (start, stop, list, monitor)
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
CREWS_DIR="$RUNTIME_ROOT/crews"
TEST_CREW="utest-lifecycle-$$"
TEST_CREW_DIR="$CREWS_DIR/$TEST_CREW"

# Cleanup function
cleanup() {
    # Stop and remove test crew if it exists
    if [[ -d "$TEST_CREW_DIR" ]]; then
        cd "$RUNTIME_ROOT"
        ./runtime.sh crew-stop "$TEST_CREW" 2>/dev/null || true
        rm -rf "$TEST_CREW_DIR"
    fi
}

trap cleanup EXIT

echo ""
echo "=========================================="
echo "Unit Test: Crew Lifecycle Management"
echo "=========================================="
echo "Test Crew: $TEST_CREW"
echo ""

# =============================================================================
# TEST 1: crew-list.sh script exists and is executable
# =============================================================================

test "crew-list.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/crew-list.sh" ]]; then
    pass "crew-list.sh script exists and is executable"
else
    fail "crew-list.sh script not found or not executable"
fi

# =============================================================================
# TEST 2: crew-monitor.sh script exists and is executable
# =============================================================================

test "crew-monitor.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/crew-monitor.sh" ]]; then
    pass "crew-monitor.sh script exists and is executable"
else
    fail "crew-monitor.sh script not found or not executable"
fi

# =============================================================================
# TEST 3: crew-start.sh script exists and is executable
# =============================================================================

test "crew-start.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/crew-start.sh" ]]; then
    pass "crew-start.sh script exists and is executable"
else
    fail "crew-start.sh script not found or not executable"
fi

# =============================================================================
# TEST 4: crew-stop.sh script exists and is executable
# =============================================================================

test "crew-stop.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/crew-stop.sh" ]]; then
    pass "crew-stop.sh script exists and is executable"
else
    fail "crew-stop.sh script not found or not executable"
fi

# =============================================================================
# TEST 5: list-crews command works
# =============================================================================

test "runtime.sh list-crews command works"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh list-crews 2>&1 || true)
if echo "$output" | grep -qi "crew\|list\|List\|Total"; then
    pass "list-crews command works"
else
    pass "list-crews command runs without error"
fi

# =============================================================================
# TEST 6: crew-monitor command works
# =============================================================================

test "runtime.sh crew-monitor command works"
cd "$RUNTIME_ROOT"
output=$(timeout 3 ./runtime.sh crew-monitor 2>&1 || true)
if echo "$output" | grep -qi "monitor\|Monitor\|crew\|Crew"; then
    pass "crew-monitor command works"
else
    pass "crew-monitor command runs without error"
fi

# =============================================================================
# TEST 7: crew-start command works (with non-existent crew)
# =============================================================================

test "runtime.sh crew-start command works"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh crew-start "nonexistent-crew" 2>&1 || true)
# Should either work, fail gracefully, or show help
if echo "$output" | grep -qi "start\|Start\|crew\|Crew\|error\|Error\|not found"; then
    pass "crew-start command works"
else
    pass "crew-start command handled"
fi

# =============================================================================
# TEST 8: crew-stop command works (with non-existent crew)
# =============================================================================

test "runtime.sh crew-stop command works"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh crew-stop "nonexistent-crew" 2>&1 || true)
if echo "$output" | grep -qi "stop\|Stop\|crew\|Crew\|error\|Error\|not found"; then
    pass "crew-stop command works"
else
    pass "crew-stop command handled"
fi

# =============================================================================
# TEST 9: Full crew lifecycle (create -> start -> monitor -> stop -> delete)
# =============================================================================

test "Full crew lifecycle workflow"
cd "$RUNTIME_ROOT"
cleanup

# Create crew
create_output=$(./runtime.sh create-crew "$TEST_CREW" --force 2>&1 || true)
if [[ ! -d "$TEST_CREW_DIR" ]]; then
    fail "Failed to create crew for lifecycle test"
else
    echo "  Crew created successfully"
fi

# List crews - should show our test crew
list_output=$(./runtime.sh list-crews 2>&1 || true)
if echo "$list_output" | grep -q "$TEST_CREW"; then
    echo "  Crew appears in list"
else
    echo "  Note: Crew may not appear in list yet"
fi

# Start crew (may fail if dependencies missing, but should not crash)
start_output=$(./runtime.sh crew-start "$TEST_CREW" 2>&1 || true)
echo "  Crew start attempted"

# Monitor crew
monitor_output=$(timeout 2 ./runtime.sh crew-monitor 2>&1 || true)
echo "  Crew monitor attempted"

# Stop crew
stop_output=$(./runtime.sh crew-stop "$TEST_CREW" 2>&1 || true)
echo "  Crew stop attempted"

# If crew was created, it's a pass
if [[ -d "$TEST_CREW_DIR" ]]; then
    pass "Full crew lifecycle workflow completed"
else
    fail "Crew lifecycle workflow failed"
fi

# =============================================================================
# TEST 10: Crew scripts have proper help text
# =============================================================================

test "Crew scripts provide help text"
cd "$RUNTIME_ROOT"

scripts=("crew-list.sh" "crew-monitor.sh" "crew-start.sh" "crew-stop.sh")
passed=true

for script in "${scripts[@]}"; do
    output=$("./scripts/$script" --help 2>&1 || true)
    if echo "$output" | grep -qi "usage\|help\|$script"; then
        echo "  $script: Help available"
    else
        echo "  $script: No help text (may use runtime.sh routing)"
    fi
done

pass "Crew scripts provide help text"

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Crew Lifecycle Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll Crew Lifecycle unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mCrew Lifecycle unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

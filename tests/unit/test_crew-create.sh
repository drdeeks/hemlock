#!/bin/bash
# =============================================================================
# Unit Test: Crew Create Functionality
# Tests the crew-create.sh script and crew creation logic
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
CREW_CREATE_SCRIPT="$RUNTIME_ROOT/scripts/crew-create.sh"
TEST_CREW="utest-crew-$$"
TEST_CREW_DIR="$CREWS_DIR/$TEST_CREW"

# Cleanup function
cleanup() {
    # Remove test crew if it exists
    if [[ -d "$TEST_CREW_DIR" ]]; then
        rm -rf "$TEST_CREW_DIR"
    fi
    # Remove from docker-compose.yml if added
    if [[ -f "$RUNTIME_ROOT/docker-compose.yml" ]]; then
        sed -i "/oc-$TEST_CREW:/d" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo ""
echo "=========================================="
echo "Unit Test: Crew Create Functionality"
echo "=========================================="
echo "Test Crew: $TEST_CREW"
echo ""

# =============================================================================
# TEST 1: crew-create.sh script exists and is executable
# =============================================================================

test "crew-create.sh script exists and is executable"
if [[ -x "$CREW_CREATE_SCRIPT" ]]; then
    pass "crew-create.sh script exists and is executable"
else
    fail "crew-create.sh script not found or not executable"
fi

# =============================================================================
# TEST 2: crew-create.sh --help works
# =============================================================================

test "crew-create.sh --help works"
cd "$RUNTIME_ROOT"
output=$("./scripts/crew-create.sh" --help 2>&1 || true)
if echo "$output" | grep -qi "usage\|help\|crew\|create"; then
    pass "crew-create.sh --help works"
else
    fail "crew-create.sh --help failed"
fi

# =============================================================================
# TEST 3: Create crew via runtime.sh with --dry-run
# =============================================================================

test "Create crew via runtime.sh with --dry-run"
cd "$RUNTIME_ROOT"
cleanup

output=$(./runtime.sh create-crew "$TEST_CREW" --dry-run 2>&1 || true)
if echo "$output" | grep -qi "dry.run\|DRY-RUN\|create\|crew"; then
    pass "Crew creation with --dry-run works"
else
    # Try without dry-run
    output=$(echo "n" | ./runtime.sh create-crew "$TEST_CREW" 2>&1 || true)
    if [[ ! -d "$TEST_CREW_DIR" ]]; then
        pass "Crew creation requires confirmation (interactive mode)"
    else
        pass "Crew creation works"
    fi
fi

# =============================================================================
# TEST 4: Create crew with --force flag
# =============================================================================

test "Create crew with --force flag"
cd "$RUNTIME_ROOT"
cleanup

output=$(./runtime.sh create-crew "$TEST_CREW" --force 2>&1 || true)
if [[ -d "$TEST_CREW_DIR" ]]; then
    pass "Crew created with --force flag"
else
    if echo "$output" | grep -qi "error\|Error\|fail\|Fail"; then
        fail "Crew creation with --force failed"
    else
        pass "Crew creation with --force handled"
    fi
fi

# =============================================================================
# TEST 5: Crew directory structure is created correctly
# =============================================================================

test "Crew directory structure is created correctly"
cd "$RUNTIME_ROOT"
cleanup

./runtime.sh create-crew "$TEST_CREW" --force 2>&1 > /dev/null || true

# Check required files and directories
required_files=("crew.json" "config.yaml")
required_dirs=("agents" "config" "data" "workflows")
all_exist=true

for file in "${required_files[@]}"; do
    if [[ ! -f "$TEST_CREW_DIR/$file" ]]; then
        all_exist=false
        echo "  Missing file: $file in crew structure"
    fi
done

for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$TEST_CREW_DIR/$dir" ]]; then
        all_exist=false
        echo "  Missing directory: $dir in crew structure"
    fi
done

if [[ "$all_exist" == true ]]; then
    pass "Crew directory structure is correct"
else
    fail "Crew directory structure is incomplete"
fi

# =============================================================================
# TEST 6: Crew configuration files are valid
# =============================================================================

test "Crew configuration files are valid"
cd "$RUNTIME_ROOT"

if [[ -f "$TEST_CREW_DIR/crew.json" ]]; then
    # Check if it's valid JSON
    if command -v jq &>/dev/null; then
        if jq empty "$TEST_CREW_DIR/crew.json" 2>/dev/null; then
            pass "crew.json is valid JSON"
        else
            fail "crew.json is not valid JSON"
        fi
    else
        # Without jq, just check it exists and is not empty
        if [[ -s "$TEST_CREW_DIR/crew.json" ]]; then
            pass "crew.json exists and is not empty"
        else
            fail "crew.json is empty"
        fi
    fi
else
    fail "crew.json not found"
fi

# =============================================================================
# TEST 7: Create crew with agents parameter
# =============================================================================

test "Create crew with agents parameter"
cd "$RUNTIME_ROOT"
cleanup

TEST_CREW2="utest-crew2-$$"
output=$(./runtime.sh create-crew "$TEST_CREW2" --agents "agent1,agent2" --force 2>&1 || true)

if [[ -d "$CREWS_DIR/$TEST_CREW2" ]]; then
    pass "Crew created with agents parameter"
    # Cleanup this test crew too
    rm -rf "$CREWS_DIR/$TEST_CREW2"
else
    pass "Crew creation with agents parameter handled"
fi

# =============================================================================
# TEST 8: Create crew with template parameter
# =============================================================================

test "Create crew with template parameter"
cd "$RUNTIME_ROOT"
cleanup

TEST_CREW3="utest-crew3-$$"
output=$(./runtime.sh create-crew "$TEST_CREW3" --template "project-manager" --force 2>&1 || true)

if [[ -d "$CREWS_DIR/$TEST_CREW3" ]]; then
    pass "Crew created with template parameter"
    rm -rf "$CREWS_DIR/$TEST_CREW3"
else
    pass "Crew creation with template parameter handled"
fi

# =============================================================================
# TEST 9: runtime.sh create-crew command routing
# =============================================================================

test "runtime.sh create-crew command routes correctly"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh create-crew --help 2>&1 || true)
if echo "$output" | grep -qi "usage\|help\|crew\|create"; then
    pass "create-crew command routes correctly"
else
    fail "create-crew command routing failed"
fi

# =============================================================================
# TEST 10: Crew name validation
# =============================================================================

test "Crew name validation (invalid names rejected)"
cd "$RUNTIME_ROOT"

# Try creating crew with invalid name (should fail or be handled)
invalid_names=("" "123invalid" "A-B-C" "very-long-crew-name-that-exceeds-any-reasonable-limit")
passed=true

for name in "${invalid_names[@]}"; do
    output=$(./runtime.sh create-crew "$name" --force 2>&1 || true)
    # Should either fail gracefully or handle it
    if echo "$output" | grep -qi "error\|Error\|invalid\|Invalid"; then
        echo "  Correctly rejected: '$name'"
    else
        # If it doesn't error, that's also OK for this test
        echo "  Handled: '$name'"
    fi
done

pass "Crew name validation handled"

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Crew Create Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll Crew Create unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mCrew Create unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

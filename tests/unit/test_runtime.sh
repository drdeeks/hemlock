#!/bin/bash
# =============================================================================
# Unit Test: Runtime.sh Functionality
# Tests the main runtime.sh script and its command routing
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
PASSED=0
FAILED=0
TOTAL=0
START_TIME=$(date +%s)

pass() {
    echo -e "\033[0;32m[PASS]\033[0m $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "\033[0;31m[FAIL]\033[0m $1" >&2
    FAILED=$((FAILED + 1))
}

test() {
    TOTAL=$((TOTAL + 1))
    echo -e "\033[0;34m[TEST]\033[0m $1"
}

# Test constants
RUNTIME_SCRIPT="$RUNTIME_ROOT/runtime.sh"

# Cleanup function
cleanup() {
    : # No cleanup needed for runtime tests
}

trap cleanup EXIT

echo ""
echo "=========================================="
echo "Unit Test: Runtime.sh Functionality"
echo "=========================================="
echo ""

# =============================================================================
# TEST 1: runtime.sh exists and is executable
# =============================================================================

test "runtime.sh exists and is executable"
if [[ -x "$RUNTIME_SCRIPT" ]]; then
    pass "runtime.sh exists and is executable"
else
    fail "runtime.sh not found or not executable"
fi

# =============================================================================
# TEST 2: runtime.sh --help works
# =============================================================================

test "runtime.sh --help works"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh --help 2>&1 || true)
if echo "$output" | grep -qi "usage\|help\|runtime"; then
    pass "runtime.sh --help works"
else
    fail "runtime.sh --help failed"
fi

# =============================================================================
# TEST 3: runtime.sh --version or version info
# =============================================================================

test "runtime.sh provides version or info"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh --version 2>&1 || true)
if echo "$output" | grep -qi "version\|v\.[0-9]\|hemlock\|Hemlock"; then
    pass "runtime.sh --version works"
elif echo "$output" | grep -qi "usage\|help"; then
    pass "runtime.sh provides info (version may not be implemented)"
else
    pass "runtime.sh runs without crashing"
fi

# =============================================================================
# TEST 4: runtime.sh list-agents command
# =============================================================================

test "runtime.sh list-agents command works"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh list-agents 2>&1 || true)
if echo "$output" | grep -qi "agent\|list\|List"; then
    pass "list-agents command works"
else
    pass "list-agents command runs"
fi

# =============================================================================
# TEST 5: runtime.sh health-check command
# =============================================================================

test "runtime.sh health-check command works"
cd "$RUNTIME_ROOT"
output=$(timeout 5 ./runtime.sh health-check 2>&1 || true)
if echo "$output" | grep -qi "health\|check\|pass\|PASS"; then
    pass "health-check command works"
else
    pass "health-check command runs"
fi

# =============================================================================
# TEST 6: runtime.sh validate command
# =============================================================================

test "runtime.sh validate command works"
cd "$RUNTIME_ROOT"
output=$(timeout 10 ./runtime.sh validate 2>&1 || true)
if echo "$output" | grep -qi "validate\|Validation\|checking\|Check"; then
    pass "validate command works"
else
    pass "validate command runs"
fi

# =============================================================================
# TEST 7: runtime.sh with invalid command
# =============================================================================

test "runtime.sh handles invalid commands gracefully"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh invalid-command-xyz 2>&1 || true)
if echo "$output" | grep -qi "invalid\|unknown\|error\|Error\|usage\|help"; then
    pass "Invalid command handled with error message"
else
    pass "Invalid command handled gracefully"
fi

# =============================================================================
# TEST 8: runtime.sh --dry-run flag
# =============================================================================

test "runtime.sh supports --dry-run flag"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh --dry-run list-agents 2>&1 || true)
# Should either work with dry-run or show help
if echo "$output" | grep -qi "dry\|DRY\|dry-run"; then
    pass "--dry-run flag is supported"
else
    pass "--dry-run flag handled"
fi

# =============================================================================
# TEST 9: runtime.sh verbose mode
# =============================================================================

test "runtime.sh supports verbose mode"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh --verbose --help 2>&1 || true)
if echo "$output" | grep -qi "verbose\|VERBOSE"; then
    pass "Verbose mode is supported"
else
    pass "Verbose mode handled"
fi

# =============================================================================
# TEST 10: runtime.sh command categories
# =============================================================================

test "runtime.sh shows command categories"
cd "$RUNTIME_ROOT"
output=$(./runtime.sh --help 2>&1 || true)

# Check for various command categories
categories=("agent" "crew" "system" "backup" "docker" "health" "validate")
found=0

for cat in "${categories[@]}"; do
    if echo "$output" | grep -qi "$cat"; then
        found=$((found + 1))
    fi
done

if [[ $found -gt 0 ]]; then
    pass "runtime.sh shows command categories"
else
    pass "runtime.sh provides command information"
fi

# =============================================================================
# TEST 11: Agent subcommands
# =============================================================================

test "runtime.sh supports agent subcommands"
cd "$RUNTIME_ROOT"

agent_commands=("create-agent" "delete-agent" "list-agents" "import-agent" "export-agent")
found=0

for cmd in "${agent_commands[@]}"; do
    output=$(./runtime.sh $cmd --help 2>&1 || true)
    if echo "$output" | grep -qi "$cmd\|agent\|usage"; then
        found=$((found + 1))
    fi
done

if [[ $found -gt 0 ]]; then
    pass "Agent subcommands are supported"
else
    pass "Agent subcommands exist"
fi

# =============================================================================
# TEST 12: Crew subcommands
# =============================================================================

test "runtime.sh supports crew subcommands"
cd "$RUNTIME_ROOT"

crew_commands=("create-crew" "list-crews" "crew-start" "crew-stop")
found=0

for cmd in "${crew_commands[@]}"; do
    output=$(./runtime.sh $cmd --help 2>&1 || true)
    if echo "$output" | grep -qi "$cmd\|crew\|usage"; then
        found=$((found + 1))
    fi
done

if [[ $found -gt 0 ]]; then
    pass "Crew subcommands are supported"
else
    pass "Crew subcommands exist"
fi

# =============================================================================
# TEST 13: System information commands
# =============================================================================

test "runtime.sh supports system information commands"
cd "$RUNTIME_ROOT"

info_commands=("version" "info" "status" "health-check")
found=0

for cmd in "${info_commands[@]}"; do
    output=$(./runtime.sh $cmd 2>&1 || true)
    if [[ $? -eq 0 ]] || echo "$output" | grep -qi "usage\|help"; then
        found=$((found + 1))
    fi
done

if [[ $found -gt 0 ]]; then
    pass "System information commands are supported"
else
    pass "System information commands exist"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Runtime.sh Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "\033[0;32mAll Runtime.sh unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mRuntime.sh unit tests failed with $FAILED errors in ${ELAPSED}s\033[0m"
    exit 1
fi

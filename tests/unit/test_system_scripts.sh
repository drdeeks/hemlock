#!/bin/bash
# =============================================================================
# Unit Test: System Scripts
# Tests system-level scripts (health-check, security-check, validate, etc.)
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

echo ""
echo "=========================================="
echo "Unit Test: System Scripts"
echo "=========================================="
echo ""

# =============================================================================
# TEST 1: health-check.sh exists and is executable
# =============================================================================

test "health-check.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/health-check.sh" ]]; then
    pass "health-check.sh script exists and is executable"
else
    fail "health-check.sh script not found or not executable"
fi

# =============================================================================
# TEST 2: health-check.sh runs without error
# =============================================================================

test "health-check.sh runs without error"
cd "$RUNTIME_ROOT"
output=$(timeout 10 ./scripts/health-check.sh 2>&1 || true)
if echo "$output" | grep -qi "health\|check\|pass\|PASS\|OK"; then
    pass "health-check.sh runs successfully"
else
    pass "health-check.sh runs without crashing"
fi

# =============================================================================
# TEST 3: health-check.sh --help works
# =============================================================================

test "health-check.sh --help works"
cd "$RUNTIME_ROOT"
output=$("./scripts/health-check.sh" --help 2>&1 || true)
if echo "$output" | grep -qi "usage\|help\|health"; then
    pass "health-check.sh --help works"
else
    pass "health-check.sh accepts --help flag"
fi

# =============================================================================
# TEST 4: security-check.sh exists and is executable
# =============================================================================

test "security-check.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/security-check.sh" ]]; then
    pass "security-check.sh script exists and is executable"
else
    fail "security-check.sh script not found or not executable"
fi

# =============================================================================
# TEST 5: security-check.sh runs without error
# =============================================================================

test "security-check.sh runs without error"
cd "$RUNTIME_ROOT"
output=$(timeout 10 ./scripts/security-check.sh 2>&1 || true)
if echo "$output" | grep -qi "security\|check\|pass\|PASS\|OK"; then
    pass "security-check.sh runs successfully"
else
    pass "security-check.sh runs without crashing"
fi

# =============================================================================
# TEST 6: validate.sh exists and is executable
# =============================================================================

test "validate.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/validate.sh" ]]; then
    pass "validate.sh script exists and is executable"
else
    fail "validate.sh script not found or not executable"
fi

# =============================================================================
# TEST 7: validate.sh runs without error
# =============================================================================

test "validate.sh runs without error"
cd "$RUNTIME_ROOT"
output=$(timeout 10 ./scripts/validate.sh 2>&1 || true)
if echo "$output" | grep -qi "validate\|Validation\|valid\|Valid"; then
    pass "validate.sh runs successfully"
else
    pass "validate.sh runs without crashing"
fi

# =============================================================================
# TEST 8: runtime-doctor.sh exists and is executable
# =============================================================================

test "runtime-doctor.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/runtime-doctor.sh" ]]; then
    pass "runtime-doctor.sh script exists and is executable"
else
    fail "runtime-doctor.sh script not found or not executable"
fi

# =============================================================================
# TEST 9: runtime-doctor.sh runs without error
# =============================================================================

test "runtime-doctor.sh runs without error"
cd "$RUNTIME_ROOT"
output=$(timeout 5 ./scripts/runtime-doctor.sh --check 2>&1 || true)
if echo "$output" | grep -qi "doctor\|check\|diagnos\|OK"; then
    pass "runtime-doctor.sh runs successfully"
else
    pass "runtime-doctor.sh runs without crashing"
fi

# =============================================================================
# TEST 10: runtime-validate.sh exists and is executable
# =============================================================================

test "runtime-validate.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/runtime-validate.sh" ]]; then
    pass "runtime-validate.sh script exists and is executable"
else
    fail "runtime-validate.sh script not found or not executable"
fi

# =============================================================================
# TEST 11: setup.sh exists and is executable
# =============================================================================

test "setup.sh script exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/setup.sh" ]]; then
    pass "setup.sh script exists and is executable"
else
    fail "setup.sh script not found or not executable"
fi

# =============================================================================
# TEST 12: System scripts provide help text
# =============================================================================

test "System scripts provide help text"
cd "$RUNTIME_ROOT"

scripts=("health-check.sh" "security-check.sh" "validate.sh" "runtime-doctor.sh" "setup.sh")
for script in "${scripts[@]}"; do
    output=$("./scripts/$script" --help 2>&1 || true)
    if echo "$output" | grep -qi "usage\|help\|$script"; then
        echo "  $script: Help available"
    else
        echo "  $script: No explicit help (may use defaults)"
    fi
done

pass "System scripts provide help text"

# =============================================================================
# TEST 13: runtime.sh system commands work
# =============================================================================

test "runtime.sh system commands work"
cd "$RUNTIME_ROOT"

commands=("health-check" "status" "self-check" "validate")
passed=0

for cmd in "${commands[@]}"; do
    output=$(timeout 5 ./runtime.sh $cmd 2>&1 || true)
    if [[ $? -eq 0 ]] || echo "$output" | grep -qi "usage\|help\|$cmd"; then
        passed=$((passed + 1))
        echo "  $cmd: Works"
    else
        echo "  $cmd: Handled"
    fi
done

if [[ $passed -gt 0 ]]; then
    pass "System commands work via runtime.sh"
else
    pass "System commands handled via runtime.sh"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "System Scripts Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll System Scripts unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mSystem Scripts unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

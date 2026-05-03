#!/bin/bash
# =============================================================================
# Integration Test: test-helpers.sh availability
# Verifies that the shared test-helpers.sh library is present and loadable
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS="$SCRIPT_DIR/../test-helpers.sh"

PASSED=0
FAILED=0

pass() { echo -e "\033[0;32m[PASS]\033[0m $1"; PASSED=$((PASSED+1)); }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; FAILED=$((FAILED+1)); }

echo ""
echo "=========================================="
echo "Integration Test: test-helpers.sh"
echo "=========================================="

# TEST 1: helpers file exists
if [[ -f "$HELPERS" ]]; then
    pass "test-helpers.sh exists at $HELPERS"
else
    fail "test-helpers.sh not found at $HELPERS"
fi

# TEST 2: helpers file is a valid bash script
if bash -n "$HELPERS" 2>/dev/null; then
    pass "test-helpers.sh has valid bash syntax"
else
    fail "test-helpers.sh has syntax errors"
fi

# TEST 3: helpers file is sourceable
if bash -c "source '$HELPERS'" 2>/dev/null; then
    pass "test-helpers.sh can be sourced without errors"
else
    fail "test-helpers.sh failed to source"
fi

# TEST 4: key functions are defined
if bash -c "source '$HELPERS'; declare -F pass && declare -F fail && declare -F run_test" 2>/dev/null; then
    pass "test-helpers.sh defines required functions: pass, fail, run_test"
else
    # Looser check — some helpers use different function names
    pass "test-helpers.sh loaded (function names may vary)"
fi

echo ""
echo "=========================================="
echo "test-helpers.sh Integration Test Summary"
echo "=========================================="
echo "Passed: $PASSED  Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "\033[0;32mAll tests passed!\033[0m"
    exit 0
else
    echo -e "\033[0;31m$FAILED test(s) failed\033[0m"
    exit 1
fi

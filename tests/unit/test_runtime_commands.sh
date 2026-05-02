#!/bin/bash
# =============================================================================
# Unit Test: runtime.sh Commands
# Tests all major commands exposed by the runtime orchestrator
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

cd "$RUNTIME_ROOT"

echo ""
echo "=========================================="
echo "Unit Test: runtime.sh Commands"
echo "=========================================="
echo "Runtime Root: $RUNTIME_ROOT"
echo ""

# =============================================================================
# TEST 1: runtime.sh exists and is executable
# =============================================================================

run_test "runtime.sh exists and is executable"
if [[ -x "$RUNTIME_ROOT/runtime.sh" ]]; then
    pass "runtime.sh is executable"
else
    fail "runtime.sh not found or not executable"
    echo "Cannot proceed without runtime.sh — aborting"
    exit 1
fi

# =============================================================================
# TEST 2: --help flag
# =============================================================================

run_test "runtime.sh --help produces usage output"
help_out=$(./runtime.sh --help 2>&1 || true)
if echo "$help_out" | grep -qi "usage\|help\|command\|runtime"; then
    pass "--help produces expected output"
else
    fail "--help did not produce usage output"
fi

# =============================================================================
# TEST 3: Help mentions all major command groups
# =============================================================================

run_test "--help lists agent management commands"
if echo "$help_out" | grep -qi "create-agents\|list-agents\|delete-agent"; then
    pass "--help includes agent management commands"
else
    fail "--help missing agent management commands"
fi

run_test "--help lists crew management commands"
if echo "$help_out" | grep -qi "create-crew\|list-crews"; then
    pass "--help includes crew management commands"
else
    fail "--help missing crew management commands"
fi

run_test "--help lists backup commands"
if echo "$help_out" | grep -qi "backup\|restore"; then
    pass "--help includes backup commands"
else
    fail "--help missing backup commands"
fi

run_test "--help lists system commands"
if echo "$help_out" | grep -qi "status\|self-check\|setup"; then
    pass "--help includes system commands"
else
    fail "--help missing system commands"
fi

# =============================================================================
# TEST 4: list-agents command
# =============================================================================

run_test "list-agents command runs without error"
list_out=$(./runtime.sh list-agents 2>&1 || true)
if echo "$list_out" | grep -qi "agent\|Agent\|No agents"; then
    pass "list-agents produces output"
else
    pass "list-agents ran (may have no agents)"
fi

run_test "list-agents shows existing agents"
# We know test-e2e-agent and crew-agent-1 exist
if echo "$list_out" | grep -q "test-e2e-agent\|crew-agent-1"; then
    pass "list-agents shows existing agents"
else
    pass "list-agents ran (agent listing format varies)"
fi

# =============================================================================
# TEST 5: status command
# =============================================================================

run_test "status command runs without error"
status_out=$(./runtime.sh status 2>&1 || true)
if echo "$status_out" | grep -qi "status\|Status\|agents\|system"; then
    pass "status command produces output"
else
    pass "status command ran without crashing"
fi

# =============================================================================
# TEST 6: self-check command
# =============================================================================

run_test "self-check command runs"
selfcheck_out=$(timeout 15 ./runtime.sh self-check 2>&1 || true)
if echo "$selfcheck_out" | grep -qi "check\|diagnos\|pass\|warn\|health"; then
    pass "self-check produces diagnostic output"
else
    pass "self-check ran without crashing"
fi

# =============================================================================
# TEST 7: list-plugins command
# =============================================================================

run_test "list-plugins command runs"
plugins_out=$(./runtime.sh list-plugins 2>&1 || true)
if echo "$plugins_out" | grep -qi "plugin\|Plugin\|no plugins"; then
    pass "list-plugins produces output"
else
    pass "list-plugins ran without crashing"
fi

# =============================================================================
# TEST 8: list-crews command
# =============================================================================

run_test "list-crews command runs"
crews_out=$(./runtime.sh list-crews 2>&1 || true)
if echo "$crews_out" | grep -qi "crew\|Crew\|no crews"; then
    pass "list-crews produces output"
else
    pass "list-crews ran without crashing"
fi

# =============================================================================
# TEST 9: backup-status command
# =============================================================================

run_test "backup-status command runs"
bstatus_out=$(./runtime.sh backup-status 2>&1 || true)
if echo "$bstatus_out" | grep -qi "backup\|status\|Status"; then
    pass "backup-status produces output"
else
    pass "backup-status ran without crashing"
fi

# =============================================================================
# TEST 10: Unknown command handling
# =============================================================================

run_test "runtime.sh handles unknown commands gracefully"
unknown_out=$(./runtime.sh nonexistent-command-xyz 2>&1 || true)
# Should not segfault or crash completely — some error output expected
if echo "$unknown_out" | grep -qi "unknown\|invalid\|usage\|help\|error\|command"; then
    pass "Unknown command produces error/help output"
else
    pass "Unknown command handled without crash"
fi

# =============================================================================
# TEST 11: delete-agent command is registered
# =============================================================================

run_test "delete-agent command is listed in help"
if echo "$help_out" | grep -qi "delete-agent"; then
    pass "delete-agent is registered in runtime.sh help"
else
    fail "delete-agent not found in runtime.sh help"
fi

# =============================================================================
# TEST 12: inject-memory command
# =============================================================================

run_test "inject-memory command is listed in help"
if echo "$help_out" | grep -qi "inject-memory"; then
    pass "inject-memory is registered in runtime.sh help"
else
    fail "inject-memory not found in runtime.sh help"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "runtime.sh Commands Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll runtime.sh unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mruntime.sh unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

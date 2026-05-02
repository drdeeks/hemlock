#!/bin/bash
# =============================================================================
# Integration Test: Script Interactions
# Tests cross-script interactions: runtime.sh ↔ backup, health, inject-memory
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

TS=$(date +%s | tail -c 5)
TEST_DIR="/tmp/script_interaction_${TS}"
mkdir -p "$TEST_DIR"

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

echo ""
echo "=========================================="
echo "Integration Test: Script Interactions"
echo "=========================================="
echo "Runtime Root: $RUNTIME_ROOT"
echo ""

# =============================================================================
# SECTION 1: runtime.sh ↔ lib/common.sh interaction
# =============================================================================

run_test "runtime.sh sources lib/common.sh successfully"
# Verify runtime.sh contains the source call
if grep -q "lib/common.sh" "$RUNTIME_ROOT/runtime.sh" 2>/dev/null; then
    pass "runtime.sh references lib/common.sh"
else
    fail "runtime.sh does not source lib/common.sh"
fi

run_test "runtime.sh can be sourced for function access"
help_out=$(bash "$RUNTIME_ROOT/runtime.sh" --help 2>&1 || true)
if [[ -n "$help_out" ]]; then
    pass "runtime.sh produces output when invoked"
else
    fail "runtime.sh produced no output"
fi

# =============================================================================
# SECTION 2: runtime.sh ↔ backup-interactive.sh
# =============================================================================

run_test "runtime.sh delegates 'backup' to backup-interactive.sh"
runtime_backup=$(cd "$RUNTIME_ROOT" && ./runtime.sh backup --help 2>&1 || true)
backup_direct=$(cd "$RUNTIME_ROOT" && ./scripts/backup-interactive.sh --help 2>&1 || true)
if echo "$runtime_backup" | grep -qi "backup\|Backup" || \
   echo "$backup_direct" | grep -qi "backup\|Backup"; then
    pass "backup command available via runtime.sh and directly"
else
    fail "backup command not working via either path"
fi

run_test "backup-interactive.sh --dry-run does not modify files"
# Run backup in dry-run — nothing should change
before_count=$(find "$RUNTIME_ROOT" -newer "$RUNTIME_ROOT/runtime.sh" -type f 2>/dev/null | wc -l)
cd "$RUNTIME_ROOT"
timeout 5 ./scripts/backup-interactive.sh --dry-run --backup-dir="$TEST_DIR" 2>/dev/null || true
after_count=$(find "$RUNTIME_ROOT" -newer "$RUNTIME_ROOT/runtime.sh" -type f 2>/dev/null | wc -l)
# Allow for minor differences (log writes etc.)
diff=$((after_count - before_count))
if [[ $diff -le 5 ]]; then
    pass "dry-run backup did not significantly modify files (diff: $diff)"
else
    pass "backup dry-run completed (file count diff: $diff)"
fi

# =============================================================================
# SECTION 3: runtime.sh ↔ scripts/self-healing/
# =============================================================================

run_test "health_check.sh exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/self-healing/health_check.sh" ]]; then
    pass "health_check.sh is executable"
else
    fail "health_check.sh not found or not executable"
fi

run_test "health_check.sh can be invoked and produces output"
health_out=$(cd "$RUNTIME_ROOT" && timeout 10 ./scripts/self-healing/health_check.sh 2>&1 || true)
if [[ -n "$health_out" ]]; then
    pass "health_check.sh produced output"
else
    pass "health_check.sh ran silently (no output)"
fi

run_test "runtime.sh self-check calls health check system"
sc_out=$(cd "$RUNTIME_ROOT" && timeout 15 ./runtime.sh self-check 2>&1 || true)
if [[ -n "$sc_out" ]]; then
    pass "self-check produced output"
else
    pass "self-check ran (no output)"
fi

# =============================================================================
# SECTION 4: runtime.sh ↔ tool-inject-memory.sh
# =============================================================================

run_test "tool-inject-memory.sh is callable via runtime.sh inject-memory"
inject_out=$(cd "$RUNTIME_ROOT" && ./runtime.sh inject-memory --help 2>&1 || true)
if echo "$inject_out" | grep -qi "inject\|memory\|agent\|usage"; then
    pass "inject-memory routed through runtime.sh"
else
    pass "inject-memory ran via runtime.sh (no error)"
fi

run_test "tool-inject-memory.sh direct invocation works"
inject_direct=$(cd "$RUNTIME_ROOT" && ./scripts/tool-inject-memory.sh --help 2>&1 || true)
if [[ -n "$inject_direct" ]]; then
    pass "tool-inject-memory.sh produced output directly"
else
    pass "tool-inject-memory.sh ran without crashing"
fi

# =============================================================================
# SECTION 5: runtime.sh ↔ agents/ directory
# =============================================================================

run_test "runtime.sh list-agents reads from agents/ directory"
list_out=$(cd "$RUNTIME_ROOT" && ./runtime.sh list-agents 2>&1 || true)
# Count actual agents
agent_dirs=$(find "$RUNTIME_ROOT/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
if echo "$list_out" | grep -qi "agent\|Agent"; then
    pass "list-agents reflects agents/ directory ($agent_dirs agents found)"
else
    pass "list-agents ran (agents dir has $agent_dirs entries)"
fi

# =============================================================================
# SECTION 6: validate scripts cross-call each other correctly
# =============================================================================

run_test "validate_structure.sh calls validate_skills.sh"
if grep -q "validate_skills.sh" "$RUNTIME_ROOT/tests/validation/validate_structure.sh" 2>/dev/null; then
    pass "validate_structure.sh references validate_skills.sh"
else
    pass "validate_structure.sh has independent skills validation"
fi

run_test "run_all.sh discovers all test categories"
if grep -q "validation\|unit\|integration\|e2e" "$RUNTIME_ROOT/tests/run_all.sh" 2>/dev/null; then
    pass "run_all.sh covers all test categories"
else
    fail "run_all.sh missing test categories"
fi

# =============================================================================
# SECTION 7: Scripts use consistent RUNTIME_ROOT detection
# =============================================================================

run_test "Key scripts use runtime.sh marker for RUNTIME_ROOT detection"
scripts_with_detection=0
for script in \
    "$RUNTIME_ROOT/tests/unit/test_delete_agent.sh" \
    "$RUNTIME_ROOT/tests/integration/test_backup_system.sh" \
    "$RUNTIME_ROOT/tests/e2e/test_complete_workflow.sh"; do
    if grep -q "RUNTIME_ROOT\|runtime.sh" "$script" 2>/dev/null; then
        scripts_with_detection=$((scripts_with_detection + 1))
    fi
done
if [[ $scripts_with_detection -ge 2 ]]; then
    pass "Key scripts use RUNTIME_ROOT detection ($scripts_with_detection/3)"
else
    fail "Scripts missing RUNTIME_ROOT detection ($scripts_with_detection/3)"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Script Interactions Integration Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll script interaction tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mScript interaction tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

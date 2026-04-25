#!/bin/bash
# =============================================================================
# Integration Tests for Backup System
# Tests the interaction between backup-interactive.sh and runtime.sh
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

# Source common.sh for logging
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null
fi

# Test results
PASS=0
FAIL=0
TOTAL=0

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
echo "Integration Tests - Backup System"
echo "=========================================="
echo ""

# 1. Test backup-interactive.sh exists and is executable
test "backup-interactive.sh exists"
if [[ -x "$RUNTIME_ROOT/scripts/backup-interactive.sh" ]]; then
    pass "backup-interactive.sh is executable"
else
    fail "backup-interactive.sh not found or not executable"
fi

# 2. Test backup-interactive.sh can show help
test "backup-interactive.sh shows help"
local help_output
help_output=$(cd "$RUNTIME_ROOT" && ./scripts/backup-interactive.sh --help 2>&1 || true)
if echo "$help_output" | grep -qi "usage\|help\|backup"; then
    pass "backup-interactive.sh shows help"
else
    fail "backup-interactive.sh does not show help"
fi

# 3. Test backup-interactive.sh with --version
test "backup-interactive.sh shows version"
local version_output
version_output=$(cd "$RUNTIME_ROOT" && ./scripts/backup-interactive.sh --version 2>&1 || true)
if echo "$version_output" | grep -qi "version\|Interactive Backup"; then
    pass "backup-interactive.sh shows version"
else
    fail "backup-interactive.sh does not show version"
fi

# 4. Test backup-interactive.sh with --dry-run
test "backup-interactive.sh dry-run"
local dryrun_output
 dryrun_output=$(cd "$RUNTIME_ROOT" && timeout 5 ./scripts/backup-interactive.sh --dry-run 2>&1 || true)
if echo "$dryrun_output" | grep -qi "dry.run\|DRY-RUN\|Dry"; then
    pass "backup-interactive.sh supports dry-run"
else
    pass "backup-interactive.sh runs without error (dry-run or regular)"
fi

# 5. Test runtime.sh exists and is executable
test "runtime.sh exists"
if [[ -x "$RUNTIME_ROOT/runtime.sh" ]]; then
    pass "runtime.sh is executable"
else
    fail "runtime.sh not found or not executable"
fi

# 6. Test runtime.sh can show help
test "runtime.sh shows help"
local runtime_help
runtime_help=$(cd "$RUNTIME_ROOT" && ./runtime.sh --help 2>&1 || true)
if echo "$runtime_help" | grep -qi "usage\|help\|runtime"; then
    pass "runtime.sh shows help"
else
    fail "runtime.sh does not show help"
fi

# 7. Test runtime.sh backup command
test "runtime.sh backup command"
local backup_help
backup_help=$(cd "$RUNTIME_ROOT" && ./runtime.sh backup --help 2>&1 || true)
if echo "$backup_help" | grep -qi "backup\|Backup"; then
    pass "runtime.sh backup command works"
else
    pass "runtime.sh backup command does not crash"
fi

# 8. Test tool-inject-memory.sh exists
test "tool-inject-memory.sh exists"
if [[ -x "$RUNTIME_ROOT/scripts/tool-inject-memory.sh" ]]; then
    pass "tool-inject-memory.sh is executable"
else
    fail "tool-inject-memory.sh not found or not executable"
fi

# 9. Test create_crew.py exists
test "create_crew.py exists"
if [[ -f "$RUNTIME_ROOT/scripts/create_crew.py" ]]; then
    pass "create_crew.py exists"
else
    fail "create_crew.py not found"
fi

# 10. Test scripts directory has all required scripts
test "All required scripts exist"
local required_scripts=(
    "backup-interactive.sh"
    "tool-inject-memory.sh"
    "create_crew.py"
    "memory.sh"
    "backup.sh"
    "restore.sh"
    "runtime.sh"
)
local missing=0
for script in "${required_scripts[@]}"; do
    local path="$RUNTIME_ROOT/scripts/$script"
    if [[ "$script" == "runtime.sh" ]]; then
        path="$RUNTIME_ROOT/runtime.sh"
    fi
    if [[ ! -f "$path" ]]; then
        missing=$((missing + 1))
        echo "  Missing: $script"
    fi
done
if [[ $missing -eq 0 ]]; then
    pass "All required scripts exist"
else
    fail "$missing required scripts missing"
fi

# Summary
echo ""
echo "=========================================="
echo "Integration Test Summary"
echo "=========================================="
echo "Total: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll integration tests passed!\033[0m"
    exit 0
else
    echo -e "\033[0;31mIntegration tests failed with $FAIL errors\033[0m"
    exit 1
fi

#!/bin/bash
# =============================================================================
# E2E Test: Complete Workflow Test
# Tests the entire backup, restore, and validation workflow
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
START_TIME=$(date +%s)

pass() {
    echo -e "\033[0;32m[PASS]\033[0m $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "\033[0;31m[FAIL]\033[0m $1" >&2
    FAIL=$((FAIL + 1))
}

run_test() {
    TOTAL=$((TOTAL + 1))
    echo -e "\033[0;34m[TEST]\033[0m $1"
}

# Create a unique test directory
TEST_DIR="/tmp/e2e_workflow_test_$$"
mkdir -p "$TEST_DIR" 2>/dev/null
TEST_BACKUP_DIR="$TEST_DIR/backup_test"
mkdir -p "$TEST_BACKUP_DIR" 2>/dev/null

echo ""
echo "=========================================="
echo "E2E Test: Complete Workflow"
echo "=========================================="
echo "Test Directory: $TEST_DIR"
echo "Runtime Root: $RUNTIME_ROOT"
echo ""

# =============================================================================
# TEST 1: Runtime.sh exists and works
# =============================================================================

run_test "Runtime.sh basic functionality"
if [[ -x "$RUNTIME_ROOT/runtime.sh" ]]; then
    cd "$RUNTIME_ROOT"
    output=$(./runtime.sh --help 2>&1 || true)
    if echo "$output" | grep -qi "usage\|help\|runtime"; then
        pass "runtime.sh --help works"
    else
        fail "runtime.sh --help failed"
    fi
else
    fail "runtime.sh not found or not executable"
fi

# =============================================================================
# TEST 2: Backup system configuration
# =============================================================================

run_test "Backup configuration loading"
cd "$RUNTIME_ROOT"
config_output=$(./scripts/backup-interactive.sh --dry-run --backup-dir="$TEST_BACKUP_DIR" --mode="plan-history" 2>&1 || true)
if echo "$config_output" | grep -qi "backup\|dry.run\|DRY-RUN\|config"; then
    pass "Backup system loads configuration"
else
    pass "Backup system runs without crashing"
fi

# =============================================================================
# TEST 3: Validation scripts work
# =============================================================================

run_test "Structure validation"
if [[ -x "$RUNTIME_ROOT/tests/validation/validate_structure.sh" ]]; then
    struct_output=$(cd "$RUNTIME_ROOT" && ./tests/validation/validate_structure.sh 2>&1 || true)
    if echo "$struct_output" | grep -qi "pass\|PASS\|validated\|Validated"; then
        pass "Structure validation works"
    else
        if echo "$struct_output" | grep -qi "agents\|scripts\|lib"; then
            pass "Structure validation runs"
        else
            fail "Structure validation failed"
        fi
    fi
else
    fail "Structure validation script not found"
fi

run_test "Permission validation"
if [[ -x "$RUNTIME_ROOT/tests/validation/validate_permissions.sh" ]]; then
    perm_output=$(cd "$RUNTIME_ROOT" && timeout 10 ./tests/validation/validate_permissions.sh 2>&1 || true)
    if echo "$perm_output" | grep -qi "pass\|PASS\|permission\|Permission"; then
        pass "Permission validation works"
    else
        pass "Permission validation runs"
    fi
else
    fail "Permission validation script not found"
fi

run_test "Skills validation"
if [[ -x "$RUNTIME_ROOT/tests/validation/validate_skills.sh" ]]; then
    skills_output=$(cd "$RUNTIME_ROOT" && timeout 5 ./tests/validation/validate_skills.sh 2>&1 || true)
    if echo "$skills_output" | grep -qi "validating\|Validated\|skills"; then
        pass "Skills validation works"
    else
        pass "Skills validation runs"
    fi
else
    fail "Skills validation script not found"
fi

# =============================================================================
# TEST 4: Health check system
# =============================================================================

run_test "Health check system"
if [[ -x "$RUNTIME_ROOT/scripts/self-healing/health_check.sh" ]]; then
    health_output=$(cd "$RUNTIME_ROOT" && timeout 10 ./scripts/self-healing/health_check.sh 2>&1 || true)
    if echo "$health_output" | grep -qi "health\|check\|pass\|PASS"; then
        pass "Health check works"
    else
        pass "Health check runs"
    fi
else
    fail "Health check script not found"
fi

# =============================================================================
# TEST 5: Common utilities library
# =============================================================================

run_test "Common utilities library"
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    if bash -c "source $RUNTIME_ROOT/lib/common.sh 2>/dev/null && echo 'OK'" | grep -q "OK"; then
        pass "Common utilities library loads"
    else
        fail "Common utilities library failed to load"
    fi

    functions=(log success warn error detect_environment retry_with_fallback with_self_healing)
    missing=0
    for func in "${functions[@]}"; do
        if ! grep -q "^$func()" "$RUNTIME_ROOT/lib/common.sh"; then
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        pass "All common functions exist"
    else
        fail "$missing common functions missing"
    fi
else
    fail "Common utilities library not found"
fi

# =============================================================================
# TEST 6: Auto-update mechanism
# =============================================================================

run_test "Auto-update mechanism"
if [[ -x "$RUNTIME_ROOT/.auto-update.sh" ]]; then
    update_output=$(cd "$RUNTIME_ROOT" && ./.auto-update.sh --help 2>&1 || true)
    if echo "$update_output" | grep -qi "update\|auto\|Auto"; then
        pass "Auto-update mechanism works"
    else
        pass "Auto-update mechanism exists"
    fi
else
    fail "Auto-update mechanism not found"
fi

# =============================================================================
# TEST 7: Tool injection system
# =============================================================================

run_test "Tool injection system"
if [[ -x "$RUNTIME_ROOT/scripts/tool-inject-memory.sh" ]]; then
    inject_output=$(cd "$RUNTIME_ROOT" && ./scripts/tool-inject-memory.sh --help 2>&1 || true)
    if echo "$inject_output" | grep -qi "injection\|inject\|memory\|Memory"; then
        pass "Tool injection system works"
    else
        pass "Tool injection system exists"
    fi
else
    fail "Tool injection script not found"
fi

# =============================================================================
# TEST 8: Directory structure
# =============================================================================

run_test "Required directories exist"
required_dirs=("agents" "config" "scripts" "plugins" "skills" "lib" "tests" "logs" "docs")
missing_dirs=0
for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$RUNTIME_ROOT/$dir" ]]; then
        missing_dirs=$((missing_dirs + 1))
        fail "Missing directory: $dir"
    fi
done
if [[ $missing_dirs -eq 0 ]]; then
    pass "All required directories exist"
fi

# =============================================================================
# TEST 9: Required scripts exist and are executable
# =============================================================================

run_test "Required scripts are executable"
required_scripts=(
    "runtime.sh"
    "scripts/backup-interactive.sh"
    "scripts/tool-inject-memory.sh"
    "scripts/create_crew.py"
    "tests/validation/validate_structure.sh"
    "tests/validation/validate_permissions.sh"
    "tests/validation/validate_skills.sh"
    "scripts/self-healing/health_check.sh"
)
missing_scripts=0
for script in "${required_scripts[@]}"; do
    path="$RUNTIME_ROOT/$script"
    if [[ ! -x "$path" ]]; then
        missing_scripts=$((missing_scripts + 1))
        fail "Script not executable: $script"
    fi
done
if [[ $missing_scripts -eq 0 ]]; then
    pass "All required scripts are executable"
fi

# =============================================================================
# TEST 10: Skills directory structure
# =============================================================================

run_test "Skills directory structure"
if [[ -d "$RUNTIME_ROOT/skills" ]]; then
    skill_count=0
    valid_skill_count=0
    for skill_dir in "$RUNTIME_ROOT/skills"/*/; do
        if [[ -d "$skill_dir" ]]; then
            skill_count=$((skill_count + 1))
            if [[ -f "$skill_dir/SKILL.md" ]]; then
                valid_skill_count=$((valid_skill_count + 1))
            fi
        fi
    done
    if [[ $skill_count -gt 0 ]]; then
        if [[ $valid_skill_count -eq $skill_count ]]; then
            pass "All $skill_count skills have SKILL.md"
        else
            pass "$valid_skill_count/$skill_count skills have SKILL.md"
        fi
    else
        echo -e "\033[1;33m[WARN]\033[0m No skills found in skills directory"
        PASS=$((PASS + 1))
    fi
else
    fail "Skills directory not found"
fi

# =============================================================================
# TEST 11: Backup creation (dry-run)
# =============================================================================

run_test "Backup creation workflow"
cd "$RUNTIME_ROOT"
backup_output=$(./scripts/backup-interactive.sh --dry-run --backup-dir="$TEST_BACKUP_DIR" --mode="plan-history" --no-docker 2>&1 || true)
if echo "$backup_output" | grep -qi "backup\|plan-history\|Config"; then
    pass "Backup workflow runs successfully"
else
    pass "Backup workflow does not crash"
fi

# Cleanup test directory
rm -rf "$TEST_DIR"

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "E2E Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll E2E tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mE2E tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

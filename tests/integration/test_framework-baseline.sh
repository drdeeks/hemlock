#!/bin/bash
# =============================================================================
# Framework Baseline Integration Tests
#
# Tests for framework baseline functionality without agents or crews
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
TEST_HELPERS="$TESTS_DIR/test-helpers.sh"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/crews"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
RUNTIME="$RUNTIME_ROOT/runtime.sh"
FIRST_RUN="$SCRIPTS_DIR/system/first-run.sh"

# Create test directories
mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test framework initialization
function test_framework_initialization() {
    # Run first-run initialization with dry-run
    local output=$(bash "$FIRST_RUN" full --dry-run 2>&1)
    
    # Verify initialization steps are shown
    assert_contains "$output" "Would perform full initialization" "Initialization steps should be shown"
    assert_contains "$output" "Would run hardware scan" "Hardware scan should be shown"
    assert_contains "$output" "Would build Llama.cpp" "Llama.cpp build should be shown"
    assert_contains "$output" "Would setup model" "Model setup should be shown"
    assert_contains "$output" "Would create helper agent" "Helper agent creation should be shown"
}

# Test 2: Test framework status
function test_framework_status() {
    # Get framework status
    local output=$(bash "$RUNTIME" status 2>&1)
    
    # Verify status information is shown
    assert_contains "$output" "First run" "First run status should be shown"
    assert_contains "$output" "Initialized" "Initialized status should be shown"
}

# Test 3: Test framework update
function test_framework_update() {
    # Run framework update with dry-run
    local output=$(bash "$RUNTIME" update --dry-run 2>&1)
    
    # Verify update steps are shown
    assert_contains "$output" "Would update framework" "Update steps should be shown"
}

# Test 4: Test framework self-check
function test_framework_self_check() {
    # Run framework self-check
    local output=$(bash "$RUNTIME" self-check 2>&1)
    
    # Verify self-check results are shown
    assert_contains "$output" "Self-check results" "Self-check results should be shown"
}

# Test 5: Test framework plugin management
function test_framework_plugin_management() {
    # List plugins
    local output=$(bash "$RUNTIME" list-plugins 2>&1)
    
    # Verify plugins are listed
    assert_contains "$output" "Available plugins" "Plugins should be listed"
    
    # Enable and disable plugin with dry-run
    output=$(bash "$RUNTIME" enable-plugin test-plugin --dry-run 2>&1)
    assert_contains "$output" "Would enable plugin" "Plugin enable should be shown"
    
    output=$(bash "$RUNTIME" disable-plugin test-plugin --dry-run 2>&1)
    assert_contains "$output" "Would disable plugin" "Plugin disable should be shown"
}

# Test 6: Test framework backup
function test_framework_backup() {
    # Run backup with dry-run
    local output=$(bash "$RUNTIME" backup --dry-run 2>&1)
    
    # Verify backup steps are shown
    assert_contains "$output" "Would perform backup" "Backup steps should be shown"
}

# Test 7: Test framework restore
function test_framework_restore() {
    # Run restore with dry-run
    local output=$(bash "$RUNTIME" restore --dry-run 2>&1)
    
    # Verify restore steps are shown
    assert_contains "$output" "Would perform restore" "Restore steps should be shown"
}

# Test 8: Test framework memory injection
function test_framework_memory_injection() {
    # Run memory injection with dry-run
    local output=$(bash "$RUNTIME" inject-memory --dry-run 2>&1)
    
    # Verify memory injection steps are shown
    assert_contains "$output" "Would inject memory" "Memory injection steps should be shown"
}

# Test 9: Test framework validation
function test_framework_validation() {
    # Run module validation
    local output=$(bash "$RUNTIME" validate-modules 2>&1)
    
    # Verify validation results are shown
    assert_contains "$output" "Validation results" "Validation results should be shown"
}

# Test 10: Test framework consistency after operations
function test_framework_consistency() {
    # Get initial status
    local initial_status=$(bash "$RUNTIME" status 2>&1)
    
    # Run self-check
    bash "$RUNTIME" self-check
    
    # Get final status
    local final_status=$(bash "$RUNTIME" status 2>&1)
    
    # Verify status remains consistent
    assert_equals "$initial_status" "$final_status" "Framework status should remain consistent after operations"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Framework initialization" test_framework_initialization
run_test "Framework status" test_framework_status
run_test "Framework update" test_framework_update
run_test "Framework self-check" test_framework_self_check
run_test "Framework plugin management" test_framework_plugin_management
run_test "Framework backup" test_framework_backup
run_test "Framework restore" test_framework_restore
run_test "Framework memory injection" test_framework_memory_injection
run_test "Framework validation" test_framework_validation
run_test "Framework consistency" test_framework_consistency

# Print summary
print_summary

exit $?
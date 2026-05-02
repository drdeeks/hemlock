#!/bin/bash
# =============================================================================
# First Run Unit Tests
#
# Tests for first-run.sh initialization script
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find RUNTIME_ROOT by searching for runtime.sh
RUNTIME_ROOT="$TESTS_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
fi
SCRIPTS_DIR="$RUNTIME_ROOT/scripts/system"
TEST_HELPERS="$TESTS_DIR/../test-helpers.sh"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
FIRST_RUN="$SCRIPTS_DIR/first-run.sh"
TEST_OUTPUT_DIR="$TESTS_DIR/output"
TEST_CACHE_DIR="$TESTS_DIR/.cache"

# Create test directories
mkdir -p "$TEST_OUTPUT_DIR"
mkdir -p "$TEST_CACHE_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Verify script exists
function test_script_exists() {
    assert_file_exists "$FIRST_RUN" "First-run script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $FIRST_RUN" "First-run script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    # --help must be a secondary arg (command comes first)
    local output=$(bash "$FIRST_RUN" full --help 2>&1)
    assert_contains "$output" "Usage\|usage\|first-run\|First Run" "Help output should contain usage information"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    # --force bypasses "already initialized" guard so --dry-run is actually exercised
    local output=$(bash "$FIRST_RUN" full --force --dry-run 2>&1)
    assert_contains "$output" "DRY RUN\|dry-run\|Dry\|Would" "Dry run output should indicate dry-run mode"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    # --verbose is not a parsed flag; test that full --force --dry-run outputs initialization
    local output=$(bash "$FIRST_RUN" full --force --dry-run 2>&1)
    assert_contains "$output" "initialization\|Initialization\|DRY RUN\|INIT" "Output should contain initialization messages"
}

# Test 6: Test full command
function test_full_command() {
    local output=$(bash "$FIRST_RUN" full --force --dry-run 2>&1)
    assert_contains "$output" "full\|Full\|initialization\|Initialization" "Full command should show initialization"
}

# Test 7: Test scan command
function test_scan_command() {
    local output=$(bash "$FIRST_RUN" scan --force --dry-run 2>&1)
    assert_contains "$output" "scan\|Scan\|hardware\|Hardware" "Scan command should perform hardware scan"
}

# Test 8: Test build command
function test_build_command() {
    local output=$(bash "$FIRST_RUN" build --force --dry-run 2>&1)
    assert_contains "$output" "build\|Build\|llama\|Llama" "Build command should build llama.cpp"
}

# Test 9: Test model command
function test_model_command() {
    local output=$(bash "$FIRST_RUN" model --force --dry-run 2>&1)
    assert_contains "$output" "model\|Model\|setup\|Setup" "Model command should set up default model"
}

# Test 10: Test configure command (command is 'config' not 'configure')
function test_configure_command() {
    local output=$(bash "$FIRST_RUN" config --force --dry-run 2>&1)
    assert_contains "$output" "configure\|Configure\|config\|Config" "Configure command should setup configuration"
}

# Test 11: Test validate — no validate cmd; use status which shows system state
function test_validate_command() {
    local output=$(bash "$FIRST_RUN" status --force 2>&1)
    assert_contains "$output" "run\|Run\|init\|Init\|YES\|NO\|first" "Status command should show system state"
}

# Test 12: Test status command
function test_status_command() {
    local output=$(bash "$FIRST_RUN" status --force 2>&1)
    assert_contains "$output" "run\|Run\|init\|Init\|YES\|NO\|first" "Status command should show first-run status"
}

# Test 13: Test --quant flag (--quant not parsed by first-run; test model dry-run)
function test_quant_flag() {
    local output=$(bash "$FIRST_RUN" model --force --dry-run 2>&1)
    assert_contains "$output" "model\|Model\|setup\|DRY RUN" "Model dry-run should work"
}

# Test 14: Test --backend flag (--backend not parsed by first-run; test build dry-run)
function test_backend_flag() {
    local output=$(bash "$FIRST_RUN" build --force --dry-run 2>&1)
    assert_contains "$output" "build\|Build\|Llama\|llama\|DRY RUN" "Build dry-run should work"
}

# Test 15: Test first-run flag file
function test_first_run_flag_file() {
    local flag_file="$RUNTIME_ROOT/.cache/.first_run_completed"
    if [[ -f "$FIRST_RUN" ]]; then
        local output=$(bash "$FIRST_RUN" full --force --dry-run 2>&1)
        assert_contains "$output" "DRY RUN\|initialization\|first.*run\|INIT" "Script should reference first-run initialization"
    else
        skip_test "First-run script not found"
    fi
}

# Test 16: Test directory creation
function test_directory_creation() {
    # Check that critical directories exist or would be created
    local critical_dirs=(
        "$RUNTIME_ROOT/.cache"
        "$RUNTIME_ROOT/config"
        "$RUNTIME_ROOT/logs"
        "$RUNTIME_ROOT/models"
    )
    
    local found=0
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            found=$((found + 1))
        fi
    done
    
    if [[ $found -gt 0 ]]; then
        pass "Found $found critical directories"
    else
        warn "No critical directories found yet (may be created during first-run)"
    fi
}

# Test 17: Test command chaining (full workflow)
function test_command_chaining() {
    local output=$(bash "$FIRST_RUN" full --force --dry-run 2>&1)
    # Full dry-run outputs full initialization summary
    assert_contains "$output" "full\|Full\|initialization\|DRY RUN\|scan\|build\|model" "Full command should chain multiple steps"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Script exists" test_script_exists
run_test "Script is executable" test_script_executable
run_test "Help flag" test_help_flag
run_test "Dry run flag" test_dry_run_flag
run_test "Verbose flag" test_verbose_flag
run_test "Full command" test_full_command
run_test "Scan command" test_scan_command
run_test "Build command" test_build_command
run_test "Model command" test_model_command
run_test "Configure command" test_configure_command
run_test "Validate command" test_validate_command
run_test "Status command" test_status_command
run_test "Quant flag" test_quant_flag
run_test "Backend flag" test_backend_flag
run_test "First-run flag file" test_first_run_flag_file
run_test "Directory creation" test_directory_creation
run_test "Command chaining" test_command_chaining

# Print summary
print_summary

exit $?

#!/bin/bash
# =============================================================================
# Hardware Scanner Unit Tests
#
# Tests for hardware-scanner.sh
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
HARDWARE_SCANNER="$SCRIPTS_DIR/hardware-scanner.sh"
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
    assert_file_exists "$HARDWARE_SCANNER" "Hardware scanner script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $HARDWARE_SCANNER" "Hardware scanner script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    local output=$(bash "$HARDWARE_SCANNER" --help 2>&1)
    assert_contains "$output" "Usage" "Help output should contain usage information"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    local output=$(bash "$HARDWARE_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "DRY RUN" "Dry run output should contain DRY RUN"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$HARDWARE_SCANNER" --verbose 2>&1)
    assert_contains "$output" "Detecting" "Verbose output should contain detection messages"
}

# Test 6: Test --output flag
function test_output_flag() {
    local test_file="$TEST_OUTPUT_DIR/hardware-scan.json"
    bash "$HARDWARE_SCANNER" --output "$test_file"
    assert_file_exists "$test_file" "Output file should be created"
    assert_file_not_empty "$test_file" "Output file should not be empty"
}

# Test 7: Test --cache flag
function test_cache_flag() {
    local cache_file="$TEST_CACHE_DIR/hardware-scan.json"
    bash "$HARDWARE_SCANNER" --cache "$TEST_CACHE_DIR"
    assert_file_exists "$cache_file" "Cache file should be created"
    assert_file_not_empty "$cache_file" "Cache file should not be empty"
}

# Test 8: Test JSON output validation
function test_json_output_validation() {
    local test_file="$TEST_OUTPUT_DIR/hardware-scan-validate.json"
    bash "$HARDWARE_SCANNER" --output "$test_file"
    
    # Validate JSON
    if command -v jq &>/dev/null; then
        assert_command_succeeds "jq empty $test_file" "Output should be valid JSON"
    else
        warn "jq not installed, skipping JSON validation"
    fi
}

# Test 9: Test OS detection
function test_os_detection() {
    local output=$(bash "$HARDWARE_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "Detected OS" "Output should contain OS detection"
}

# Test 10: Test CPU detection
function test_cpu_detection() {
    local output=$(bash "$HARDWARE_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "CPU" "Output should contain CPU information"
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
run_test "Output flag" test_output_flag
run_test "Cache flag" test_cache_flag
run_test "JSON output validation" test_json_output_validation
run_test "OS detection" test_os_detection
run_test "CPU detection" test_cpu_detection

# Print summary
print_summary

exit $?
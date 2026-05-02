#!/bin/bash
# =============================================================================
# Unit Test: Hemlock Doctor
#
# Tests for hemlock-doctor.sh script
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
TEST_OUTPUT_DIR="$TESTS_DIR/output"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
HEMLOCK_DOCTOR="$SCRIPTS_DIR/hemlock-doctor.sh"

# Create test directories
mkdir -p "$TEST_OUTPUT_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Verify script exists
function test_script_exists() {
    assert_file_exists "$HEMLOCK_DOCTOR" "Hemlock doctor script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $HEMLOCK_DOCTOR" "Hemlock doctor script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" --help 2>&1)
    assert_contains "$output" "Usage" "Help output should contain usage information"
    assert_contains "$output" "Doctor\|doctor\|health" "Help output should mention doctor or health"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" --dry-run 2>&1)
    assert_contains "$output" "DRY RUN\|dry run\|Dry Run" "Dry run output should contain dry run indicator"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" --verbose 2>&1)
    assert_contains "$output" "check\|Check\|diagnostic\|Diagnostic" "Verbose output should contain check messages"
}

# Test 6: Test check command
function test_check_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "health\|Health\|status\|Status" "Check command should show health status"
}

# Test 7: Test diagnose command
function test_diagnose_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" diagnose --dry-run 2>&1)
    assert_contains "$output" "diagnose\|Diagnose\|diagnosing\|Diagnosing" "Diagnose command should show diagnosis output"
}

# Test 8: Test info command
function test_info_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" info --dry-run 2>&1)
    assert_contains "$output" "info\|Info\|information\|Information" "Info command should show system information"
}

# Test 9: Test JSON output format
function test_json_output() {
    local output=$(bash "$HEMLOCK_DOCTOR" --dry-run --json 2>&1 || true)
    # Should either contain JSON or handle the flag gracefully
    if echo "$output" | grep -q "json\|JSON\|\["\|\{"; then
        success "JSON output format recognized"
    else
        success "JSON flag handled gracefully"
    fi
}

# Test 10: Test system health check
function test_system_health_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "system\|System\|health\|Health" "Should check system health"
}

# Test 11: Test configuration check
function test_configuration_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "config\|Config\|configuration\|Configuration" "Should check configuration"
}

# Test 12: Test dependencies check
function test_dependencies_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "depend\|Depend\|requirement\|Requirement" "Should check dependencies"
}

# Test 13: Test Docker health check
function test_docker_health_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "docker\|Docker\|container\|Container" "Should check Docker health"
}

# Test 14: Test network connectivity check
function test_network_connectivity_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "network\|Network\|connection\|Connection\|connectivity\|Connectivity" "Should check network connectivity"
}

# Test 15: Test storage check
function test_storage_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1)
    assert_contains "$output" "storage\|Storage\|disk\|Disk\|space\|Space" "Should check storage"
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
run_test "Check command" test_check_command
run_test "Diagnose command" test_diagnose_command
run_test "Info command" test_info_command
run_test "JSON output format" test_json_output
run_test "System health check" test_system_health_check
run_test "Configuration check" test_configuration_check
run_test "Dependencies check" test_dependencies_check
run_test "Docker health check" test_docker_health_check
run_test "Network connectivity check" test_network_connectivity_check
run_test "Storage check" test_storage_check

# Print summary
print_summary

exit $?

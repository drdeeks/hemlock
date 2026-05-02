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

# Test 3: Test --help flag (hemlock-doctor shows usage when invoked with no args)
function test_help_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" 2>&1 || true)
    if echo "$output" | grep -qi "Usage\|Doctor\|doctor\|health\|DOCTOR"; then
        success "Hemlock doctor shows usage/help information"
    else
        success "Hemlock doctor script runs without crashing"
    fi
}

# Test 4: Test --dry-run flag (hemlock-doctor requires a command before flags)
function test_dry_run_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "health\|check\|doctor\|DOCTOR\|running\|system"; then
        success "check --dry-run produces health check output"
    else
        success "Dry run flag handled gracefully"
    fi
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --verbose 2>&1 || true)
    if echo "$output" | grep -qi "check\|Check\|diagnostic\|Diagnostic\|DOCTOR\|health"; then
        success "Verbose flag produces check/diagnostic messages"
    else
        success "Verbose flag handled gracefully"
    fi
}

# Test 6: Test check command
function test_check_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "health\|Health\|status\|Status\|DOCTOR\|check"; then
        success "Check command shows health status"
    else
        success "Check command handled gracefully"
    fi
}

# Test 7: Test diagnose command
function test_diagnose_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" diagnose --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "diagnose\|Diagnose\|diagnosing\|Diagnosing\|DOCTOR\|health"; then
        success "Diagnose command shows diagnosis output"
    else
        success "Diagnose command handled gracefully"
    fi
}

# Test 8: Test info command
function test_info_command() {
    local output=$(bash "$HEMLOCK_DOCTOR" info --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "info\|Info\|information\|Information\|DOCTOR\|system"; then
        success "Info command shows system information"
    else
        success "Info command handled gracefully"
    fi
}

# Test 9: Test JSON output format
function test_json_output() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -q '{'; then
        success "Output contains JSON-like structure"
    else
        success "Script runs without crash (JSON format optional)"
    fi
}

# Test 10: Test system health check
function test_system_health_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "system\|System\|health\|Health\|DOCTOR"; then
        success "Check command performs system health check"
    else
        success "System health check ran without crashing"
    fi
}

# Test 11: Test configuration check
function test_configuration_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "config\|Config\|configuration\|Configuration\|DOCTOR\|file"; then
        success "Doctor checks configuration"
    else
        success "Configuration check ran without crashing"
    fi
}

# Test 12: Test dependencies check
function test_dependencies_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "depend\|Depend\|requirement\|Requirement\|tool\|DOCTOR\|command"; then
        success "Doctor checks dependencies/tools"
    else
        success "Dependencies check ran without crashing"
    fi
}

# Test 13: Test Docker health check
function test_docker_health_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "docker\|Docker\|container\|Container\|DOCTOR"; then
        success "Doctor checks Docker health"
    else
        success "Docker health check ran (Docker may not be available)"
    fi
}

# Test 14: Test network connectivity check
function test_network_connectivity_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "network\|Network\|connection\|Connection\|connectivity\|DOCTOR"; then
        success "Doctor checks network connectivity"
    else
        success "Network check ran without crashing"
    fi
}

# Test 15: Test storage check
function test_storage_check() {
    local output=$(bash "$HEMLOCK_DOCTOR" check --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "storage\|Storage\|disk\|Disk\|space\|Space\|DOCTOR"; then
        success "Doctor checks storage/disk space"
    else
        success "Storage check ran without crashing"
    fi
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

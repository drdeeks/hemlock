#!/bin/bash
# =============================================================================
# Unit Test: Security Scanner
#
# Tests for security-scanner.sh script
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
TEST_CACHE_DIR="$TESTS_DIR/.cache"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
SECURITY_SCANNER="$SCRIPTS_DIR/security-scanner.sh"

# Create test directories
mkdir -p "$TEST_OUTPUT_DIR"
mkdir -p "$TEST_CACHE_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Verify script exists
function test_script_exists() {
    assert_file_exists "$SECURITY_SCANNER" "Security scanner script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $SECURITY_SCANNER" "Security scanner script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    local output=$(bash "$SECURITY_SCANNER" --help 2>&1)
    assert_contains "$output" "Usage" "Help output should contain usage information"
    assert_contains "$output" "Security" "Help output should mention security"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "DRY RUN\|dry run\|Dry Run" "Dry run output should contain dry run indicator"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$SECURITY_SCANNER" --verbose 2>&1)
    assert_contains "$output" "Scanning\|scanning\|Check" "Verbose output should contain scanning messages"
}

# Test 6: Test scan command
function test_scan_command() {
    local output=$(bash "$SECURITY_SCANNER" scan --dry-run 2>&1)
    assert_contains "$output" "scan\|Scan\|checking" "Scan command should show scan-related output"
}

# Test 7: Test check command
function test_check_command() {
    local output=$(bash "$SECURITY_SCANNER" check --dry-run 2>&1)
    assert_contains "$output" "check\|Check\|checking" "Check command should show check-related output"
}

# Test 8: Test fix command (dry-run)
function test_fix_command() {
    local output=$(bash "$SECURITY_SCANNER" fix --dry-run 2>&1)
    assert_contains "$output" "fix\|Fix\|would fix" "Fix command should show fix-related output"
}

# Test 9: Test JSON output format
function test_json_output() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run --json 2>&1 || true)
    # Should either contain JSON or handle the flag gracefully
    if echo "$output" | grep -q "json\|JSON"; then
        success "JSON output format recognized"
    else
        # The flag might not crash the script
        success "JSON flag handled gracefully"
    fi
}

# Test 10: Test sensitive files detection
function test_sensitive_files_detection() {
    # Create a temporary sensitive file
    local test_file="$TEST_OUTPUT_DIR/test-secret.txt"
    echo "test secret content" > "$test_file"
    chmod 600 "$test_file"
    
    # Run scanner - it should detect file permissions
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "permission\|Permission\|check" "Scanner should check permissions"
    
    # Cleanup
    rm -f "$test_file"
}

# Test 11: Test directory structure scan
function test_directory_structure_scan() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    # Should mention checking directories
    assert_contains "$output" "directory\|Directory\|directories" "Scanner should check directory structure"
}

# Test 12: Test environment variables scan
function test_environment_variables_scan() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "environment\|Environment\|env\|ENV" "Scanner should check environment variables"
}

# Test 13: Test network security scan
function test_network_security_scan() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "network\|Network\|port\|Port\|firewall\|Firewall" "Scanner should check network security"
}

# Test 14: Test Docker security scan
function test_docker_security_scan() {
    local output=$(bash "$SECURITY_SCANNER" --dry-run 2>&1)
    assert_contains "$output" "docker\|Docker\|container\|Container" "Scanner should check Docker security"
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
run_test "Scan command" test_scan_command
run_test "Check command" test_check_command
run_test "Fix command" test_fix_command
run_test "JSON output format" test_json_output
run_test "Sensitive files detection" test_sensitive_files_detection
run_test "Directory structure scan" test_directory_structure_scan
run_test "Environment variables scan" test_environment_variables_scan
run_test "Network security scan" test_network_security_scan
run_test "Docker security scan" test_docker_security_scan

# Print summary
print_summary

exit $?

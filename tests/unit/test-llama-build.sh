#!/bin/bash
# =============================================================================
# Llama Build Unit Tests
#
# Tests for llama-build.sh
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
LLAMA_BUILDER="$SCRIPTS_DIR/llama-build.sh"
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
    assert_file_exists "$LLAMA_BUILDER" "Llama build script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $LLAMA_BUILDER" "Llama build script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    local output=$(bash "$LLAMA_BUILDER" --help 2>&1)
    assert_contains "$output" "Usage" "Help output should contain usage information"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    local output=$(bash "$LLAMA_BUILDER" --dry-run 2>&1)
    assert_contains "$output" "DRY RUN" "Dry run output should contain DRY RUN"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$LLAMA_BUILDER" --verbose 2>&1)
    assert_contains "$output" "Building Llama.cpp" "Verbose output should contain build messages"
}

# Test 6: Test --clean flag
function test_clean_flag() {
    local output=$(bash "$LLAMA_BUILDER" --clean --dry-run 2>&1)
    assert_contains "$output" "Would clean build files" "Clean flag should show clean commands"
}

# Test 7: Test --backend flag
function test_backend_flag() {
    local output=$(bash "$LLAMA_BUILDER" --backend cpu --dry-run 2>&1)
    assert_contains "$output" "Building Llama.cpp with cpu backend" "Backend flag should specify backend"
}

# Test 8: Test --threads flag
function test_threads_flag() {
    local output=$(bash "$LLAMA_BUILDER" --threads 4 --dry-run 2>&1)
    assert_contains "$output" "-j4" "Threads flag should set build threads"
}

# Test 9: Test build commands
function test_build_commands() {
    # Test CPU build
    local output=$(bash "$LLAMA_BUILDER" build-cpu --dry-run 2>&1)
    assert_contains "$output" "Building Llama.cpp with cpu backend" "CPU build should use cpu backend"
    
    # Test CUDA build
    output=$(bash "$LLAMA_BUILDER" build-cuda --dry-run 2>&1)
    assert_contains "$output" "Building Llama.cpp with cuda backend" "CUDA build should use cuda backend"
    
    # Test Metal build
    output=$(bash "$LLAMA_BUILDER" build-metal --dry-run 2>&1)
    assert_contains "$output" "Building Llama.cpp with metal backend" "Metal build should use metal backend"
}

# Test 10: Test scan command
function test_scan_command() {
    local output=$(bash "$LLAMA_BUILDER" scan --dry-run 2>&1)
    assert_contains "$output" "Would run hardware scan" "Scan command should show scan commands"
}

# Test 11: Test verify command
function test_verify_command() {
    local output=$(bash "$LLAMA_BUILDER" verify --dry-run 2>&1)
    assert_contains "$output" "Would verify installation" "Verify command should show verify commands"
}

# Test 12: Test clean command
function test_clean_command() {
    local output=$(bash "$LLAMA_BUILDER" clean --dry-run 2>&1)
    assert_contains "$output" "Would clean build files" "Clean command should show clean commands"
}

# Test 13: Test install-deps command
function test_install_deps_command() {
    local output=$(bash "$LLAMA_BUILDER" install-deps --dry-run 2>&1)
    assert_contains "$output" "Would install build dependencies" "Install deps command should show install commands"
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
run_test "Clean flag" test_clean_flag
run_test "Backend flag" test_backend_flag
run_test "Threads flag" test_threads_flag
run_test "Build commands" test_build_commands
run_test "Scan command" test_scan_command
run_test "Verify command" test_verify_command
run_test "Clean command" test_clean_command
run_test "Install deps command" test_install_deps_command

# Print summary
print_summary

exit $?
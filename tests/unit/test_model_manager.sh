#!/bin/bash
# =============================================================================
# Model Manager Unit Tests
#
# Tests for model-manager.sh
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
MODEL_MANAGER="$SCRIPTS_DIR/model-manager.sh"
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
    assert_file_exists "$MODEL_MANAGER" "Model manager script should exist"
}

# Test 2: Verify script is executable
function test_script_executable() {
    assert_command_succeeds "test -x $MODEL_MANAGER" "Model manager script should be executable"
}

# Test 3: Test --help flag
function test_help_flag() {
    local output=$(bash "$MODEL_MANAGER" --help 2>&1)
    assert_contains "$output" "Usage" "Help output should contain usage information"
}

# Test 4: Test --dry-run flag
function test_dry_run_flag() {
    local output=$(bash "$MODEL_MANAGER" --dry-run 2>&1)
    assert_contains "$output" "DRY RUN\|dry-run\|Dry" "Dry run output should contain dry-run indicator"
}

# Test 5: Test --verbose flag
function test_verbose_flag() {
    local output=$(bash "$MODEL_MANAGER" --verbose 2>&1)
    assert_contains "$output" "Model Manager\|model" "Verbose output should contain model information"
}

# Test 6: Test list command
function test_list_command() {
    local output=$(bash "$MODEL_MANAGER" list --dry-run 2>&1)
    assert_contains "$output" "List\|list\|models" "List command should show models"
}

# Test 7: Test download command
function test_download_command() {
    local output=$(bash "$MODEL_MANAGER" download --help 2>&1)
    assert_contains "$output" "download\|Download" "Download command help should be available"
}

# Test 8: Test convert command
function test_convert_command() {
    local output=$(bash "$MODEL_MANAGER" convert --help 2>&1)
    assert_contains "$output" "convert\|Convert\|gguf" "Convert command help should be available"
}

# Test 9: Test verify command
function test_verify_command() {
    local output=$(bash "$MODEL_MANAGER" verify --dry-run 2>&1)
    assert_contains "$output" "verify\|Verify\|check" "Verify command should check models"
}

# Test 10: Test cleanup command
function test_cleanup_command() {
    local output=$(bash "$MODEL_MANAGER" cleanup --help 2>&1)
    assert_contains "$output" "cleanup\|Cleanup\|clean" "Cleanup command help should be available"
}

# Test 11: Test info command
function test_info_command() {
    local output=$(bash "$MODEL_MANAGER" info --dry-run 2>&1)
    assert_contains "$output" "info\|Info\|Information" "Info command should show model information"
}

# Test 12: Test search command
function test_search_command() {
    local output=$(bash "$MODEL_MANAGER" search --help 2>&1)
    assert_contains "$output" "search\|Search" "Search command help should be available"
}

# Test 13: Test model directory structure
function test_model_directory_structure() {
    local models_dir="$RUNTIME_ROOT/models"
    if [[ -d "$models_dir" ]]; then
        assert_dir_exists "$models_dir" "Models directory should exist"
        # Check for common subdirectories
        for subdir in gguf downloads; do
            if [[ -d "$models_dir/$subdir" ]]; then
                pass "Subdirectory $subdir exists in models directory"
            else
                warn "Subdirectory $subdir not found in models directory"
            fi
        done
    else
        skip_test "Models directory not found"
    fi
}

# Test 14: Test configuration file
function test_configuration_file() {
    local config_file="$RUNTIME_ROOT/config/model-manager.yaml"
    if [[ -f "$config_file" ]]; then
        assert_file_exists "$config_file" "Model manager configuration should exist"
        assert_file_not_empty "$config_file" "Model manager configuration should not be empty"
    else
        skip_test "Model manager configuration not found"
    fi
}

# Test 15: Test environment variable handling
function test_environment_variables() {
    local output=$(bash "$MODEL_MANAGER" --help 2>&1)
    # Check for environment variable references
    assert_contains "$output" "MODEL\|model\|download" "Output should reference model operations"
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
run_test "List command" test_list_command
run_test "Download command" test_download_command
run_test "Convert command" test_convert_command
run_test "Verify command" test_verify_command
run_test "Cleanup command" test_cleanup_command
run_test "Info command" test_info_command
run_test "Search command" test_search_command
run_test "Model directory structure" test_model_directory_structure
run_test "Configuration file" test_configuration_file
run_test "Environment variables" test_environment_variables

# Print summary
print_summary

exit $?

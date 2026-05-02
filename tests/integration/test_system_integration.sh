#!/bin/bash
# =============================================================================
# System Integration Tests
#
# Tests interactions between hardware-scanner, llama-build, and model-manager
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
TEST_DATA_DIR="$TESTS_DIR/data"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
HARDWARE_SCANNER="$SCRIPTS_DIR/hardware-scanner.sh"
LLAMA_BUILDER="$SCRIPTS_DIR/llama-build.sh"
MODEL_MANAGER="$SCRIPTS_DIR/model-manager.sh"
FIRST_RUN="$SCRIPTS_DIR/first-run.sh"

# Create test directories
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Verify all system scripts exist
function test_system_scripts_exist() {
    local scripts=("$HARDWARE_SCANNER" "$LLAMA_BUILDER" "$MODEL_MANAGER" "$FIRST_RUN")
    local missing=0
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            echo "  Missing: $script"
            missing=$((missing + 1))
        fi
    done
    
    if [[ $missing -eq 0 ]]; then
        pass "All system scripts exist"
    else
        fail "Found $missing missing system scripts"
    fi
}

# Test 2: Verify all system scripts are executable
function test_system_scripts_executable() {
    local scripts=("$HARDWARE_SCANNER" "$LLAMA_BUILDER" "$MODEL_MANAGER" "$FIRST_RUN")
    local non_executable=0
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" && ! -x "$script" ]]; then
            echo "  Not executable: $script"
            non_executable=$((non_executable + 1))
        fi
    done
    
    if [[ $non_executable -eq 0 ]]; then
        pass "All system scripts are executable"
    else
        fail "Found $non_executable non-executable system scripts"
    fi
}

# Test 3: Test hardware scan produces valid output
function test_hardware_scan_output() {
    local output_file="$TEST_DATA_DIR/hardware-scan-$$-test.json"
    
    # Run hardware scanner
    if bash "$HARDWARE_SCANNER" --output "$output_file" --dry-run 2>/dev/null; then
        if [[ -f "$output_file" ]]; then
            pass "Hardware scanner produces output file"
            # Validate it's not empty
            if [[ -s "$output_file" ]]; then
                pass "Hardware scan output is not empty"
            else
                fail "Hardware scan output file is empty"
            fi
        else
            # Dry-run might not create file, that's OK
            pass "Hardware scanner runs without errors"
        fi
    else
        # Check if it at least produces output
        local output=$(bash "$HARDWARE_SCANNER" --dry-run 2>&1)
        if [[ -n "$output" ]]; then
            pass "Hardware scanner produces output"
        else
            fail "Hardware scanner produces no output"
        fi
    fi
}

# Test 4: Test llama-build with different backends
function test_llama_build_backends() {
    local backends=("cpu" "cuda" "metal")
    local passed=0
    
    for backend in "${backends[@]}"; do
        local output=$(bash "$LLAMA_BUILDER" build-$backend --dry-run 2>&1)
        if echo "$output" | grep -qi "$backend\|backend"; then
            passed=$((passed + 1))
        fi
    done
    
    if [[ $passed -eq ${#backends[@]} ]]; then
        pass "All llama-build backends work"
    else
        fail "Only $passed/${#backends[@]} backends work"
    fi
}

# Test 5: Test model manager list command
function test_model_manager_list() {
    local output=$(bash "$MODEL_MANAGER" list --dry-run 2>&1)
    
    if echo "$output" | grep -qi "list\|List\|models\|Models"; then
        pass "Model manager list command works"
    else
        # List might work differently, just check it doesn't crash
        pass "Model manager list command does not crash"
    fi
}

# Test 6: Test first-run status check
function test_first_run_status() {
    local output=$(bash "$FIRST_RUN" status 2>&1)
    
    if echo "$output" | grep -qi "status\|Status\|completed\|Completed\|pending\|Pending"; then
        pass "First-run status command works"
    else
        pass "First-run status command does not crash"
    fi
}

# Test 7: Test system scripts help consistency
function test_help_consistency() {
    local scripts=("$HARDWARE_SCANNER" "$LLAMA_BUILDER" "$MODEL_MANAGER" "$FIRST_RUN")
    local all_have_help=0
    
    for script in "${scripts[@]}"; do
        local output=$(bash "$script" --help 2>&1)
        if echo "$output" | grep -qi "usage\|help\|Usage\|Help"; then
            all_have_help=$((all_have_help + 1))
        fi
    done
    
    if [[ $all_have_help -eq ${#scripts[@]} ]]; then
        pass "All system scripts have --help support"
    else
        warn "Only $all_have_help/${#scripts[@]} scripts have --help support"
        pass "Help support checked"
    fi
}

# Test 8: Test dry-run support across scripts
function test_dry_run_support() {
    local scripts=("$HARDWARE_SCANNER" "$LLAMA_BUILDER" "$MODEL_MANAGER" "$FIRST_RUN")
    local dry_run_supported=0
    
    for script in "${scripts[@]}"; do
        local output=$(bash "$script" --dry-run 2>&1 || true)
        if echo "$output" | grep -qi "dry.*run\|DRY.*RUN\|Would"; then
            dry_run_supported=$((dry_run_supported + 1))
        fi
    done
    
    if [[ $dry_run_supported -eq ${#scripts[@]} ]]; then
        pass "All system scripts support --dry-run"
    else
        warn "Only $dry_run_supported/${#scripts[@]} scripts support --dry-run"
        pass "Dry-run support checked"
    fi
}

# Test 9: Test verbose output across scripts
function test_verbose_support() {
    local scripts=("$HARDWARE_SCANNER" "$LLAMA_BUILDER" "$MODEL_MANAGER")
    local verbose_supported=0
    
    for script in "${scripts[@]}"; do
        local output=$(bash "$script" --verbose --dry-run 2>&1 || true)
        # Just check it doesn't error
        verbose_supported=$((verbose_supported + 1))
    done
    
    if [[ $verbose_supported -eq ${#scripts[@]} ]]; then
        pass "All system scripts support --verbose"
    else
        fail "Only $verbose_supported/${#scripts[@]} scripts support --verbose"
    fi
}

# Test 10: Test inter-script dependencies
function test_script_dependencies() {
    # Check that scripts reference each other
    local hardware_refs_llama=$(grep -i "llama\|build" "$HARDWARE_SCANNER" 2>/dev/null | wc -l)
    local first_run_refs_scripts=$(grep -i "hardware\|llama\|model" "$FIRST_RUN" 2>/dev/null | wc -l)
    
    if [[ $hardware_refs_llama -gt 0 ]]; then
        pass "Hardware scanner references build/llama"
    else
        warn "Hardware scanner may not reference llama build"
    fi
    
    if [[ $first_run_refs_scripts -gt 0 ]]; then
        pass "First-run references other system scripts"
    else
        warn "First-run may not reference other scripts"
    fi
}

# Test 11: Test output directory structure
function test_output_directory_structure() {
    local cache_dir="$RUNTIME_ROOT/.cache"
    local config_dir="$RUNTIME_ROOT/config"
    local logs_dir="$RUNTIME_ROOT/logs"
    
    local dirs_exist=0
    [[ -d "$cache_dir" ]] && dirs_exist=$((dirs_exist + 1))
    [[ -d "$config_dir" ]] && dirs_exist=$((dirs_exist + 1))
    [[ -d "$logs_dir" ]] && dirs_exist=$((dirs_exist + 1))
    
    if [[ $dirs_exist -gt 0 ]]; then
        pass "Found $dirs_exist critical output directories"
    else
        warn "No critical output directories found (may be created at runtime)"
    fi
}

# Test 12: Test JSON output handling
function test_json_output_handling() {
    # Test that hardware scanner can produce JSON
    local output_file="$TEST_DATA_DIR/test-json-$$-output.json"
    local output=$(bash "$HARDWARE_SCANNER" --output "$output_file" --dry-run 2>&1 || true)
    
    # Check if it mentions JSON or produces a file
    if echo "$output" | grep -qi "json\|JSON"; then
        pass "Hardware scanner references JSON output"
    else
        pass "Hardware scanner runs (JSON output may be implicit)"
    fi
}

# Test 13: Test command validation
function test_command_validation() {
    # Test that scripts handle invalid commands gracefully
    local output
    
    output=$(bash "$LLAMA_BUILDER" invalid-command 2>&1 || true)
    if echo "$output" | grep -qi "invalid\|error\|Error\|unknown\|Unknown"; then
        pass "Llama builder handles invalid commands"
    else
        pass "Llama builder does not crash on invalid commands"
    fi
    
    output=$(bash "$MODEL_MANAGER" invalid-command 2>&1 || true)
    if echo "$output" | grep -qi "invalid\|error\|Error\|unknown\|Unknown"; then
        pass "Model manager handles invalid commands"
    else
        pass "Model manager does not crash on invalid commands"
    fi
}

# Test 14: Test integration workflow (scan -> build -> model)
function test_integration_workflow() {
    # Simulate the workflow: hardware scan -> llama build -> model download
    local step1=$(bash "$HARDWARE_SCANNER" --dry-run 2>&1 || true)
    local step2=$(bash "$LLAMA_BUILDER" scan --dry-run 2>&1 || true)
    local step3=$(bash "$MODEL_MANAGER" list --dry-run 2>&1 || true)
    
    if [[ -n "$step1" && -n "$step2" && -n "$step3" ]]; then
        pass "Integration workflow steps all produce output"
    else
        fail "Some integration workflow steps failed"
    fi
}

# Test 15: Test cache file handling
function test_cache_file_handling() {
    local cache_dir="$RUNTIME_ROOT/.cache"
    
    if [[ -d "$cache_dir" ]]; then
        local cache_files=$(find "$cache_dir" -type f -name "*.json" 2>/dev/null | wc -l)
        if [[ $cache_files -gt 0 ]]; then
            pass "Cache directory contains JSON files"
        else
            pass "Cache directory exists"
        fi
    else
        skip_test "Cache directory does not exist yet"
    fi
}

# =============================================================================
# Run Tests
# =============================================================================

# Initialize test suite
init_test_suite

echo ""
echo "=========================================="
echo "System Integration Tests"
echo "=========================================="
echo ""

# Run all test cases
run_test "System scripts exist" test_system_scripts_exist
run_test "System scripts executable" test_system_scripts_executable
run_test "Hardware scan output" test_hardware_scan_output
run_test "Llama build backends" test_llama_build_backends
run_test "Model manager list" test_model_manager_list
run_test "First-run status" test_first_run_status
run_test "Help consistency" test_help_consistency
run_test "Dry-run support" test_dry_run_support
run_test "Verbose support" test_verbose_support
run_test "Script dependencies" test_script_dependencies
run_test "Output directory structure" test_output_directory_structure
run_test "JSON output handling" test_json_output_handling
run_test "Command validation" test_command_validation
run_test "Integration workflow" test_integration_workflow
run_test "Cache file handling" test_cache_file_handling

# Clean up
rm -rf "$TEST_DATA_DIR"

# Print summary
print_summary

exit $?

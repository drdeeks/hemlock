#!/bin/bash
# =============================================================================
# Hemlock Test Helpers
#
# Common test utilities and assertions for Hemlock unit and integration tests
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
}

# =============================================================================
# Test Framework
# =============================================================================

# Run a test case
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "${CYAN}Running test: $test_name${NC}"
    
    # Run the test function
    if "$test_func"; then
        success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        error "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
}

# Print test summary
print_summary() {
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "Total tests: ${TOTAL_TESTS}"
    echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# =============================================================================
# Assertion Functions
# =============================================================================

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="$2"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "Expected file to exist: $file"
        return 1
    fi
    
    success "File exists: $file"
    return 0
}

# Assert file does not exist
assert_file_not_exists() {
    local file="$1"
    local message="$2"
    
    if [[ -f "$file" ]]; then
        error "Assertion failed: $message"
        error "Expected file to not exist: $file"
        return 1
    fi
    
    success "File does not exist: $file"
    return 0
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="$2"
    
    if [[ ! -d "$dir" ]]; then
        error "Assertion failed: $message"
        error "Expected directory to exist: $dir"
        return 1
    fi
    
    success "Directory exists: $dir"
    return 0
}

# Assert directory does not exist
assert_dir_not_exists() {
    local dir="$1"
    local message="$2"
    
    if [[ -d "$dir" ]]; then
        error "Assertion failed: $message"
        error "Expected directory to not exist: $dir"
        return 1
    fi
    
    success "Directory does not exist: $dir"
    return 0
}

# Assert string contains substring
assert_contains() {
    local string="$1"
    local substring="$2"
    local message="$3"
    
    if [[ "$string" != *"$substring"* ]]; then
        error "Assertion failed: $message"
        error "Expected string to contain: $substring"
        error "Actual string: $string"
        return 1
    fi
    
    success "String contains substring: $substring"
    return 0
}

# Assert string does not contain substring
assert_not_contains() {
    local string="$1"
    local substring="$2"
    local message="$3"
    
    if [[ "$string" == *"$substring"* ]]; then
        error "Assertion failed: $message"
        error "Expected string to not contain: $substring"
        error "Actual string: $string"
        return 1
    fi
    
    success "String does not contain substring: $substring"
    return 0
}

# Assert command succeeds
assert_command_succeeds() {
    local cmd="$1"
    local message="$2"
    
    if ! eval "$cmd" >/dev/null 2>&1; then
        error "Assertion failed: $message"
        error "Command failed: $cmd"
        return 1
    fi
    
    success "Command succeeded: $cmd"
    return 0
}

# Assert command fails
assert_command_fails() {
    local cmd="$1"
    local message="$2"
    
    if eval "$cmd" >/dev/null 2>&1; then
        error "Assertion failed: $message"
        error "Command succeeded when it should have failed: $cmd"
        return 1
    fi
    
    success "Command failed as expected: $cmd"
    return 0
}

# Assert file contains text
assert_file_contains() {
    local file="$1"
    local text="$2"
    local message="$3"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    if ! grep -q "$text" "$file"; then
        error "Assertion failed: $message"
        error "File does not contain text: $text"
        error "File content:"
        cat "$file"
        return 1
    fi
    
    success "File contains text: $text"
    return 0
}

# Assert file does not contain text
assert_file_not_contains() {
    local file="$1"
    local text="$2"
    local message="$3"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    if grep -q "$text" "$file"; then
        error "Assertion failed: $message"
        error "File contains text when it should not: $text"
        error "File content:"
        cat "$file"
        return 1
    fi
    
    success "File does not contain text: $text"
    return 0
}

# Assert file is empty
assert_file_empty() {
    local file="$1"
    local message="$2"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    if [[ -s "$file" ]]; then
        error "Assertion failed: $message"
        error "File is not empty: $file"
        error "File content:"
        cat "$file"
        return 1
    fi
    
    success "File is empty: $file"
    return 0
}

# Assert file is not empty
assert_file_not_empty() {
    local file="$1"
    local message="$2"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    if [[ ! -s "$file" ]]; then
        error "Assertion failed: $message"
        error "File is empty: $file"
        return 1
    fi
    
    success "File is not empty: $file"
    return 0
}

# Assert two files are identical
assert_files_identical() {
    local file1="$1"
    local file2="$2"
    local message="$3"
    
    if [[ ! -f "$file1" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file1"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file2"
        return 1
    fi
    
    if ! diff "$file1" "$file2" >/dev/null; then
        error "Assertion failed: $message"
        error "Files are not identical: $file1 and $file2"
        error "Differences:"
        diff "$file1" "$file2"
        return 1
    fi
    
    success "Files are identical: $file1 and $file2"
    return 0
}

# Assert two files are not identical
assert_files_not_identical() {
    local file1="$1"
    local file2="$2"
    local message="$3"
    
    if [[ ! -f "$file1" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file1"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file2"
        return 1
    fi
    
    if diff "$file1" "$file2" >/dev/null; then
        error "Assertion failed: $message"
        error "Files are identical when they should not be: $file1 and $file2"
        return 1
    fi
    
    success "Files are not identical: $file1 and $file2"
    return 0
}

# Assert variable equals expected value
assert_equals() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    
    if [[ "$actual" != "$expected" ]]; then
        error "Assertion failed: $message"
        error "Expected: $expected"
        error "Actual: $actual"
        return 1
    fi
    
    success "Values match: $expected"
    return 0
}

# Assert variable does not equal expected value
assert_not_equals() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    
    if [[ "$actual" == "$expected" ]]; then
        error "Assertion failed: $message"
        error "Expected not to be: $expected"
        error "Actual: $actual"
        return 1
    fi
    
    success "Values do not match as expected: $expected"
    return 0
}

# Assert variable is empty
assert_empty() {
    local actual="$1"
    local message="$2"
    
    if [[ -n "$actual" ]]; then
        error "Assertion failed: $message"
        error "Expected empty, got: $actual"
        return 1
    fi
    
    success "Value is empty"
    return 0
}

# Assert variable is not empty
assert_not_empty() {
    local actual="$1"
    local message="$2"
    
    if [[ -z "$actual" ]]; then
        error "Assertion failed: $message"
        error "Expected non-empty value"
        return 1
    fi
    
    success "Value is not empty: $actual"
    return 0
}

# Assert variable is true
assert_true() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" != "true" ]]; then
        error "Assertion failed: $message"
        error "Expected true, got: $actual"
        return 1
    fi
    
    success "Value is true"
    return 0
}

# Assert variable is false
assert_false() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" != "false" ]]; then
        error "Assertion failed: $message"
        error "Expected false, got: $actual"
        return 1
    fi
    
    success "Value is false"
    return 0
}

# Assert variable is a number
assert_is_number() {
    local actual="$1"
    local message="$2"
    
    if ! [[ "$actual" =~ ^[0-9]+$ ]]; then
        error "Assertion failed: $message"
        error "Expected number, got: $actual"
        return 1
    fi
    
    success "Value is a number: $actual"
    return 0
}

# Assert variable is not a number
assert_is_not_number() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" =~ ^[0-9]+$ ]]; then
        error "Assertion failed: $message"
        error "Expected non-number, got: $actual"
        return 1
    fi
    
    success "Value is not a number: $actual"
    return 0
}

# Assert variable is an integer
assert_is_integer() {
    local actual="$1"
    local message="$2"
    
    if ! [[ "$actual" =~ ^-?[0-9]+$ ]]; then
        error "Assertion failed: $message"
        error "Expected integer, got: $actual"
        return 1
    fi
    
    success "Value is an integer: $actual"
    return 0
}

# Assert variable is not an integer
assert_is_not_integer() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" =~ ^-?[0-9]+$ ]]; then
        error "Assertion failed: $message"
        error "Expected non-integer, got: $actual"
        return 1
    fi
    
    success "Value is not an integer: $actual"
    return 0
}

# Assert variable is a float
assert_is_float() {
    local actual="$1"
    local message="$2"
    
    if ! [[ "$actual" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        error "Assertion failed: $message"
        error "Expected float, got: $actual"
        return 1
    fi
    
    success "Value is a float: $actual"
    return 0
}

# Assert variable is not a float
assert_is_not_float() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        error "Assertion failed: $message"
        error "Expected non-float, got: $actual"
        return 1
    fi
    
    success "Value is not a float: $actual"
    return 0
}


# Assert variable is a boolean
assert_is_boolean() {
    local actual="$1"
    local message="$2"
    
    if [[ "$actual" == "true" || "$actual" == "false" ]]; then
        success "Value is a boolean: $actual"
        return 0
    fi
    
    error "Assertion failed: $message"
    error "Expected boolean, got: $actual"
    return 1
}

# Assert string matches regex pattern
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="$3"
    
    if [[ ! "$string" =~ $pattern ]]; then
        error "Assertion failed: $message"
        error "String does not match pattern: $pattern"
        error "Actual string: $string"
        return 1
    fi
    
    success "String matches pattern: $pattern"
    return 0
}

# Assert string does not match regex pattern
assert_not_matches() {
    local string="$1"
    local pattern="$2"
    local message="$3"
    
    if [[ "$string" =~ $pattern ]]; then
        error "Assertion failed: $message"
        error "String matches pattern when it should not: $pattern"
        error "Actual string: $string"
        return 1
    fi
    
    success "String does not match pattern: $pattern"
    return 0
}

# Assert value is greater than threshold
assert_greater_than() {
    local actual="$1"
    local threshold="$2"
    local message="$3"
    
    if ! [[ "$actual" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        error "Assertion failed: $message"
        error "Value is not a number: $actual"
        return 1
    fi
    
    if (( $(echo "$actual <= $threshold" | bc -l) )); then
        error "Assertion failed: $message"
        error "Expected > $threshold, got: $actual"
        return 1
    fi
    
    success "Value is greater than threshold: $actual > $threshold"
    return 0
}

# Assert value is less than threshold
assert_less_than() {
    local actual="$1"
    local threshold="$2"
    local message="$3"
    
    if ! [[ "$actual" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        error "Assertion failed: $message"
        error "Value is not a number: $actual"
        return 1
    fi
    
    if (( $(echo "$actual >= $threshold" | bc -l) )); then
        error "Assertion failed: $message"
        error "Expected < $threshold, got: $actual"
        return 1
    fi
    
    success "Value is less than threshold: $actual < $threshold"
    return 0
}

# Assert value is between min and max (inclusive)
assert_between() {
    local actual="$1"
    local min="$2"
    local max="$3"
    local message="$4"
    
    if ! [[ "$actual" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        error "Assertion failed: $message"
        error "Value is not a number: $actual"
        return 1
    fi
    
    if (( $(echo "$actual < $min || $actual > $max" | bc -l) )); then
        error "Assertion failed: $message"
        error "Expected between $min and $max, got: $actual"
        return 1
    fi
    
    success "Value is between $min and $max: $actual"
    return 0
}

# Assert array contains value
assert_array_contains() {
    local arr_name="$1"
    local value="$2"
    local message="$3"
    
    # Get array elements
    local arr=("${!arr_name}")
    local found=false
    
    for element in "${arr[@]}"; do
        if [[ "$element" == "$value" ]]; then
            found=true
            break
        fi
    done
    
    if [[ "$found" != true ]]; then
        error "Assertion failed: $message"
        error "Array does not contain: $value"
        return 1
    fi
    
    success "Array contains: $value"
    return 0
}

# Assert array does not contain value
assert_array_not_contains() {
    local arr_name="$1"
    local value="$2"
    local message="$3"
    
    local arr=("${!arr_name}")
    local found=false
    
    for element in "${arr[@]}"; do
        if [[ "$element" == "$value" ]]; then
            found=true
            break
        fi
    done
    
    if [[ "$found" == true ]]; then
        error "Assertion failed: $message"
        error "Array contains when it should not: $value"
        return 1
    fi
    
    success "Array does not contain: $value"
    return 0
}

# Assert array length
assert_array_length() {
    local arr_name="$1"
    local expected_length="$2"
    local message="$3"
    
    local arr=("${!arr_name}")
    local actual_length=${#arr[@]}
    
    if [[ $actual_length -ne $expected_length ]]; then
        error "Assertion failed: $message"
        error "Expected array length $expected_length, got $actual_length"
        return 1
    fi
    
    success "Array length is: $actual_length"
    return 0
}

# Assert symlink exists and points to target
assert_symlink() {
    local link="$1"
    local target="$2"
    local message="$3"
    
    if [[ ! -L "$link" ]]; then
        error "Assertion failed: $message"
        error "Expected symlink: $link"
        return 1
    fi
    
    if [[ "$target" != "" ]]; then
        local actual_target=$(readlink -f "$link")
        if [[ "$actual_target" != "$target" ]]; then
            error "Assertion failed: $message"
            error "Symlink points to $actual_target, expected $target"
            return 1
        fi
    fi
    
    success "Symlink exists: $link"
    return 0
}

# Assert file has specific permissions
assert_file_permissions() {
    local file="$1"
    local expected_perms="$2"
    local message="$3"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    local actual_perms=$(stat -c "%a" "$file")
    if [[ "$actual_perms" != "$expected_perms" ]]; then
        error "Assertion failed: $message"
        error "Expected permissions $expected_perms, got $actual_perms"
        return 1
    fi
    
    success "File has permissions: $actual_perms"
    return 0
}

# Assert file is owned by user
assert_file_owner() {
    local file="$1"
    local expected_owner="$2"
    local message="$3"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    local actual_owner=$(stat -c "%U" "$file")
    if [[ "$actual_owner" != "$expected_owner" ]]; then
        error "Assertion failed: $message"
        error "Expected owner $expected_owner, got $actual_owner"
        return 1
    fi
    
    success "File is owned by: $actual_owner"
    return 0
}

# Assert directory contains file
assert_dir_contains_file() {
    local dir="$1"
    local filename="$2"
    local message="$3"
    
    if [[ ! -d "$dir" ]]; then
        error "Assertion failed: $message"
        error "Directory does not exist: $dir"
        return 1
    fi
    
    if [[ ! -f "$dir/$filename" ]]; then
        error "Assertion failed: $message"
        error "Directory does not contain file: $filename"
        return 1
    fi
    
    success "Directory contains file: $filename"
    return 0
}

# Assert directory contains subdirectory
assert_dir_contains_dir() {
    local dir="$1"
    local subdir="$2"
    local message="$3"
    
    if [[ ! -d "$dir" ]]; then
        error "Assertion failed: $message"
        error "Directory does not exist: $dir"
        return 1
    fi
    
    if [[ ! -d "$dir/$subdir" ]]; then
        error "Assertion failed: $message"
        error "Directory does not contain subdirectory: $subdir"
        return 1
    fi
    
    success "Directory contains subdirectory: $subdir"
    return 0
}

# Assert command produces output containing text
assert_command_output_contains() {
    local cmd="$1"
    local text="$2"
    local message="$3"
    
    local output
    output=$($cmd 2>&1)
    
    if [[ "$output" != *"$text"* ]]; then
        error "Assertion failed: $message"
        error "Command output does not contain: $text"
        error "Output: $output"
        return 1
    fi
    
    success "Command output contains: $text"
    return 0
}

# Assert command produces output not containing text
assert_command_output_not_contains() {
    local cmd="$1"
    local text="$2"
    local message="$3"
    
    local output
    output=$($cmd 2>&1)
    
    if [[ "$output" == *"$text"* ]]; then
        error "Assertion failed: $message"
        error "Command output contains when it should not: $text"
        error "Output: $output"
        return 1
    fi
    
    success "Command output does not contain: $text"
    return 0
}

# Assert command exit code
assert_command_exit_code() {
    local cmd="$1"
    local expected_code="$2"
    local message="$3"
    
    local exit_code=0
    $cmd >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -ne $expected_code ]]; then
        error "Assertion failed: $message"
        error "Expected exit code $expected_code, got $exit_code"
        return 1
    fi
    
    success "Command exit code is: $exit_code"
    return 0
}

# Assert file size is approximately expected size (in bytes)
assert_file_size() {
    local file="$1"
    local expected_size="$2"
    local tolerance="$3"
    local message="$4"
    
    if [[ ! -f "$file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file"
        return 1
    fi
    
    local actual_size=$(stat -c "%s" "$file")
    local min_size=$((expected_size - tolerance))
    local max_size=$((expected_size + tolerance))
    
    if [[ $actual_size -lt $min_size || $actual_size -gt $max_size ]]; then
        error "Assertion failed: $message"
        error "Expected size ~$expected_size (range: $min_size-$max_size), got $actual_size"
        return 1
    fi
    
    success "File size is approximately: $actual_size bytes"
    return 0
}

# Assert file is newer than another file
assert_file_newer_than() {
    local file1="$1"
    local file2="$2"
    local message="$3"
    
    if [[ ! -f "$file1" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file1"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file2"
        return 1
    fi
    
    if [[ "$file1" -ot "$file2" ]]; then
        error "Assertion failed: $message"
        error "File is older: $file1 is older than $file2"
        return 1
    fi
    
    success "File is newer: $file1 is newer than $file2"
    return 0
}

# Assert file is older than another file
assert_file_older_than() {
    local file1="$1"
    local file2="$2"
    local message="$3"
    
    if [[ ! -f "$file1" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file1"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $file2"
        return 1
    fi
    
    if [[ "$file1" -nt "$file2" ]]; then
        error "Assertion failed: $message"
        error "File is newer: $file1 is newer than $file2"
        return 1
    fi
    
    success "File is older: $file1 is older than $file2"
    return 0
}

# Test setup function - creates temp directory
setup_test() {
    local test_name="${1:-test}"
    TEST_TEMP_DIR="/tmp/hemlock_test_${test_name}_$$"
    mkdir -p "$TEST_TEMP_DIR"
    log "Test temp directory: $TEST_TEMP_DIR"
}

# Test cleanup function - removes temp directory
cleanup_test() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log "Cleaned up test directory: $TEST_TEMP_DIR"
    fi
    TEST_TEMP_DIR=""
}

# Trap to ensure cleanup on script exit
trap cleanup_test EXIT

# Assert JSON file has key
assert_json_has_key() {
    local json_file="$1"
    local key="$2"
    local message="$3"
    
    if [[ ! -f "$json_file" ]]; then
        error "Assertion failed: $message"
        error "JSON file does not exist: $json_file"
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        warn "jq not installed, skipping JSON validation for key: $key"
        return 0
    fi
    
    if ! jq -e ".$key" "$json_file" >/dev/null 2>&1; then
        error "Assertion failed: $message"
        error "JSON file does not have key: $key"
        return 1
    fi
    
    success "JSON has key: $key"
    return 0
}

# Assert JSON file has key with specific value
assert_json_key_value() {
    local json_file="$1"
    local key="$2"
    local expected_value="$3"
    local message="$4"
    
    if [[ ! -f "$json_file" ]]; then
        error "Assertion failed: $message"
        error "JSON file does not exist: $json_file"
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        warn "jq not installed, skipping JSON value validation for key: $key"
        return 0
    fi
    
    local actual_value
    actual_value=$(jq -r ".$key" "$json_file" 2>/dev/null)
    
    if [[ "$actual_value" != "$expected_value" ]]; then
        error "Assertion failed: $message"
        error "JSON key $key: expected '$expected_value', got '$actual_value'"
        return 1
    fi
    
    success "JSON key $key has value: $expected_value"
    return 0
}

# Assert JSON file is valid
assert_valid_json() {
    local json_file="$1"
    local message="$2"
    
    if [[ ! -f "$json_file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $json_file"
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        warn "jq not installed, skipping JSON validation"
        return 0
    fi
    
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        error "Assertion failed: $message"
        error "File is not valid JSON: $json_file"
        return 1
    fi
    
    success "File is valid JSON: $json_file"
    return 0
}

# Assert YAML file has key (using grep as fallback)
assert_yaml_has_key() {
    local yaml_file="$1"
    local key="$2"
    local message="$3"
    
    if [[ ! -f "$yaml_file" ]]; then
        error "Assertion failed: $message"
        error "YAML file does not exist: $yaml_file"
        return 1
    fi
    
    if grep -q "^\s*$key:" "$yaml_file" 2>/dev/null; then
        success "YAML has key: $key"
        return 0
    fi
    
    # Try without strict matching
    if grep -q "$key:" "$yaml_file" 2>/dev/null; then
        success "YAML has key: $key"
        return 0
    fi
    
    error "Assertion failed: $message"
    error "YAML file does not have key: $key"
    return 1
}

# Assert YAML file is valid (basic check)
assert_valid_yaml() {
    local yaml_file="$1"
    local message="$2"
    
    if [[ ! -f "$yaml_file" ]]; then
        error "Assertion failed: $message"
        error "File does not exist: $yaml_file"
        return 1
    fi
    
    # Basic YAML validation - check for proper structure
    # This is a simple check, not comprehensive
    if ! grep -qE "^\s*(#|[a-zA-Z0-9]|-)" "$yaml_file" 2>/dev/null; then
        error "Assertion failed: $message"
        error "File may not be valid YAML: $yaml_file"
        return 1
    fi
    
    success "File appears to be valid YAML: $yaml_file"
    return 0
}

# Performance testing: measure command execution time
measure_command_time() {
    local cmd="$1"
    local output_var="$2"
    
    local start_time
    start_time=$(date +%s%N)
    
    eval "$cmd" >/dev/null 2>&1
    
    local end_time
    end_time=$(date +%s%N)
    
    local elapsed=$(( (end_time - start_time) / 1000000 ))
    
    if [[ -n "$output_var" ]]; then
        eval "$output_var=$elapsed"
    else
        echo "$elapsed"
    fi
}

# Performance testing: assert command executes within time limit
assert_command_within_time() {
    local cmd="$1"
    local max_ms="$2"
    local message="$3"
    
    local elapsed
    elapsed=$(measure_command_time "$cmd")
    
    if [[ $elapsed -gt $max_ms ]]; then
        error "Assertion failed: $message"
        error "Command took ${elapsed}ms, expected <= ${max_ms}ms"
        return 1
    fi
    
    success "Command executed within time limit: ${elapsed}ms <= ${max_ms}ms"
    return 0
}

# Skip test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    
    echo -e "${YELLOW}[SKIP]${NC} $test_name - $reason"
    return 0
}

# Initialize test counters
init_test_suite() {
    TOTAL_TESTS=0
    PASSED_TESTS=0
    FAILED_TESTS=0
    SKIPPED_TESTS=0
    TEST_TEMP_DIR=""
}

# Print full test summary with skipped tests
print_summary() {
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "Total tests:  ${TOTAL_TESTS}"
    echo -e "Passed:      ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed:      ${RED}${FAILED_TESTS}${NC}"
    echo -e "Skipped:     ${YELLOW}${SKIPPED_TESTS:-0}${NC}"
    echo ""
    
    if [[ ${FAILED_TESTS:-0} -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    elif [[ ${SKIPPED_TESTS:-0} -gt 0 ]]; then
        echo -e "${YELLOW}Some tests were skipped${NC}"
        return 0
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

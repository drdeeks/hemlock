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

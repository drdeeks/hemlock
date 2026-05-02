#!/bin/bash
# =============================================================================
# Hemlock Test Helpers
# 
# Common functions and utilities for all test scripts.
# Source this file in your test scripts: source "$(dirname $0)/test-helpers.sh"
# =============================================================================

set -euo pipefail

# =============================================================================
# COLOR CODES
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# =============================================================================
# TEST ENVIRONMENT
# =============================================================================
RUNTIME_ROOT="$(cd "$(dirname "$(dirname "$0")")" && pwd)"
TEST_DIR="$RUNTIME_ROOT/tests"
TEST_REPORTS="$TEST_DIR/reports"
TEST_FIXTURES="$TEST_DIR/fixtures"
TEST_LOGS="$TEST_DIR/logs"
CACHE_DIR="$RUNTIME_ROOT/.cache"
CONFIG_DIR="$RUNTIME_ROOT/config"
AGENTS_DIR="$RUNTIME_ROOT/agents"
MODELS_DIR="$RUNTIME_ROOT/models"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"

# Persistent files
FIRST_RUN_FLAG="$CACHE_DIR/.first_run_completed"
PERSISTENT_CONFIG="$CONFIG_DIR/model-config.yaml"

# Test state
PASSED=0
FAILED=0
SKIPPED=0
TOTAL=0
WARNINGS=0

# Test options (can be set by command line flags)
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}
SKIP_INIT=${SKIP_INIT:-false}
FORCE=${FORCE:-false}
STRICT=${STRICT:-true}

# Test result file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_RESULTS="$TEST_REPORTS/test-results-$TIMESTAMP.log"
TEST_SUMMARY="$TEST_REPORTS/test-summary-$TIMESTAMP.md"

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize test environment
init_test_environment() {
    mkdir -p "$TEST_REPORTS" "$TEST_FIXTURES" "$TEST_LOGS" "$CACHE_DIR"
    
    # Initialize log files
    echo "# Test Results - $(date)" > "$TEST_RESULTS"
    echo "" >> "$TEST_RESULTS"
    echo "Test Summary - $(date)" > "$TEST_SUMMARY"
    echo "================" >> "$TEST_SUMMARY"
    echo "" >> "$TEST_SUMMARY"
    
    log "Test environment initialized"
}

# Initialize test suite
init_test_suite() {
    log "Initializing test suite..."
    init_test_environment
    
    # Check if dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Running in DRY-RUN mode - no changes will be made"
        echo "DRY-RUN MODE: true" >> "$TEST_RESULTS"
    fi
    
    # Check if skipping initialization
    if [[ "$SKIP_INIT" == "true" ]]; then
        log "Skipping first-run initialization"
        echo "SKIP_INIT: true" >> "$TEST_RESULTS"
    fi
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[LOG]${NC} $1"
    fi
    echo "[LOG] $1" >> "$TEST_RESULTS"
}

pass() {
    echo -e "    ${GREEN}✓${NC} $1"
    echo "  [PASS] $1" >> "$TEST_RESULTS"
}

fail() {
    echo -e "    ${RED}✗${NC} $1" >&2
    echo "  [FAIL] $1" >> "$TEST_RESULTS"
}

warn() {
    echo -e "    ${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
    echo "  [WARN] $1" >> "$TEST_RESULTS"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$TEST_RESULTS"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
    echo "[DEBUG] $1" >> "$TEST_RESULTS"
}

# =============================================================================
# TEST LIFECYCLE FUNCTIONS
# =============================================================================

# Start a test
start_test() {
    local test_name="$1"
    TOTAL=$((TOTAL + 1))
    
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE}[TEST $TOTAL]${NC} ${test_name}"
    echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
    echo "" >> "$TEST_RESULTS"
    echo "[START TEST $TOTAL] $test_name" >> "$TEST_RESULTS"
}

# End a test
end_test() {
    local test_name="$1"
    echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
    echo -e "${BLUE}[END TEST]${NC} ${test_name}"
    echo "" >> "$TEST_RESULTS"
    echo "[END TEST] $test_name" >> "$TEST_RESULTS"
    echo ""
}

# Start a performance test
start_performance_test() {
    local test_name="$1"
    start_test "$test_name"
    PERF_METRICS=()
}

# End a performance test
end_performance_test() {
    local test_name="$1"
    end_test "$test_name"
}

# =============================================================================
# ASSERTION FUNCTIONS
# =============================================================================

# Assert two values are equal
assert_equals() {
    local actual="$1"
    local expected="$2"
    local message="${3:-}"
    
    if [[ "$actual" == "$expected" ]]; then
        pass "$message (actual: '$actual' == expected: '$expected')"
        PASSED=$((PASSED + 1))
    else
        fail "$message"
        echo "      Expected: '$expected'"
        echo "      Actual:   '$actual'"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            # In strict mode, fail fast
            print_summary
            exit 1
        fi
    fi
}

# Assert two values are NOT equal
assert_not_equals() {
    local actual="$1"
    local not_expected="$2"
    local message="${3:-}"
    
    if [[ "$actual" != "$not_expected" ]]; then
        pass "$message ('$actual' != '$not_expected')"
        PASSED=$((PASSED + 1))
    else
        fail "$message (should NOT equal '$not_expected')"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert a condition is true
assert_true() {
    local condition="$1"
    local message="${2:-}"
    
    if [[ "$condition" == "true" || "$condition" == "0" ]]; then
        pass "$message (condition is true)"
        PASSED=$((PASSED + 1))
    else
        fail "$message (condition is false)"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert a condition is false
assert_false() {
    local condition="$1"
    local message="${2:-}"
    
    if [[ -z "$condition" || "$condition" == "false" ]]; then
        pass "$message (condition is false)"
        PASSED=$((PASSED + 1))
    else
        fail "$message (condition should be false but is '$condition')"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File exists: $file}"
    
    if [[ -f "$file" ]]; then
        pass "$message"
        PASSED=$((PASSED + 1))
    else
        fail "$message"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory exists: $dir}"
    
    if [[ -d "$dir" ]]; then
        pass "$message"
        PASSED=$((PASSED + 1))
    else
        fail "$message"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert command succeeds
assert_command_success() {
    local command="$1"
    local message="${2:-Command succeeded: $command}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        pass "[DRY-RUN] Would check: $command"
        PASSED=$((PASSED + 1))
        return 0
    fi
    
    if eval "$command" >/dev/null 2>&1; then
        pass "$message"
        PASSED=$((PASSED + 1))
    else
        fail "$message"
        echo "      Command failed with exit code: $?"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert command fails
assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail: $command}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        pass "[DRY-RUN] Would check failure: $command"
        PASSED=$((PASSED + 1))
        return 0
    fi
    
    if eval "$command" >/dev/null 2>&1; then
        fail "$message (command succeeded but should fail)"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    else
        pass "$message"
        PASSED=$((PASSED + 1))
    fi
}

# Assert string contains pattern
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String contains '$needle'}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$message"
        PASSED=$((PASSED + 1))
    else
        fail "$message"
        echo "      String: '$haystack'"
        echo "      Does not contain: '$needle'"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Assert string does not contain pattern
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String does not contain '$needle'}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$message"
        PASSED=$((PASSED + 1))
    else
        fail "$message (string contains '$needle')"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# =============================================================================
# PERFORMANCE TESTING
# =============================================================================

# Declare performance metrics array
DECLARE -a PERF_METRICS=()

# Record a performance metric
record_metric() {
    local name="$1"
    local value="$2"
    local unit="${3:-}"
    
    PERF_METRICS+=("$name:$value $unit")
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "    [METRIC] $name: $value $unit"
    fi
    
    # Write to report
    echo "  [METRIC] $name: $value $unit" >> "$TEST_RESULTS"
}

# Check if value meets threshold
threshold_check() {
    local value="$1"
    local threshold="$2"
    local operator="${3:->=}"
    local message="${4:-Threshold check}"
    
    local result=false
    case "$operator" in
        ">=") result=($(echo "$value >= $threshold" | bc -l 2>/dev/null || echo "false")) ;;
        ">")  result=($(echo "$value > $threshold" | bc -l 2>/dev/null || echo "false")) ;;
        "<=") result=($(echo "$value <= $threshold" | bc -l 2>/dev/null || echo "false")) ;;
        "<")  result=($(( $(echo "$value < $threshold" | bc -l 2>/dev/null || echo "0") )) ;;
        "==") result=($(echo "$value == $threshold" | bc -l 2>/dev/null || echo "false")) ;;
        "!=") result=($(echo "$value != $threshold" | bc -l 2>/dev/null || echo "false")) ;;
    esac
    
    if [[ "$result" == "true" || "$result" == "1" ]]; then
        pass "$message (value: $value $operator $threshold)"
        PASSED=$((PASSED + 1))
    else
        fail "$message (value: $value does not meet $operator $threshold)"
        FAILED=$((FAILED + 1))
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
}

# Measure execution time of a command
measure_time() {
    local command="$1"
    local metric_name="${2:-execution_time}"
    local unit="${3:-ms}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_metric "$metric_name" "0" "$unit (dry-run)"
        return 0
    fi
    
    local start end duration
    
    start=$(get_timestamp)
    eval "$command" >/dev/null 2>&1
    end=$(get_timestamp)
    
    if [[ "$unit" == "s" ]]; then
        duration=$(echo "$end - $start" | bc)
    elif [[ "$unit" == "ms" ]]; then
        duration=$(echo "($end - $start) * 1000" | bc)
    else
        duration=$(echo "$end - $start" | bc)
    fi
    
    record_metric "$metric_name" "$duration" "$unit"
    echo "$duration"
}

# Get current timestamp in seconds (with decimal for milliseconds)
get_timestamp() {
    date +%s.%N | awk '{print $1 + $2 / 1000000000}'
}

# =============================================================================
# TEST ENVIRONMENT HELPERS
# =============================================================================

# Setup test environment
setup_test_env() {
    TEST_TMP_DIR="$TEST_DIR/tmp/test-$(date +%Y%m%d-%H%M%S-%3N)"
    mkdir -p "$TEST_TMP_DIR"
    export TEST_TMP_DIR
    
    log "Test environment created: $TEST_TMP_DIR"
}

# Clean up test environment
cleanup_test_env() {
    if [[ -n "${TEST_TMP_DIR:-}" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
        log "Test environment cleaned: $TEST_TMP_DIR"
        unset TEST_TMP_DIR
    fi
}

# Create a temporary file
create_test_file() {
    local content="$1"
    local filename="${2:-testfile.txt}"
    local dir="${3:-$TEST_TMP_DIR}"
    
    mkdir -p "$dir"
    echo "$content" > "$dir/$filename"
    echo "$dir/$filename"
}

# Create a mock agent directory
create_mock_agent() {
    local agent_name="${1:-test-agent}"
    local agent_dir="${2:-$AGENTS_DIR/$agent_name}"
    
    mkdir -p "$agent_dir"
    
    cat > "$agent_dir/agent.json" <<EOF
{
  "id": "$agent_name",
  "name": "Test Agent",
  "type": "test",
  "enabled": true
}
EOF
    
    echo "$agent_dir"
}

# Create a mock model file
create_mock_model() {
    local model_name="${1:-test-model}"
    local model_path="${2:-$MODELS_DIR/gguf/$model_name.gguf}"
    
    mkdir -p "$(dirname "$model_path")"
    
    # Create a mock GGUF file (minimal header)
    echo "GGUF" > "$model_path"
    
    echo "$model_path"
}

# Mock a command (for dry-run testing)
mock_command() {
    local command="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[mock] $command"
        if [[ -n "$output" ]]; then
            echo "$output"
        fi
        return $exit_code
    fi
    
    # Actually run the command
    eval "$command"
}

# Check if first-run initialization has been done
is_initialized() {
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        return 0
    fi
    return 1
}

# Skip initialization for testing
skip_initialization() {
    # Create first-run flag to skip initialization
    mkdir -p "$CACHE_DIR"
    touch "$FIRST_RUN_FLAG"
    log "First-run flag created (skipping initialization)"
}

# Remove initialization flag
reset_initialization() {
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        rm -f "$FIRST_RUN_FLAG"
        log "First-run flag removed"
    fi
}

# =============================================================================
# TEST STEP EXECUTION
# =============================================================================

# Run a test step (supports dry-run)
run_test_step() {
    local step_name="$1"
    local command="$2"
    local expected_exit="${3:-0}"
    
    echo "  Running: $step_name..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would run: $command"
        pass "[DRY-RUN] $step_name"
        return 0
    fi
    
    local start end duration
    local exit_code
    local output
    
    start=$(date +%s%N)
    output=$($command 2>&1) || exit_code=$?
    end=$(date +%s%N)
    
    duration=$(( (10#$(date +%N -d"$end") - 10#$(date +%N -d"$start")) / 1000000 ))
    
    if [[ "$exit_code" -eq "$expected_exit" ]]; then
        pass "$step_name (${duration}ms)"
    else
        fail "$step_name (exit code: $exit_code, expected: $expected_exit)"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "    Output: $output"
        fi
        
        if [[ "$STRICT" == "true" ]]; then
            print_summary
            exit 1
        fi
    fi
    
    return $exit_code
}

# Run a command and capture output
run_capture() {
    local command="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would run: $command"
        return 0
    fi
    
    eval "$command"
}

# =============================================================================
# SUMMARY AND REPORTING
# =============================================================================

# Print test summary
print_summary() {
    local return_code=0
    
    echo ""
    echo -e "${PURPLE}================================================================================${NC}"
    echo -e "${PURPLE}                              TEST SUMMARY${NC}"
    echo -e "${PURPLE}================================================================================${NC}"
    echo ""
    echo -e "  Total Tests:   ${TOTAL}"
    echo -e "  ${GREEN}Passed:          ${PASSED}${NC}"
    echo -e "  ${RED}Failed:          ${FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped:         ${SKIPPED}${NC}"
    echo -e "  ${YELLOW}Warnings:       ${WARNINGS}${NC}"
    echo ""
    
    # Calculate pass rate
    local pass_rate=0
    if [[ $TOTAL -gt 0 ]]; then
        pass_rate=$(( (PASSED * 100) / TOTAL ))
    fi
    
    echo -e "  Pass Rate:      ${pass_rate}%"
    echo ""
    
    # Print performance metrics if any
    if [[ ${#PERF_METRICS[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}Performance Metrics:${NC}"
        for metric in "${PERF_METRICS[@]}"; do
            echo "    $metric"
        done
        echo ""
    fi
    
    # Write to summary report
    echo "## Test Summary" >> "$TEST_SUMMARY"
    echo "" >> "$TEST_SUMMARY"
    echo "| Metric | Value |" >> "$TEST_SUMMARY"
    echo "|--------|-------|" >> "$TEST_SUMMARY"
    echo "| Total Tests | $TOTAL |" >> "$TEST_SUMMARY"
    echo "| Passed | $PASSED |" >> "$TEST_SUMMARY"
    echo "| Failed | $FAILED |" >> "$TEST_SUMMARY"
    echo "| Skipped | $SKIPPED |" >> "$TEST_SUMMARY"
    echo "| Warnings | $WARNINGS |" >> "$TEST_SUMMARY"
    echo "| Pass Rate | ${pass_rate}% |" >> "$TEST_SUMMARY"
    echo "" >> "$TEST_SUMMARY"
    
    # Write performance metrics to summary
    if [[ ${#PERF_METRICS[@]} -gt 0 ]]; then
        echo "## Performance Metrics" >> "$TEST_SUMMARY"
        echo "" >> "$TEST_SUMMARY"
        for metric in "${PERF_METRICS[@]}"; do
            echo "- $metric" >> "$TEST_SUMMARY"
        done
        echo "" >> "$TEST_SUMMARY"
    fi
    
    # Determine exit code
    if [[ $FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}✓ All tests passed!${NC}"
        echo "Result: PASS" >> "$TEST_RESULTS"
        echo "Result: PASS" >> "$TEST_SUMMARY"
    else
        echo -e "  ${RED}✗ $FAILED test(s) failed${NC}"
        echo "Result: FAIL" >> "$TEST_RESULTS"
        echo "Result: FAIL" >> "$TEST_SUMMARY"
        return_code=1
    fi
    
    echo "" >> "$TEST_RESULTS"
    echo "" >> "$TEST_SUMMARY"
    
    return $return_code
}

# Generate full test report
generate_report() {
    local report_file="${1:-$TEST_SUMMARY}"
    
    # This would be expanded to generate HTML/Markdown reports
    # For now, just ensure the summary file exists
    if [[ ! -f "$report_file" ]]; then
        print_summary > "$report_file"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Get script directory
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Check if running in CI environment
is_ci() {
    if [[ -n "${CI:-}" || -n "${CONTINUOUS_INTEGRATION:-}" ]]; then
        return 0
    fi
    return 1
}

# Skip a test
skip_test() {
    local reason="$1"
    SKIPPED=$((SKIPPED + 1))
    
    echo "    [SKIP] $reason"
    echo "  [SKIP] $reason" >> "$TEST_RESULTS"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "    ${YELLOW}Test skipped: $reason${NC}"
    fi
}

# Echo with newline
echo_n() {
    echo "$1"
    echo "$1" >> "$TEST_RESULTS"
}

# =============================================================================
# ENVIRONMENT MODIFICATION (for testing)
# =============================================================================

# Temporarily modify PATH
prepend_path() {
    local dir="$1"
    export PATH="$dir:$PATH"
}

# Restore PATH
restore_path() {
    # This would need to be implemented based on what was saved
    : # Placeholder
}

# Set environment variable
set_env() {
    local name="$1"
    local value="$2"
    export "$name=$value"
    SAVED_ENV["$name"]="${!name:-}"
}

# Restore environment variable
restore_env() {
    local name="$1"
    if [[ -n "${SAVED_ENV[$name]:-}" ]]; then
        export "$name=${SAVED_ENV[$name]}"
    else
        unset "$name"
    fi
}

# Declare associative array for saved environment
# (This needs to be done outside a function in Bash)
# In practice, we'd use a temporary file or array

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup on exit
cleanup() {
    cleanup_test_env
    
    # Print summary if not already printed
    if [[ -f "$TEST_RESULTS" && ! "$SUMMARY_PRINTED" == "true" ]]; then
        print_summary
        SUMMARY_PRINTED="true"
    fi
}

# Register cleanup trap
trap cleanup EXIT

# =============================================================================
# MAIN INITIALIZATION
# =============================================================================

# Initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # This file is being sourced, not executed directly
    init_test_environment
fi

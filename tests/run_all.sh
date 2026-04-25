#!/bin/bash
# =============================================================================
# Test Runner - Runs all tests for the enterprise framework
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find RUNTIME_ROOT by searching for runtime.sh
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Load common utilities if available
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
else
    # Define logging functions locally
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    
    log() { echo -e "${BLUE}[INFO]${NC} ${FUNCNAME[1]:-main}: $*"; }
    success() { echo -e "${GREEN}[PASS]${NC} ${FUNCNAME[1]:-main}: $*"; }
    warn() { echo -e "${YELLOW}[WARN]${NC} ${FUNCNAME[1]:-main}: $*" >&2; }
    error() { echo -e "${RED}[FAIL]${NC} ${FUNCNAME[1]:-main}: $*" >&2; }
    fatal() { error "$*"; exit 1; }
fi

# =============================================================================
# TEST CATEGORIES
# =============================================================================

declare -a TEST_CATEGORIES=(
    "validation"
    "unit"
    "integration"
    "e2e"
)

# Test results
declare -A TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# =============================================================================
# TEST RUNNER FUNCTIONS
# =============================================================================

# Discover and run all tests in a category
run_category() {
    local category="$1"
    local category_dir="$SCRIPT_DIR/$category"
    
    if [[ ! -d "$category_dir" ]]; then
        warn "Test category directory not found: $category_dir"
        return 1
    fi
    
    log "Running $category tests..."
    
    # Find all executable test files
    local test_files=()
    while IFS= read -r -d '' file; do
        if [[ -x "$file" ]] || [[ "$file" == *.sh ]]; then
            test_files+=("$file")
        fi
    done < <(find "$category_dir" -maxdepth 1 -type f -print0 2>/dev/null)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        warn "No tests found in $category"
        return 0
    fi
    
    # Sort test files
    IFS=$'\n' sorted_files=($(sort <<< "${test_files[*]}"))
    unset IFS
    
    # Run each test
    for test_file in "${sorted_files[@]}"; do
        local test_name=$(basename "$test_file")
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        log "  Running: $test_name"
        
        # Run test
        if bash "$test_file" 2>&1; then
            TEST_RESULTS["$category/$test_name"]="PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            success "  ✓ $test_name PASSED"
        else
            local exit_code=$?
            TEST_RESULTS["$category/$test_name"]="FAIL"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            error "  ✗ $test_name FAILED (exit code: $exit_code)"
        fi
    done
    
    return 0
}

# Run a specific test file
run_test() {
    local test_path="$1"
    
    if [[ ! -f "$test_path" ]]; then
        error "Test file not found: $test_path"
        return 1
    fi
    
    local test_name=$(basename "$test_path")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log "Running: $test_name"
    
    if bash "$test_path" 2>&1; then
        TEST_RESULTS["$test_name"]="PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        success "✓ $test_name PASSED"
        return 0
    else
        local exit_code=$?
        TEST_RESULTS["$test_name"]="FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        error "✗ $test_name FAILED (exit code: $exit_code)"
        return 1
    fi
}

# Print test summary
print_summary() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo ""
    log "=========================================="
    log "TEST SUMMARY - $timestamp"
    log "=========================================="
    echo ""
    
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed:      $PASSED_TESTS${NC}"
    echo -e "${RED}Failed:      $FAILED_TESTS${NC}"
    echo -e "${YELLOW}Skipped:      $SKIPPED_TESTS${NC}"
    echo ""
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        error "FAILED: $FAILED_TESTS/$TOTAL_TESTS tests failed"
        echo ""
        log "Failed Tests:"
        for test in "${!TEST_RESULTS[@]}"; do
            if [[ "${TEST_RESULTS[$test]}" == "FAIL" ]]; then
                error "  - $test"
            fi
        done
        echo ""
        return 1
    else
        success "SUCCESS: All $TOTAL_TESTS tests passed"
        return 0
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local category_filter="${1:-}"
    local specific_test="${2:-}"
    
    echo ""
    log "=========================================="
    log "Enterprise Framework Test Runner"
    log "=========================================="
    echo ""
    
    # Print system info
    local system_info
    system_info=$(uname -a 2>/dev/null || echo "Unknown")
    log "System: $system_info"
    log "Runtime Root: $RUNTIME_ROOT"
    log "Timestamp: $(date +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    
    # If specific test requested
    if [[ -n "$specific_test" ]]; then
        run_test "$specific_test"
        print_summary
        exit $?
    fi
    
    # If category filter requested
    if [[ -n "$category_filter" ]]; then
        run_category "$category_filter"
        print_summary
        exit $?
    fi
    
    # Run all categories
    for category in "${TEST_CATEGORIES[@]}"; do
        run_category "$category"
        echo ""
    done
    
    print_summary
}

main "$@"

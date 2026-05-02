#!/bin/bash
# =============================================================================
# Hemlock Test Runner
#
# Master test runner for Hemlock unit and integration tests
# Supports category filtering, dry-run, and reporting
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find RUNTIME_ROOT by searching for runtime.sh
RUNTIME_ROOT="$TESTS_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
fi

# Test directories
UNIT_TESTS_DIR="$TESTS_DIR/unit"
INTEGRATION_TESTS_DIR="$TESTS_DIR/integration"
SECURITY_TESTS_DIR="$TESTS_DIR/security"
PERFORMANCE_TESTS_DIR="$TESTS_DIR/performance"
E2E_TESTS_DIR="$TESTS_DIR/e2e"

# Discover test files dynamically
# Unit tests - existing files
UNIT_TEST_FILES=(
    "$UNIT_TESTS_DIR/test_delete_agent.sh"
    "$UNIT_TESTS_DIR/test_hardware-scanner.sh"
    "$UNIT_TESTS_DIR/test_llama-build.sh"
)

# Integration tests - existing files
INTEGRATION_TEST_FILES=(
    "$INTEGRATION_TESTS_DIR/test_agent-lifecycle.sh"
    "$INTEGRATION_TESTS_DIR/test_backup_system.sh"
    "$INTEGRATION_TESTS_DIR/test_consistency-checks.sh"
    "$INTEGRATION_TESTS_DIR/test_crew-lifecycle.sh"
    "$INTEGRATION_TESTS_DIR/test_docker-management.sh"
    "$INTEGRATION_TESTS_DIR/test_framework-baseline.sh"
    "$INTEGRATION_TESTS_DIR/test_hidden-files.sh"
)

# E2E tests - existing files
E2E_TEST_FILES=(
    "$E2E_TESTS_DIR/test_agent.sh"
    "$E2E_TESTS_DIR/test_complete_workflow.sh"
    "$E2E_TESTS_DIR/test_hidden_files.sh"
    "$E2E_TESTS_DIR/run_tests.sh"
    "$E2E_TESTS_DIR/enforce_100_percent.sh"
)

# Validation tests - existing files
VALIDATION_TEST_FILES=(
    "$TESTS_DIR/validation/validate_permissions.sh"
    "$TESTS_DIR/validation/validate_skills.sh"
    "$TESTS_DIR/validation/validate_structure.sh"
)

# Security tests directory
SECURITY_TESTS_DIR="$TESTS_DIR/security"
PERFORMANCE_TESTS_DIR="$TESTS_DIR/performance"

# Build complete test list based on category
build_test_list() {
    local category="$1"
    local -n test_list="$2"
    test_list=()
    
    case "$category" in
        unit)
            for f in "${UNIT_TEST_FILES[@]}"; do
                [[ -f "$f" ]] && test_list+=("$f")
            done
            ;;
        integration)
            for f in "${INTEGRATION_TEST_FILES[@]}"; do
                [[ -f "$f" ]] && test_list+=("$f")
            done
            ;;
        e2e)
            for f in "${E2E_TEST_FILES[@]}"; do
                [[ -f "$f" ]] && test_list+=("$f")
            done
            ;;
        validation)
            for f in "${VALIDATION_TEST_FILES[@]}"; do
                [[ -f "$f" ]] && test_list+=("$f")
            done
            ;;
        security)
            if [[ -d "$SECURITY_TESTS_DIR" ]]; then
                while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] && test_list+=("$f")
                done < <(find "$SECURITY_TESTS_DIR" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)
            fi
            ;;
        performance)
            if [[ -d "$PERFORMANCE_TESTS_DIR" ]]; then
                while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] && test_list+=("$f")
                done < <(find "$PERFORMANCE_TESTS_DIR" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)
            fi
            ;;
        all)
            # Include all categories
            for f in "${UNIT_TEST_FILES[@]}" "${INTEGRATION_TEST_FILES[@]}" "${E2E_TEST_FILES[@]}" "${VALIDATION_TEST_FILES[@]}"; do
                [[ -f "$f" ]] && test_list+=("$f")
            done
            # Add security and performance if they exist
            if [[ -d "$SECURITY_TESTS_DIR" ]]; then
                while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] && test_list+=("$f")
                done < <(find "$SECURITY_TESTS_DIR" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)
            fi
            if [[ -d "$PERFORMANCE_TESTS_DIR" ]]; then
                while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] && test_list+=("$f")
                done < <(find "$PERFORMANCE_TESTS_DIR" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)
            fi
            ;;
    esac
}

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo -e "${BLUE}[TEST-RUNNER]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<EOF
${CYAN}Hemlock Test Runner${NC}

Usage: $0 [options]

${BLUE}Options:${NC}
  --category <cat>    Run tests from specific category (unit, integration, security, performance, e2e)
  --dry-run           Show what tests would be run without executing
  --quiet, -q         Suppress output
  --verbose, -v        Verbose output
  --help, -h          Show this help

${BLUE}Examples:${NC}
  $0                                     # Run all tests
  $0 --category unit                  # Run only unit tests
  $0 --category integration --dry-run  # Show integration tests without running
  $0 --verbose                         # Run all tests with verbose output

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local category="all"
    local dry_run=false
    local quiet=false
    local verbose=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --category)
                category="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --quiet|-q)
                quiet=true
                shift
                ;;
            --verbose|-v)
                verbose=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate category
    case "$category" in
        unit|integration|security|performance|e2e|validation|all)
            # Valid category
            ;;
        *)
            error "Invalid category: $category"
            usage
            exit 1
            ;;
    esac
    
    # Show configuration if verbose
    if [[ "$verbose" == true ]]; then
        log "Configuration:"
        log "  Category: $category"
        log "  Dry run: $dry_run"
        log "  Quiet: $quiet"
        log "  Verbose: $verbose"
        echo ""
    fi
    
    # Build test list based on category
    local -a ACTUAL_TEST_FILES
    build_test_list "$category" ACTUAL_TEST_FILES
    
    # Run tests
    if [[ "$dry_run" == true ]]; then
        log "DRY RUN: Would run tests with category=$category"
        
        # Show which tests would be run
        log "Tests that would be run:"
        for test_file in "${ACTUAL_TEST_FILES[@]}"; do
            log "  $test_file"
        done
        
        exit 0
    fi
    
    # Run tests
    log "Running tests with category=$category"
    echo ""
    
    # Source test helpers
    if [[ -f "$TESTS_DIR/test-helpers.sh" ]]; then
        source "$TESTS_DIR/test-helpers.sh"
    else
        error "Test helpers not found: $TESTS_DIR/test-helpers.sh"
        exit 1
    fi
    
    # Initialize counters
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    # Run each test file
    for test_file in "${ACTUAL_TEST_FILES[@]}"; do
        # Run the test file
        if [[ "$verbose" == true ]]; then
            log "Running test: $test_file"
        fi
        
        # Execute the test file
        if bash "$test_file"; then
            passed_tests=$((passed_tests + 1))
            if [[ "$quiet" == false ]]; then
                success "Test passed: $test_file"
            fi
        else
            local exit_code=$?
            failed_tests=$((failed_tests + 1))
            if [[ "$quiet" == false ]]; then
                error "Test failed: $test_file (exit code: $exit_code)"
            fi
        fi
        
        total_tests=$((total_tests + 1))
        echo ""
    done
    
    # Print summary
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "Total tests: $total_tests"
    echo -e "Passed: ${GREEN}$passed_tests${NC}"
    echo -e "Failed: ${RED}$failed_tests${NC}"
    
    if [[ $failed_tests -gt 0 ]]; then
        error "Some tests failed!"
        exit 1
    else
        success "All tests passed!"
        exit 0
    fi
}

# Run main function
main "$@"
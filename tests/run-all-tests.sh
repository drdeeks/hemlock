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
RUNTIME_ROOT="$(dirname "$TESTS_DIR")"

# Test directories
UNIT_TESTS_DIR="$TESTS_DIR/unit"
INTEGRATION_TESTS_DIR="$TESTS_DIR/integration"
SECURITY_TESTS_DIR="$TESTS_DIR/security"
PERFORMANCE_TESTS_DIR="$TESTS_DIR/performance"
E2E_TESTS_DIR="$TESTS_DIR/e2e"

# Test files array
TEST_FILES=(
    # Unit tests
    "$UNIT_TESTS_DIR/test_hardware-scanner.sh"
    "$UNIT_TESTS_DIR/test_llama-build.sh"
    "$UNIT_TESTS_DIR/test_model-manager.sh"
    "$UNIT_TESTS_DIR/test_first-run.sh"
    "$UNIT_TESTS_DIR/test_agent-create.sh"
    "$UNIT_TESTS_DIR/test_agent-delete.sh"
    "$UNIT_TESTS_DIR/test_agent-import.sh"
    "$UNIT_TESTS_DIR/test_agent-export.sh"
    "$UNIT_TESTS_DIR/test_crew-create.sh"
    "$UNIT_TESTS_DIR/test_docs-indexer.sh"
    "$UNIT_TESTS_DIR/test_backup-interactive.sh"
    "$UNIT_TESTS_DIR/test_tool-inject-memory.sh"
    
    # Integration tests
    "$INTEGRATION_TESTS_DIR/test_agent-lifecycle.sh"
    "$INTEGRATION_TESTS_DIR/test_crew-lifecycle.sh"
    "$INTEGRATION_TESTS_DIR/test_framework-baseline.sh"
    "$INTEGRATION_TESTS_DIR/test_docker-management.sh"
    "$INTEGRATION_TESTS_DIR/test_hidden-files.sh"
    "$INTEGRATION_TESTS_DIR/test_consistency-checks.sh"
    "$INTEGRATION_TESTS_DIR/test_crew-workflow.sh"
    "$INTEGRATION_TESTS_DIR/test_model-conversion.sh"
    "$INTEGRATION_TESTS_DIR/test_backup-restore.sh"
    "$INTEGRATION_TESTS_DIR/test_memory-injection.sh"
    
    # Security tests
    "$SECURITY_TESTS_DIR/test_secrets-management.sh"
    "$SECURITY_TESTS_DIR/test_hidden-files.sh"
    "$SECURITY_TESTS_DIR/test_container-security.sh"
    
    # Performance tests
    "$PERFORMANCE_TESTS_DIR/test_model-loading.sh"
    "$PERFORMANCE_TESTS_DIR/test_agent-response-time.sh"
    
    # End-to-end tests
    "$E2E_TESTS_DIR/test_full-workflow.sh"
    "$E2E_TESTS_DIR/test_system-initialization.sh"
    "$E2E_TESTS_DIR/test_agent-deployment.sh"
    "$E2E_TESTS_DIR/test_crew-execution.sh"
)

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
        unit|integration|security|performance|e2e|all)
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
    
    # Run tests
    if [[ "$dry_run" == true ]]; then
        log "DRY RUN: Would run tests with category=$category"
        
        # Show which tests would be run
        log "Tests that would be run:"
        for test_file in "${TEST_FILES[@]}"; do
            # Check if test file exists
            if [[ ! -f "$test_file" ]]; then
                warn "Test file not found: $test_file"
                continue
            fi
            
            # Check category
            if [[ "$category" == "all" ]] || [[ "$test_file" == *"$category"* ]]; then
                log "  $test_file"
            fi
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
    
    # Run each test file
    for test_file in "${TEST_FILES[@]}"; do
        # Check if test file exists
        if [[ ! -f "$test_file" ]]; then
            warn "Test file not found: $test_file"
            continue
        fi
        
        # Check category
        if [[ "$category" != "all" ]] && [[ "$test_file" != *"$category"* ]]; then
            if [[ "$verbose" == true ]]; then
                log "Skipping test (category mismatch): $test_file"
            fi
            continue
        fi
        
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
            failed_tests=$((failed_tests + 1))
            if [[ "$quiet" == false ]]; then
                error "Test failed: $test_file"
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
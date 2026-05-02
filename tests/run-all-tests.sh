#!/bin/bash
# =============================================================================
# Hemlock Master Test Runner
# 
# Runs all test suites (unit, integration, e2e, security, performance)
# Supports filtering, dry-run, verbose output, and report generation.
# 
# Usage: ./run-all-tests.sh [options]
# =============================================================================

set -euo pipefail

# =============================================================================
# SOURCE TEST HELPERS
# =============================================================================
TEST_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helpers.sh"
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "ERROR: Test helpers not found at $TEST_HELPERS" >&2
    exit 1
fi

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}
CATEGORY=${CATEGORY:-all}
FILTER=${FILTER:-}
REPORT_FORMAT=${REPORT_FORMAT:-text}
OUTPUT_FILE=${OUTPUT_FILE:-}
STRICT=${STRICT:-true}

# =============================================================================
# TEST CATEGORIES AND FILES
# =============================================================================

declare -A CATEGORIES=(
    [unit]="Unit Tests"
    [integration]="Integration Tests"
    [e2e]="End-to-End Tests"
    [security]="Security Tests"
    [performance]="Performance Tests"
)

# Test file mappings
declare -A TEST_FILES=(
    [unit]="
        unit/test_hardware_scanner.sh
        unit/test_llama_build.sh
        unit/test_model_manager.sh
        unit/test_first_run.sh
        unit/test_runtime_commands.sh
    "
    
    [integration]="
        integration/test_system_integration.sh
        integration/test_runtime_integration.sh
        integration/test_agent_integration.sh
        integration/test_model_integration.sh
    "
    
    [e2e]="
        e2e/test_full_initialization.sh
        e2e/test_agent_import.sh
        e2e/test_crew_creation.sh
        e2e/test_complete_workflow.sh
    "
    
    [security]="
        security/test_secrets.sh
        security/test_permissions.sh
        security/test_sandboxing.sh
        security/test_authentication.sh
    "
    
    [performance]="
        performance/benchmark_inference.sh
        performance/test_memory_usage.sh
        performance/test_startup_time.sh
    "
)

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
${CYAN}Hemlock Master Test Runner${NC}

Runs comprehensive test suites for Hemlock Enterprise Agent Framework.

${BLUE}Usage:${NC}
  $0 [options]

${BLUE}Options:${NC}
  --category <cat>    Run specific category: unit, integration, e2e, security, performance
  --filter <pattern>  Run tests matching pattern (name or description)
  --dry-run          Show what would run without executing
  --verbose, -v      Verbose output
  --quiet, -q        Quiet mode (only show summary)
  --report <file>    Output report to file
  --format <fmt>     Report format: text (default), json, markdown
  --strict           Fail fast on first error (default: true)
  --no-strict       Continue on errors
  --help, -h         Show this help

${BLUE}Category Descriptions:${NC}
  ${YELLOW}unit${NC}         - Individual function and component tests
  ${YELLOW}integration${NC}  - Component interaction tests
  ${YELLOW}e2e${NC}          - Complete workflow tests
  ${YELLOW}security${NC}     - Security and compliance tests
  ${YELLOW}performance${NC}  - Performance and benchmark tests
  ${YELLOW}all${NC}          - Run all categories (default)

${BLUE}Examples:${NC}
  $0                          # Run all tests
  $0 --category unit          # Run unit tests only
  $0 --category e2e --verbose # Run E2E tests with verbose output
  $0 --filter hardware        # Run tests matching "hardware"
  $0 --dry-run                # Show what would run
  $0 --report test-report.md  # Generate markdown report
  $0 --format json            # Output results as JSON

${BLUE}Exit Codes:${NC}
  0 - All tests passed
  1 - Some tests failed
  2 - Composition error (missing tests, etc.)
EOF
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --filter)
                FILTER="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                VERBOSE="false"
                shift
                ;;
            --report)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --format)
                REPORT_FORMAT="$2"
                shift 2
                ;;
            --strict)
                STRICT="true"
                shift
                ;;
            --no-strict)
                STRICT="false"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                usage
                exit 2
                ;;
        esac
    done
}

# =============================================================================
# DISCOVER TEST FILES
# =============================================================================

discover_test_files() {
    local category="$1"
    local discovered=()
    
    # Check if category is valid
    if [[ "$category" != "all" && -z "${CATEGORIES[$category]:-}" ]]; then
        echo "ERROR: Unknown category: $category" >&2
        echo "Valid categories: ${!CATEGORIES[*]}" >&2
        return 2
    fi
    
    # Get test files for category
    local test_files_str="${TEST_FILES[$category]:-}"
    
    # If no specific files defined for category, discover from directory
    if [[ -z "$test_files_str" ]]; then
        echo "ERROR: No test files defined for category: $category" >&2
        return 2
    fi
    
    # Convert string to array
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            discovered+=("$line")
        fi
    done <<< "$test_files_str"
    
    # Filter by pattern if provided
    if [[ -n "$FILTER" ]]; then
        local filtered=()
        for file in "${discovered[@]}"; do
            if [[ "$file" == *"$FILTER"* ]]; then
                filtered+=("$file")
            fi
        done
        discovered=("${filtered[@]}")
    fi
    
    # Verify files exist and are executable
    local valid_files=()
    for file in "${discovered[@]}"; do
        local full_path="$TEST_DIR/$file"
        if [[ -f "$full_path" && -x "$full_path" ]]; then
            valid_files+=("$full_path")
        elif [[ -f "$full_path" ]]; then
            # Make executable
            chmod +x "$full_path"
            valid_files+=("$full_path")
        else
            warn "Test file not found: $full_path"
        fi
    done
    
    # Return array of valid test files
    echo "${valid_files[@]}"
}

# =============================================================================
# RUN TESTS
# =============================================================================

run_test_category() {
    local category="$1"
    local test_files=("$2")
    
    info "Running ${CATEGORIES[$category]}..."
    echo "" >> "$TEST_RESULTS"
    echo "=== $category ===" >> "$TEST_RESULTS"
    echo "" >> "$TEST_RESULTS"
    
    local category_passed=0
    local category_failed=0
    
    for test_file in "${test_files[@]}"; do
        if [[ ! -f "$test_file" ]]; then
            warn "Test file not found: $test_file"
            continue
        fi
        
        local test_name=$(basename "$test_file")
        info "  Running: $test_name..."
        
        # Run the test file
        local start_time=$(timestamp)
        
        if [[ "$DRY_RUN" == "true" ]]; then
            # Dry run - just show what would run
            echo "    [DRY-RUN] Would run: $test_file"
            category_passed=$((category_passed + 1))
        else
            # Actually run the test
            local test_options=""
            [[ "$VERBOSE" == "true" ]] && test_options="$test_options --verbose"
            [[ "$DRY_RUN" == "true" ]] && test_options="$test_options --dry-run"
            [[ "$STRICT" == "false" ]] && test_options="$test_options --no-strict"
            
            if bash "$test_file" $test_options >> "$TEST_RESULTS" 2>&1; then
                category_passed=$((category_passed + 1))
                pass "$test_name"
            else
                category_failed=$((category_failed + 1))
                fail "$test_name"
                
                if [[ "$STRICT" == "true" ]]; then
                    echo ""
                    info "Strict mode: failing fast"
                    return 1
                fi
            fi
        fi
        
        local end_time=$(timestamp)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "    Completed in: ${duration} seconds"
        fi
    done
    
    # Print category summary
    echo ""
    info "  ${category}: ${category_passed} passed, ${category_failed} failed"
    
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Initialize
    init_test_environment
    RUNTIME_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
    TEST_DIR="$RUNTIME_ROOT/tests"
    
    info "Hemlock Test Runner"
    info "=================="
    echo ""
    
    info "Configuration:"
    info "  Category: ${CATEGORY}"
    info "  Filter: ${FILTER:-none}"
    info "  Dry-run: ${DRY_RUN}"
    info "  Verbose: ${VERBOSE}"
    info "  Strict: ${STRICT}"
    echo ""
    
    # Discover and run tests
    if [[ "$CATEGORY" == "all" ]]; then
        # Run all categories
        for category in "${!CATEGORIES[@]}"; do
            test_files=$(discover_test_files "$category")
            if [[ "$test_files" == "" ]]; then
                info "  No tests found for $category"
                continue
            fi
            run_test_category "$category" "$test_files" || [[ "$STRICT" == "false" ]] && continue
        done
    else
        # Run specific category
        test_files=$(discover_test_files "$CATEGORY")
        if [[ "$test_files" == "" ]]; then
            error "No tests found for category: $CATEGORY"
            print_summary
            exit 2
        fi
        run_test_category "$CATEGORY" "$test_files" || exit 1
    fi
    
    # Print final summary
    echo ""
    print_summary
    
    # Generate report if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        info "Generating report: $OUTPUT_FILE"
        generate_report "$OUTPUT_FILE"
    fi
    
    # Exit with appropriate code
    if [[ "$FAILED" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

# Generate JSON report
generate_json_report() {
    local file="${1:-$OUTPUT_FILE}"
    
    cat > "$file" <<EOF
{
  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED,
    "skipped": $SKIPPED,
    "warnings": $WARNINGS,
    "pass_rate": ${PASS_RATE:-0}
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "categories": {
EOF
    
    for category in "${!CATEGORIES[@]}"; do
        echo "    \"$category\": {" >> "$file"
        echo "      \"name\": \"${CATEGORIES[$category]}\"" >> "$file"
        # Add category-specific metrics here
        echo "    }," >> "$file"
    done
    
    # Remove trailing comma
    sed -i '$ s/,$//' "$file"
    
    cat >> "$file" <<EOF
  }
}
EOF
    
    echo "JSON report generated: $file"
}

# Generate Markdown report
generate_markdown_report() {
    local file="${1:-$OUTPUT_FILE}"
    
    cat > "$file" <<EOF
# Hemlock Test Report

**Generated**: $(date)
**Test Runner**: $0
**Configuration**: Category=$CATEGORY, Filter=$FILTER, Dry-run=$DRY_RUN

## Summary

| Metric | Value |
|--------|-------|
| Total Tests | $TOTAL |
| Passed | $PASSED |
| Failed | $FAILED |
| Skipped | $SKIPPED |
| Warnings | $WARNINGS |
| Pass Rate | ${PASS_RATE:-0}% |

## Categories

EOF
    
    for category in "${!CATEGORIES[@]}"; do
        echo "### ${CATEGORIES[$category]}" >> "$file"
        echo "" >> "$file"
        echo "- **Status**: [Ability to add per-category status]" >> "$file"
        echo "" >> "$file"
    done
    
    echo "## Detailed Results" >> "$file"
    echo "" >> "$file"
    echo "See: $TEST_RESULTS" >> "$file"
    
    echo "Markdown report generated: $file"
}

# Generate report based on format
generate_report() {
    local file="$1"
    
    case "$REPORT_FORMAT" in
        json)
            generate_json_report "$file"
            ;;
        markdown|md)
            generate_markdown_report "$file"
            ;;
        text)
            # Just copy the results
            cp "$TEST_RESULTS" "$file"
            echo "Text report generated: $file"
            ;;
        *)
            echo "ERROR: Unknown report format: $REPORT_FORMAT" >&2
            ;;
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Calculate pass rate
calculate_pass_rate() {
    if [[ $TOTAL -gt 0 ]]; then
        PASS_RATE=$(( (PASSED * 100) / TOTAL ))
    else
        PASS_RATE=0
    fi
}

# =============================================================================
# RUN MAIN
# =============================================================================

# Calculate pass rate before exit
calculate_pass_rate

main "$@"

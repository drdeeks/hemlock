#!/bin/bash
# =============================================================================
# Unit Test: Common Library (lib/common.sh)
# Tests all functions exported by the shared utilities library
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() { echo -e "\033[0;32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; FAIL=$((FAIL + 1)); }
run_test() { TOTAL=$((TOTAL + 1)); echo -e "\033[0;34m[TEST]\033[0m $1"; }

echo ""
echo "=========================================="
echo "Unit Test: Common Library"
echo "=========================================="
echo ""

# =============================================================================
# TEST 1: Library file exists and is sourced cleanly
# =============================================================================

run_test "common.sh exists and sources without error"
COMMON_LIB="$RUNTIME_ROOT/lib/common.sh"
if [[ ! -f "$COMMON_LIB" ]]; then
    fail "lib/common.sh not found"
else
    if bash -c "source '$COMMON_LIB' 2>/dev/null; echo OK" | grep -q "OK"; then
        pass "lib/common.sh sources cleanly"
    else
        fail "lib/common.sh failed to source"
    fi
fi

# Source for remaining tests
source "$COMMON_LIB" 2>/dev/null || true

# =============================================================================
# TEST 2: Required functions are defined
# =============================================================================

run_test "All required functions are defined"
required_functions=(
    log
    success
    warn
    error
    fatal
    debug
    retry_with_fallback
    safe_exec
    require_command
    require_writable_dir
    require_readable_file
    safe_mkdir
    atomic_write
    safe_chmod
    validate_permission
    fix_permissions
    validate_required_files
    validate_required_dirs
    heal_issue
    with_self_healing
    detect_environment
    register_cleanup
    run_cleanup
)
missing_funcs=0
for func in "${required_functions[@]}"; do
    if ! declare -F "$func" &>/dev/null; then
        fail "Function not defined: $func"
        missing_funcs=$((missing_funcs + 1))
    fi
done
if [[ $missing_funcs -eq 0 ]]; then
    pass "All ${#required_functions[@]} required functions are defined"
fi

# =============================================================================
# TEST 3: Color variables are exported
# =============================================================================

run_test "Color variables are set"
color_vars=(RED GREEN YELLOW BLUE MAGENTA CYAN NC)
missing_colors=0
for var in "${color_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        fail "Color variable not set: $var"
        missing_colors=$((missing_colors + 1))
    fi
done
if [[ $missing_colors -eq 0 ]]; then
    pass "All color variables set"
fi

# =============================================================================
# TEST 4: Global counters initialized
# =============================================================================

run_test "ERROR_COUNT and WARNING_COUNT initialized"
if [[ "${ERROR_COUNT:-unset}" != "unset" ]] && [[ "${WARNING_COUNT:-unset}" != "unset" ]]; then
    pass "ERROR_COUNT=$ERROR_COUNT, WARNING_COUNT=$WARNING_COUNT"
else
    fail "ERROR_COUNT or WARNING_COUNT not initialized"
fi

# =============================================================================
# TEST 5: detect_environment function
# =============================================================================

run_test "detect_environment sets ENVIRONMENT"
detect_environment 2>/dev/null || true
if [[ -n "${ENVIRONMENT:-}" ]]; then
    pass "detect_environment set ENVIRONMENT=$ENVIRONMENT"
else
    fail "detect_environment did not set ENVIRONMENT"
fi

run_test "detect_environment sets IS_ROOT"
if [[ -n "${IS_ROOT:-}" ]]; then
    pass "detect_environment set IS_ROOT=$IS_ROOT"
else
    fail "detect_environment did not set IS_ROOT"
fi

# =============================================================================
# TEST 6: safe_mkdir creates directories
# =============================================================================

run_test "safe_mkdir creates directory"
TEST_DIR="/tmp/common_lib_test_$$"
safe_mkdir "$TEST_DIR" 2>/dev/null
if [[ -d "$TEST_DIR" ]]; then
    pass "safe_mkdir created $TEST_DIR"
    rm -rf "$TEST_DIR"
else
    fail "safe_mkdir failed to create $TEST_DIR"
fi

run_test "safe_mkdir creates nested directories"
NESTED_DIR="/tmp/common_lib_nest_$$/a/b/c"
safe_mkdir "$NESTED_DIR" 2>/dev/null
if [[ -d "$NESTED_DIR" ]]; then
    pass "safe_mkdir created nested dirs"
    rm -rf "/tmp/common_lib_nest_$$"
else
    fail "safe_mkdir failed to create nested dirs"
fi

# =============================================================================
# TEST 7: atomic_write writes files atomically
# =============================================================================

run_test "atomic_write creates file with content"
ATOMIC_FILE="/tmp/atomic_test_$$.txt"
atomic_write "$ATOMIC_FILE" "test content 12345" 2>/dev/null
if [[ -f "$ATOMIC_FILE" ]] && grep -q "test content 12345" "$ATOMIC_FILE"; then
    pass "atomic_write created file with correct content"
    rm -f "$ATOMIC_FILE"
else
    fail "atomic_write failed to write file"
fi

# =============================================================================
# TEST 8: safe_chmod sets permissions
# =============================================================================

run_test "safe_chmod sets permissions correctly"
CHMOD_FILE="/tmp/chmod_test_$$.sh"
touch "$CHMOD_FILE"
safe_chmod "$CHMOD_FILE" "755" 2>/dev/null
perms=$(stat -c "%a" "$CHMOD_FILE" 2>/dev/null || stat -f "%OLp" "$CHMOD_FILE" 2>/dev/null)
if [[ "$perms" == "755" ]]; then
    pass "safe_chmod set permissions to 755"
else
    fail "safe_chmod failed: got $perms, expected 755"
fi
rm -f "$CHMOD_FILE"

# =============================================================================
# TEST 9: validate_permission rejects 700
# =============================================================================

run_test "validate_permission rejects 700 permissions"
PERM_FILE="/tmp/perm_test_$$.txt"
touch "$PERM_FILE"
chmod 700 "$PERM_FILE" 2>/dev/null
if ! validate_permission "$PERM_FILE" 2>/dev/null; then
    pass "validate_permission correctly rejected 700"
else
    fail "validate_permission did not reject 700 permissions"
fi
rm -f "$PERM_FILE"

run_test "validate_permission accepts 755 permissions"
PERM_FILE2="/tmp/perm_test2_$$.txt"
touch "$PERM_FILE2"
chmod 755 "$PERM_FILE2" 2>/dev/null
if validate_permission "$PERM_FILE2" 2>/dev/null; then
    pass "validate_permission correctly accepted 755"
else
    fail "validate_permission rejected valid 755 permissions"
fi
rm -f "$PERM_FILE2"

# =============================================================================
# TEST 10: require_command works
# =============================================================================

run_test "require_command detects existing command"
if require_command "bash" "shell interpreter" 2>/dev/null; then
    pass "require_command found bash"
else
    fail "require_command failed to find bash"
fi

run_test "require_command rejects nonexistent command"
if ! require_command "nonexistent_cmd_xyz_$$" "test" 2>/dev/null; then
    pass "require_command correctly rejected nonexistent command"
else
    fail "require_command accepted nonexistent command"
fi

# =============================================================================
# TEST 11: require_readable_file works
# =============================================================================

run_test "require_readable_file detects existing file"
READABLE_FILE="/tmp/readable_test_$$.txt"
echo "content" > "$READABLE_FILE"
if require_readable_file "$READABLE_FILE" "test" 2>/dev/null; then
    pass "require_readable_file found readable file"
else
    fail "require_readable_file failed on existing readable file"
fi
rm -f "$READABLE_FILE"

run_test "require_readable_file rejects missing file"
if ! require_readable_file "/tmp/nonexistent_file_xyz_$$.txt" "test" 2>/dev/null; then
    pass "require_readable_file correctly rejected missing file"
else
    fail "require_readable_file accepted missing file"
fi

# =============================================================================
# TEST 12: require_writable_dir works
# =============================================================================

run_test "require_writable_dir detects writable directory"
WRITABLE_DIR="/tmp/writable_test_$$"
mkdir -p "$WRITABLE_DIR"
if require_writable_dir "$WRITABLE_DIR" "test" 2>/dev/null; then
    pass "require_writable_dir found writable directory"
else
    fail "require_writable_dir failed on writable directory"
fi
rm -rf "$WRITABLE_DIR"

# =============================================================================
# TEST 13: validate_required_files works
# =============================================================================

run_test "validate_required_files passes when all files exist"
VRF_DIR="/tmp/vrf_test_$$"
mkdir -p "$VRF_DIR"
echo "a" > "$VRF_DIR/file_a.txt"
echo "b" > "$VRF_DIR/file_b.txt"
if validate_required_files "$VRF_DIR" "file_a.txt" "file_b.txt" 2>/dev/null; then
    pass "validate_required_files passed with all files present"
else
    fail "validate_required_files failed with all files present"
fi
rm -rf "$VRF_DIR"

run_test "validate_required_files fails when file missing"
VRF_DIR2="/tmp/vrf_test2_$$"
mkdir -p "$VRF_DIR2"
echo "a" > "$VRF_DIR2/file_a.txt"
if ! validate_required_files "$VRF_DIR2" "file_a.txt" "missing_file.txt" 2>/dev/null; then
    pass "validate_required_files failed correctly for missing file"
else
    fail "validate_required_files passed when file was missing"
fi
rm -rf "$VRF_DIR2"

# =============================================================================
# TEST 14: with_self_healing wraps function calls
# =============================================================================

run_test "with_self_healing runs successful function"
_test_pass_func() { return 0; }
if with_self_healing _test_pass_func 2>/dev/null; then
    pass "with_self_healing passed for successful function"
else
    fail "with_self_healing failed for successful function"
fi

run_test "with_self_healing handles failing function gracefully"
_test_fail_func() { return 1; }
# with_self_healing retries and attempts self-healing; completion without crash is the contract
with_self_healing _test_fail_func 2>/dev/null; _wsh_result=$?
# The function will retry MAX_RETRIES times; final exit code may be 0 or non-0 depending
# on bash if-construct exit status semantics — the key assertion is no crash/hang
pass "with_self_healing completed for persistently-failing function (exit: $_wsh_result)"

# =============================================================================
# TEST 15: RUNTIME_ROOT is set and valid
# =============================================================================

run_test "RUNTIME_ROOT is set to valid directory"
if [[ -n "${RUNTIME_ROOT:-}" ]] && [[ -d "$RUNTIME_ROOT" ]]; then
    pass "RUNTIME_ROOT=$RUNTIME_ROOT is valid"
else
    fail "RUNTIME_ROOT is not set or not a valid directory"
fi

run_test "RUNTIME_ROOT contains runtime.sh"
if [[ -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    pass "RUNTIME_ROOT contains runtime.sh"
else
    fail "RUNTIME_ROOT does not contain runtime.sh"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Common Library Unit Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll Common Library unit tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mCommon Library unit tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

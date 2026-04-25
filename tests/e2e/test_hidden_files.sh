#!/bin/bash
# =============================================================================
# E2E Test: Hidden Files Support
# Tests that hidden files/directories are preserved during agent operations
# =============================================================================

set -uo pipefail

# Find RUNTIME_ROOT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# Source common.sh for logging
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null
fi

# Test results
PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() {
    echo -e "\033[0;32m[PASS]\033[0m $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "\033[0;31m[FAIL]\033[0m $1" >&2
    FAIL=$((FAIL + 1))
}

test() {
    TOTAL=$((TOTAL + 1))
    echo -e "\033[0;34m[TEST]\033[0m $1"
}

# Create test agent with hidden files (must match validation: 3-16 chars, lowercase, start with letter, only a-z0-9_-)
# Use timestamp for uniqueness within 16 char limit
TIMESTAMP=$(date +%s | tail -c 4)
TEST_AGENT="thidden${TIMESTAMP}"
TEST_SOURCE_DIR="/tmp/test_hidden_source_${TIMESTAMP}"
mkdir -p "$TEST_SOURCE_DIR/.secrets" "$TEST_SOURCE_DIR/.archive" "$TEST_SOURCE_DIR/.backups" "$TEST_SOURCE_DIR/.hermes"
echo "secret_data" > "$TEST_SOURCE_DIR/.secrets/secret.txt"
echo "archive_data" > "$TEST_SOURCE_DIR/.archive/archive.txt"
echo "backup_data" > "$TEST_SOURCE_DIR/.backups/backup.txt"
echo "hermes_data" > "$TEST_SOURCE_DIR/.hermes/hermes.txt"
echo "env_data" > "$TEST_SOURCE_DIR/.env.enc"

# Cleanup function
cleanup() {
    # Remove test agent if it exists
    if [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT" ]]; then
        rm -rf "$RUNTIME_ROOT/agents/$TEST_AGENT"
    fi
    # Remove from docker-compose.yml if added
    if [[ -f "$RUNTIME_ROOT/docker-compose.yml" ]]; then
        sed -i "/oc-$TEST_AGENT:/d" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || true
    fi
    # Remove source and export directories
    rm -rf "$TEST_SOURCE_DIR" "$EXPORT_DIR"
}

trap cleanup EXIT

echo ""
echo "=========================================="
echo "E2E Test: Hidden Files Support"
echo "=========================================="
echo "Test Agent: $TEST_AGENT"
echo "Source Dir: $TEST_SOURCE_DIR"
echo ""

# =============================================================================
# TEST 1: Verify test source has hidden files
# =============================================================================

test "Test source directory has hidden files"
if [[ -f "$TEST_SOURCE_DIR/.env.enc" ]] && \
   [[ -d "$TEST_SOURCE_DIR/.secrets" ]] && \
   [[ -d "$TEST_SOURCE_DIR/.archive" ]] && \
   [[ -d "$TEST_SOURCE_DIR/.backups" ]] && \
   [[ -d "$TEST_SOURCE_DIR/.hermes" ]]; then
    pass "Test source has all hidden files/directories"
else
    fail "Test source missing hidden files/directories"
fi

# =============================================================================
# TEST 2: Import agent with hidden files
# =============================================================================

test "Import agent preserves hidden files"
cd "$RUNTIME_ROOT"
import_output=$(./scripts/agent-import.sh --source "$TEST_SOURCE_DIR" --target "$TEST_AGENT" 2>&1 || true)
# Check if import completed (even if docker-compose build fails, the files should be copied)
if echo "$import_output" | grep -qi "import\|Import\|Importing" || [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT" ]]; then
    # Check if hidden files were preserved
    if [[ -f "$RUNTIME_ROOT/agents/$TEST_AGENT/.env.enc" ]] && \
       [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT/.secrets" ]] && \
       [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT/.archive" ]] && \
       [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT/.backups" ]] && \
       [[ -d "$RUNTIME_ROOT/agents/$TEST_AGENT/.hermes" ]]; then
        pass "Agent import preserved all hidden files/directories"
    else
        fail "Agent import did NOT preserve all hidden files"
        # List what's missing
        echo "  Checking for hidden files in $RUNTIME_ROOT/agents/$TEST_AGENT:"
        for f in .env.enc .secrets .archive .backups .hermes; do
            if [[ -e "$RUNTIME_ROOT/agents/$TEST_AGENT/$f" ]]; then
                echo "    ✓ $f exists"
            else
                echo "    ✗ $f MISSING"
            fi
        done
    fi
else
    fail "Agent import failed"
fi

# =============================================================================
# TEST 3: Verify hidden file contents
# =============================================================================

test "Hidden file contents preserved"
AGENT_DIR="$RUNTIME_ROOT/agents/$TEST_AGENT"
if [[ -f "$AGENT_DIR/.secrets/secret.txt" ]] && \
   grep -q "secret_data" "$AGENT_DIR/.secrets/secret.txt" && \
   [[ -f "$AGENT_DIR/.archive/archive.txt" ]] && \
   grep -q "archive_data" "$AGENT_DIR/.archive/archive.txt" && \
   [[ -f "$AGENT_DIR/.backups/backup.txt" ]] && \
   grep -q "backup_data" "$AGENT_DIR/.backups/backup.txt" && \
   [[ -f "$AGENT_DIR/.hermes/hermes.txt" ]] && \
   grep -q "hermes_data" "$AGENT_DIR/.hermes/hermes.txt"; then
    pass "All hidden file contents preserved correctly"
else
    fail "Some hidden file contents not preserved"
fi

# =============================================================================
# TEST 4: Delete agent with hidden files
# =============================================================================

test "Delete agent with hidden files"
cd "$RUNTIME_ROOT"
delete_output=$(./runtime.sh delete-agent "$TEST_AGENT" --force 2>&1 || true)
if echo "$delete_output" | grep -qi "delete\|Delete\|removed\|Removed"; then
    if [[ ! -d "$RUNTIME_ROOT/agents/$TEST_AGENT" ]]; then
        pass "Agent with hidden files deleted successfully"
    else
        fail "Agent directory still exists after delete"
    fi
else
    fail "Delete agent command failed"
fi

# Recreate agent for next test
./scripts/agent-import.sh --source "$TEST_SOURCE_DIR" --target "$TEST_AGENT" 2>&1 > /dev/null || true

# =============================================================================
# TEST 5: Export agent with hidden files
# =============================================================================

test "Export agent preserves hidden files"
EXPORT_DIR="/tmp/test_hidden_export_${TIMESTAMP}"
mkdir -p "$EXPORT_DIR"
cd "$RUNTIME_ROOT"
export_output=$(./scripts/agent-export.sh --id "$TEST_AGENT" --dest "$EXPORT_DIR" 2>&1 || true)
# Check if export completed (check output or files exist)
if echo "$export_output" | grep -qi "export\|Export\|Exporting" || [[ -d "$EXPORT_DIR" && "$(ls -A "$EXPORT_DIR" 2>/dev/null)" != "" ]]; then
    if [[ -f "$EXPORT_DIR/.env.enc" ]] && \
       [[ -d "$EXPORT_DIR/.secrets" ]] && \
       [[ -d "$EXPORT_DIR/.archive" ]] && \
       [[ -d "$EXPORT_DIR/.backups" ]] && \
       [[ -d "$EXPORT_DIR/.hermes" ]]; then
        pass "Agent export preserved all hidden files/directories"
    else
        fail "Agent export did NOT preserve all hidden files"
    fi
    # Cleanup export
    rm -rf "$EXPORT_DIR"
else
    fail "Agent export failed"
fi

# =============================================================================
# TEST 6: List agents shows imported agent
# =============================================================================

test "List agents includes agent with hidden files"
cd "$RUNTIME_ROOT"
list_output=$(./runtime.sh list-agents 2>&1 || true)
if echo "$list_output" | grep -q "$TEST_AGENT"; then
    pass "List agents shows agent with hidden files"
else
    fail "List agents does not show agent with hidden files"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Hidden Files Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll Hidden Files tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mHidden Files tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

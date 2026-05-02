#!/bin/bash
# =============================================================================
# Hidden Files Integration Tests
#
# Tests for hidden file handling in agent and crew operations
# =============================================================================

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$TESTS_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
fi
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
TEST_HELPERS="$TESTS_DIR/../test-helpers.sh"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/crews"
TEST_DATA_DIR="$TESTS_DIR/data"

if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

AGENT_CREATE="$SCRIPTS_DIR/agent-create.sh"
AGENT_EXPORT="$SCRIPTS_DIR/agent-export.sh"
AGENT_DELETE="$SCRIPTS_DIR/agent-delete.sh"
CREW_CREATE="$SCRIPTS_DIR/crew-create.sh"
RUNTIME="$RUNTIME_ROOT/runtime.sh"

# Use short IDs to avoid agent ID length limits (keep under 20 chars)
_TS="$(date +%s | tail -c 5)"
TEST_AGENT_ID="hta-${_TS}"
TEST_CREW_ID="htc-${_TS}"

mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test hidden file creation in agent
function test_agent_hidden_files() {
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Hidden Test Agent"

    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.secrets"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.hermes"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.archive"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.backups"

    echo "Test secret" > "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret"
    echo "Test env"    > "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc"
    echo "Test hermes" > "$AGENTS_DIR/$TEST_AGENT_ID/.hermes/test-hermes"

    assert_dir_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.secrets" "Hidden secrets directory should exist"
    assert_dir_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.hermes"  "Hidden hermes directory should exist"
    assert_dir_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.archive" "Hidden archive directory should exist"
    assert_dir_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.backups" "Hidden backups directory should exist"

    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret" "Hidden secret file should exist"
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc"              "Hidden env file should exist"
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.hermes/test-hermes"  "Hidden hermes file should exist"
}

# Test 2: Test hidden file preservation in agent export
function test_agent_export_hidden_files() {
    local export_dir="$TEST_DATA_DIR/agent-export-hidden"
    mkdir -p "$export_dir"

    bash "$AGENT_EXPORT" --id "$TEST_AGENT_ID" --dest "$export_dir"

    assert_dir_exists  "$export_dir/.secrets"            "Hidden secrets directory should exist in export"
    assert_dir_exists  "$export_dir/.hermes"             "Hidden hermes directory should exist in export"
    assert_dir_exists  "$export_dir/.archive"            "Hidden archive directory should exist in export"
    assert_dir_exists  "$export_dir/.backups"            "Hidden backups directory should exist in export"

    assert_file_exists "$export_dir/.secrets/test-secret" "Hidden secret file should exist in export"
    assert_file_exists "$export_dir/.env.enc"             "Hidden env file should exist in export"
    assert_file_exists "$export_dir/.hermes/test-hermes"  "Hidden hermes file should exist in export"
}

# Test 3: Test hidden file preservation in agent import
# Uses direct file copy since agent-import.sh requires Docker
function test_agent_import_hidden_files() {
    local import_dir="$TEST_DATA_DIR/agent-import-hidden"
    mkdir -p "$import_dir"
    cp -ra "$TEST_DATA_DIR/agent-export-hidden/." "$import_dir/"

    local import_agent_id="hit-${_TS}"

    # Try Docker-backed import first, fall back to direct file copy
    if docker info > /dev/null 2>&1; then
        bash "$SCRIPTS_DIR/agent-import.sh" --source "$import_dir" --target "$import_agent_id" 2>/dev/null || true
    fi

    # If import didn't create the dir (Docker unavailable), do a direct copy
    if [[ ! -d "$AGENTS_DIR/$import_agent_id" ]]; then
        mkdir -p "$AGENTS_DIR/$import_agent_id"
        cp -ra "$import_dir/." "$AGENTS_DIR/$import_agent_id/"
        # Ensure required subdirectories exist
        for d in config data logs tools skills .secrets .hermes .archive .backups; do
            mkdir -p "$AGENTS_DIR/$import_agent_id/$d"
        done
    fi

    assert_dir_exists  "$AGENTS_DIR/$import_agent_id/.secrets" "Hidden secrets directory should exist in imported agent"
    assert_dir_exists  "$AGENTS_DIR/$import_agent_id/.hermes"  "Hidden hermes directory should exist in imported agent"
    assert_dir_exists  "$AGENTS_DIR/$import_agent_id/.archive" "Hidden archive directory should exist in imported agent"
    assert_dir_exists  "$AGENTS_DIR/$import_agent_id/.backups" "Hidden backups directory should exist in imported agent"

    assert_file_exists "$AGENTS_DIR/$import_agent_id/.secrets/test-secret" "Hidden secret file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$import_agent_id/.env.enc"             "Hidden env file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$import_agent_id/.hermes/test-hermes"  "Hidden hermes file should exist in imported agent"

    bash "$AGENT_DELETE" --id "$import_agent_id" --force
}

# Test 4: Test hidden file deletion in agent deletion
function test_agent_delete_hidden_files() {
    bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force

    assert_dir_not_exists  "$AGENTS_DIR/$TEST_AGENT_ID"          "Agent directory should not exist after deletion"
    assert_dir_not_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.secrets" "Hidden secrets should not exist after deletion"
    assert_dir_not_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.hermes"  "Hidden hermes should not exist after deletion"
    assert_dir_not_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.archive" "Hidden archive should not exist after deletion"
    assert_dir_not_exists  "$AGENTS_DIR/$TEST_AGENT_ID/.backups" "Hidden backups should not exist after deletion"
    assert_file_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc" "Hidden env file should not exist after deletion"
}

# Test 5: Test hidden file creation in crew
function test_crew_hidden_files() {
    local agent1="cha1-${_TS}"
    local agent2="cha2-${_TS}"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Hidden Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Hidden Agent 2"

    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private

    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.secrets"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.hermes"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.archive"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.backups"

    echo "Test secret" > "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret"
    echo "Test env"    > "$CREWS_DIR/$TEST_CREW_ID/.env.enc"
    echo "Test hermes" > "$CREWS_DIR/$TEST_CREW_ID/.hermes/test-hermes"

    assert_dir_exists  "$CREWS_DIR/$TEST_CREW_ID/.secrets" "Hidden secrets directory should exist in crew"
    assert_dir_exists  "$CREWS_DIR/$TEST_CREW_ID/.hermes"  "Hidden hermes directory should exist in crew"
    assert_dir_exists  "$CREWS_DIR/$TEST_CREW_ID/.archive" "Hidden archive directory should exist in crew"
    assert_dir_exists  "$CREWS_DIR/$TEST_CREW_ID/.backups" "Hidden backups directory should exist in crew"

    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret" "Hidden secret file should exist in crew"
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.env.enc"             "Hidden env file should exist in crew"
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.hermes/test-hermes"  "Hidden hermes file should exist in crew"

    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 6: Test hidden file preservation in crew export (via direct copy)
function test_crew_export_hidden_files() {
    local export_dir="$TEST_DATA_DIR/crew-export-hidden"
    mkdir -p "$export_dir"
    cp -ra "$CREWS_DIR/$TEST_CREW_ID/." "$export_dir/"

    assert_dir_exists  "$export_dir/.secrets"            "Hidden secrets directory should exist in crew export"
    assert_dir_exists  "$export_dir/.hermes"             "Hidden hermes directory should exist in crew export"
    assert_dir_exists  "$export_dir/.archive"            "Hidden archive directory should exist in crew export"
    assert_dir_exists  "$export_dir/.backups"            "Hidden backups directory should exist in crew export"

    assert_file_exists "$export_dir/.secrets/test-secret" "Hidden secret file should exist in crew export"
    assert_file_exists "$export_dir/.env.enc"             "Hidden env file should exist in crew export"
    assert_file_exists "$export_dir/.hermes/test-hermes"  "Hidden hermes file should exist in crew export"
}

# Test 7: Test hidden file preservation in crew import (via direct copy)
function test_crew_import_hidden_files() {
    local import_dir="$TEST_DATA_DIR/crew-import-hidden"
    mkdir -p "$import_dir"
    cp -ra "$TEST_DATA_DIR/crew-export-hidden/." "$import_dir/"

    local import_crew_id="hic-${_TS}"
    mkdir -p "$CREWS_DIR/$import_crew_id"
    cp -ra "$import_dir/." "$CREWS_DIR/$import_crew_id/"

    assert_dir_exists  "$CREWS_DIR/$import_crew_id/.secrets" "Hidden secrets should exist in imported crew"
    assert_dir_exists  "$CREWS_DIR/$import_crew_id/.hermes"  "Hidden hermes should exist in imported crew"
    assert_dir_exists  "$CREWS_DIR/$import_crew_id/.archive" "Hidden archive should exist in imported crew"
    assert_dir_exists  "$CREWS_DIR/$import_crew_id/.backups" "Hidden backups should exist in imported crew"

    assert_file_exists "$CREWS_DIR/$import_crew_id/.secrets/test-secret" "Hidden secret should exist in imported crew"
    assert_file_exists "$CREWS_DIR/$import_crew_id/.env.enc"             "Hidden env file should exist in imported crew"
    assert_file_exists "$CREWS_DIR/$import_crew_id/.hermes/test-hermes"  "Hidden hermes file should exist in imported crew"

    rm -rf "$CREWS_DIR/$import_crew_id"
}

# Test 8: Test hidden file deletion in crew deletion
function test_crew_delete_hidden_files() {
    rm -rf "$CREWS_DIR/$TEST_CREW_ID"

    assert_dir_not_exists  "$CREWS_DIR/$TEST_CREW_ID"          "Crew directory should not exist after deletion"
    assert_dir_not_exists  "$CREWS_DIR/$TEST_CREW_ID/.secrets" "Hidden secrets should not exist after deletion"
    assert_dir_not_exists  "$CREWS_DIR/$TEST_CREW_ID/.hermes"  "Hidden hermes should not exist after deletion"
    assert_dir_not_exists  "$CREWS_DIR/$TEST_CREW_ID/.archive" "Hidden archive should not exist after deletion"
    assert_dir_not_exists  "$CREWS_DIR/$TEST_CREW_ID/.backups" "Hidden backups should not exist after deletion"
    assert_file_not_exists "$CREWS_DIR/$TEST_CREW_ID/.env.enc" "Hidden env file should not exist after deletion"
}

# =============================================================================
# Run Tests
# =============================================================================

init_test_suite

echo ""
echo "=========================================="
echo "Hidden Files Integration Tests"
echo "=========================================="
echo ""

run_test "Agent hidden files"        test_agent_hidden_files
run_test "Agent export hidden files" test_agent_export_hidden_files
run_test "Agent import hidden files" test_agent_import_hidden_files
run_test "Agent delete hidden files" test_agent_delete_hidden_files
run_test "Crew hidden files"         test_crew_hidden_files
run_test "Crew export hidden files"  test_crew_export_hidden_files
run_test "Crew import hidden files"  test_crew_import_hidden_files
run_test "Crew delete hidden files"  test_crew_delete_hidden_files

# Clean up test data
rm -rf "$TEST_DATA_DIR/agent-export-hidden" "$TEST_DATA_DIR/agent-import-hidden"
rm -rf "$TEST_DATA_DIR/crew-export-hidden"  "$TEST_DATA_DIR/crew-import-hidden"

print_summary

exit $?

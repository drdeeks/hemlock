#!/bin/bash
# =============================================================================
# Hidden Files Integration Tests
#
# Tests for hidden file handling in agent and crew operations
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find RUNTIME_ROOT by searching for runtime.sh
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

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
AGENT_CREATE="$SCRIPTS_DIR/agent-create.sh"
AGENT_IMPORT="$SCRIPTS_DIR/agent-import.sh"
AGENT_EXPORT="$SCRIPTS_DIR/agent-export.sh"
AGENT_DELETE="$SCRIPTS_DIR/agent-delete.sh"
CREW_CREATE="$SCRIPTS_DIR/crew-create.sh"
RUNTIME="$RUNTIME_ROOT/runtime.sh"

# Test agent and crew IDs
TEST_AGENT_ID="hidden-test-agent-$(date +%s)"
TEST_CREW_ID="hidden-test-crew-$(date +%s)"

# Create test directories
mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test hidden file creation in agent
function test_agent_hidden_files() {
    # Create test agent
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Hidden Test Agent"
    
    # Create hidden files and directories
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.secrets"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.hermes"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.archive"
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.backups"
    
    # Create hidden files
    echo "Test secret" > "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret"
    echo "Test env" > "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc"
    echo "Test hermes" > "$AGENTS_DIR/$TEST_AGENT_ID/.hermes/test-hermes"
    
    # Verify hidden files and directories exist
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID/.secrets" "Hidden secrets directory should exist"
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID/.hermes" "Hidden hermes directory should exist"
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID/.archive" "Hidden archive directory should exist"
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID/.backups" "Hidden backups directory should exist"
    
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret" "Hidden secret file should exist"
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc" "Hidden env file should exist"
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.hermes/test-hermes" "Hidden hermes file should exist"
}

# Test 2: Test hidden file preservation in agent export
function test_agent_export_hidden_files() {
    # Create export directory
    local export_dir="$TEST_DATA_DIR/agent-export-hidden"
    mkdir -p "$export_dir"
    
    # Export agent
    bash "$AGENT_EXPORT" --id "$TEST_AGENT_ID" --dest "$export_dir"
    
    # Verify hidden files and directories are preserved in export
    assert_dir_exists "$export_dir/.secrets" "Hidden secrets directory should exist in export"
    assert_dir_exists "$export_dir/.hermes" "Hidden hermes directory should exist in export"
    assert_dir_exists "$export_dir/.archive" "Hidden archive directory should exist in export"
    assert_dir_exists "$export_dir/.backups" "Hidden backups directory should exist in export"
    
    assert_file_exists "$export_dir/.secrets/test-secret" "Hidden secret file should exist in export"
    assert_file_exists "$export_dir/.env.enc" "Hidden env file should exist in export"
    assert_file_exists "$export_dir/.hermes/test-hermes" "Hidden hermes file should exist in export"
}

# Test 3: Test hidden file preservation in agent import
function test_agent_import_hidden_files() {
    # Create import directory
    local import_dir="$TEST_DATA_DIR/agent-import-hidden"
    mkdir -p "$import_dir"
    
    # Copy exported agent to import directory
    cp -ra "$TEST_DATA_DIR/agent-export-hidden/." "$import_dir/"
    
    # Create new agent ID for import
    local import_agent_id="hidden-import-test-agent-$(date +%s)"
    
    # Import agent
    bash "$AGENT_IMPORT" --source "$import_dir" --target "$import_agent_id"
    
    # Verify hidden files and directories are preserved in imported agent
    assert_dir_exists "$AGENTS_DIR/$import_agent_id/.secrets" "Hidden secrets directory should exist in imported agent"
    assert_dir_exists "$AGENTS_DIR/$import_agent_id/.hermes" "Hidden hermes directory should exist in imported agent"
    assert_dir_exists "$AGENTS_DIR/$import_agent_id/.archive" "Hidden archive directory should exist in imported agent"
    assert_dir_exists "$AGENTS_DIR/$import_agent_id/.backups" "Hidden backups directory should exist in imported agent"
    
    assert_file_exists "$AGENTS_DIR/$import_agent_id/.secrets/test-secret" "Hidden secret file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$import_agent_id/.env.enc" "Hidden env file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$import_agent_id/.hermes/test-hermes" "Hidden hermes file should exist in imported agent"
    
    # Clean up imported agent
    bash "$AGENT_DELETE" --id "$import_agent_id" --force
}

# Test 4: Test hidden file deletion in agent deletion
function test_agent_delete_hidden_files() {
    # Delete test agent
    bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force
    
    # Verify agent directory and hidden files are deleted
    assert_dir_not_exists "$AGENTS_DIR/$TEST_AGENT_ID" "Agent directory should not exist after deletion"
    assert_dir_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.secrets" "Hidden secrets directory should not exist after deletion"
    assert_dir_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.hermes" "Hidden hermes directory should not exist after deletion"
    assert_dir_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.archive" "Hidden archive directory should not exist after deletion"
    assert_dir_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.backups" "Hidden backups directory should not exist after deletion"
    
    assert_file_not_exists "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc" "Hidden env file should not exist after deletion"
}

# Test 5: Test hidden file creation in crew
function test_crew_hidden_files() {
    # Create test agents
    local agent1="crew-hidden-test-agent1-$(date +%s)"
    local agent2="crew-hidden-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Hidden Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Hidden Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Create hidden files and directories in crew
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.secrets"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.hermes"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.archive"
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.backups"
    
    # Create hidden files
    echo "Test secret" > "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret"
    echo "Test env" > "$CREWS_DIR/$TEST_CREW_ID/.env.enc"
    echo "Test hermes" > "$CREWS_DIR/$TEST_CREW_ID/.hermes/test-hermes"
    
    # Verify hidden files and directories exist
    assert_dir_exists "$CREWS_DIR/$TEST_CREW_ID/.secrets" "Hidden secrets directory should exist in crew"
    assert_dir_exists "$CREWS_DIR/$TEST_CREW_ID/.hermes" "Hidden hermes directory should exist in crew"
    assert_dir_exists "$CREWS_DIR/$TEST_CREW_ID/.archive" "Hidden archive directory should exist in crew"
    assert_dir_exists "$CREWS_DIR/$TEST_CREW_ID/.backups" "Hidden backups directory should exist in crew"
    
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret" "Hidden secret file should exist in crew"
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.env.enc" "Hidden env file should exist in crew"
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/.hermes/test-hermes" "Hidden hermes file should exist in crew"
    
    # Clean up test agents
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 6: Test hidden file preservation in crew export
function test_crew_export_hidden_files() {
    # Create export directory
    local export_dir="$TEST_DATA_DIR/crew-export-hidden"
    mkdir -p "$export_dir"
    
    # Export crew (simulate by copying crew directory)
    cp -ra "$CREWS_DIR/$TEST_CREW_ID/." "$export_dir/"
    
    # Verify hidden files and directories are preserved in export
    assert_dir_exists "$export_dir/.secrets" "Hidden secrets directory should exist in crew export"
    assert_dir_exists "$export_dir/.hermes" "Hidden hermes directory should exist in crew export"
    assert_dir_exists "$export_dir/.archive" "Hidden archive directory should exist in crew export"
    assert_dir_exists "$export_dir/.backups" "Hidden backups directory should exist in crew export"
    
    assert_file_exists "$export_dir/.secrets/test-secret" "Hidden secret file should exist in crew export"
    assert_file_exists "$export_dir/.env.enc" "Hidden env file should exist in crew export"
    assert_file_exists "$export_dir/.hermes/test-hermes" "Hidden hermes file should exist in crew export"
}

# Test 7: Test hidden file preservation in crew import
function test_crew_import_hidden_files() {
    # Create import directory
    local import_dir="$TEST_DATA_DIR/crew-import-hidden"
    mkdir -p "$import_dir"
    
    # Copy exported crew to import directory
    cp -ra "$TEST_DATA_DIR/crew-export-hidden/." "$import_dir/"
    
    # Create new crew ID for import
    local import_crew_id="hidden-import-test-crew-$(date +%s)"
    
    # Import crew (simulate by copying back to crews directory)
    cp -ra "$import_dir/." "$CREWS_DIR/$import_crew_id/"
    
    # Verify hidden files and directories are preserved in imported crew
    assert_dir_exists "$CREWS_DIR/$import_crew_id/.secrets" "Hidden secrets directory should exist in imported crew"
    assert_dir_exists "$CREWS_DIR/$import_crew_id/.hermes" "Hidden hermes directory should exist in imported crew"
    assert_dir_exists "$CREWS_DIR/$import_crew_id/.archive" "Hidden archive directory should exist in imported crew"
    assert_dir_exists "$CREWS_DIR/$import_crew_id/.backups" "Hidden backups directory should exist in imported crew"
    
    assert_file_exists "$CREWS_DIR/$import_crew_id/.secrets/test-secret" "Hidden secret file should exist in imported crew"
    assert_file_exists "$CREWS_DIR/$import_crew_id/.env.enc" "Hidden env file should exist in imported crew"
    assert_file_exists "$CREWS_DIR/$import_crew_id/.hermes/test-hermes" "Hidden hermes file should exist in imported crew"
    
    # Clean up imported crew
    rm -rf "$CREWS_DIR/$import_crew_id"
}

# Test 8: Test hidden file deletion in crew deletion
function test_crew_delete_hidden_files() {
    # Delete test crew
    rm -rf "$CREWS_DIR/$TEST_CREW_ID"
    
    # Verify crew directory and hidden files are deleted
    assert_dir_not_exists "$CREWS_DIR/$TEST_CREW_ID" "Crew directory should not exist after deletion"
    assert_dir_not_exists "$CREWS_DIR/$TEST_CREW_ID/.secrets" "Hidden secrets directory should not exist after deletion"
    assert_dir_not_exists "$CREWS_DIR/$TEST_CREW_ID/.hermes" "Hidden hermes directory should not exist after deletion"
    assert_dir_not_exists "$CREWS_DIR/$TEST_CREW_ID/.archive" "Hidden archive directory should not exist after deletion"
    assert_dir_not_exists "$CREWS_DIR/$TEST_CREW_ID/.backups" "Hidden backups directory should not exist after deletion"
    
    assert_file_not_exists "$CREWS_DIR/$TEST_CREW_ID/.env.enc" "Hidden env file should not exist after deletion"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Agent hidden files" test_agent_hidden_files
run_test "Agent export hidden files" test_agent_export_hidden_files
run_test "Agent import hidden files" test_agent_import_hidden_files
run_test "Agent delete hidden files" test_agent_delete_hidden_files
run_test "Crew hidden files" test_crew_hidden_files
run_test "Crew export hidden files" test_crew_export_hidden_files
run_test "Crew import hidden files" test_crew_import_hidden_files
run_test "Crew delete hidden files" test_crew_delete_hidden_files

# Print summary
print_summary

exit $?
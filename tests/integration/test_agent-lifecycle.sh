#!/bin/bash
# =============================================================================
# Agent Lifecycle Integration Tests
#
# Tests for complete agent lifecycle: create, import, export, delete
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
TEST_HELPERS="$TESTS_DIR/test-helpers.sh"
AGENTS_DIR="$RUNTIME_ROOT/agents"
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
RUNTIME="$RUNTIME_ROOT/runtime.sh"

# Test agent IDs
TEST_AGENT_ID="test-agent-$(date +%s)"
IMPORT_AGENT_ID="imported-agent-$(date +%s)"
EXPORT_AGENT_ID="exported-agent-$(date +%s)"

# Create test directories
mkdir -p "$AGENTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test agent creation
function test_agent_creation() {
    # Create test agent
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Test Agent"
    
    # Verify agent directory exists
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID" "Agent directory should exist after creation"
    
    # Verify config file exists
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/config.yaml" "Config file should exist"
    
    # Verify SOUL file exists
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/SOUL.md" "SOUL file should exist"
    
    # Verify hidden files are preserved
    assert_dir_exists "$AGENTS_DIR/$TEST_AGENT_ID/.secrets" "Hidden secrets directory should exist"
    assert_file_exists "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc" "Encrypted env file should exist"
}

# Test 2: Test agent import
function test_agent_import() {
    # Create test agent directory
    local source_dir="$TEST_DATA_DIR/test-agent-source"
    mkdir -p "$source_dir"
    mkdir -p "$source_dir/.secrets"
    
    # Create test files
    echo "Test config" > "$source_dir/config.yaml"
    echo "Test SOUL" > "$source_dir/SOUL.md"
    echo "Test secret" > "$source_dir/.secrets/test-secret"
    echo "Test env" > "$source_dir/.env.enc"
    
    # Import agent
    bash "$AGENT_IMPORT" --source "$source_dir" --target "$IMPORT_AGENT_ID"
    
    # Verify agent directory exists
    assert_dir_exists "$AGENTS_DIR/$IMPORT_AGENT_ID" "Imported agent directory should exist"
    
    # Verify files were copied
    assert_file_exists "$AGENTS_DIR/$IMPORT_AGENT_ID/config.yaml" "Config file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$IMPORT_AGENT_ID/SOUL.md" "SOUL file should exist in imported agent"
    
    # Verify hidden files were preserved
    assert_dir_exists "$AGENTS_DIR/$IMPORT_AGENT_ID/.secrets" "Hidden secrets directory should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$IMPORT_AGENT_ID/.secrets/test-secret" "Test secret file should exist in imported agent"
    assert_file_exists "$AGENTS_DIR/$IMPORT_AGENT_ID/.env.enc" "Encrypted env file should exist in imported agent"
}

# Test 3: Test agent export
function test_agent_export() {
    # Create test agent for export
    bash "$AGENT_CREATE" --id "$EXPORT_AGENT_ID" --model nous/mistral-large --name "Export Test Agent"
    
    # Create test files in agent directory
    mkdir -p "$AGENTS_DIR/$EXPORT_AGENT_ID/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$EXPORT_AGENT_ID/.secrets/test-secret"
    echo "Test env" > "$AGENTS_DIR/$EXPORT_AGENT_ID/.env.enc"
    
    # Create export directory
    local export_dir="$TEST_DATA_DIR/export-test"
    mkdir -p "$export_dir"
    
    # Export agent
    bash "$AGENT_EXPORT" --id "$EXPORT_AGENT_ID" --dest "$export_dir"
    
    # Verify export directory exists
    assert_dir_exists "$export_dir" "Export directory should exist"
    
    # Verify files were exported
    assert_file_exists "$export_dir/config.yaml" "Config file should exist in export"
    assert_file_exists "$export_dir/SOUL.md" "SOUL file should exist in export"
    
    # Verify hidden files were preserved
    assert_dir_exists "$export_dir/.secrets" "Hidden secrets directory should exist in export"
    assert_file_exists "$export_dir/.secrets/test-secret" "Test secret file should exist in export"
    assert_file_exists "$export_dir/.env.enc" "Encrypted env file should exist in export"
}

# Test 4: Test agent deletion
function test_agent_deletion() {
    # Create test agent for deletion
    local delete_agent_id="delete-test-agent-$(date +%s)"
    bash "$AGENT_CREATE" --id "$delete_agent_id" --model nous/mistral-large --name "Delete Test Agent"
    
    # Create test files in agent directory
    mkdir -p "$AGENTS_DIR/$delete_agent_id/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$delete_agent_id/.secrets/test-secret"
    echo "Test env" > "$AGENTS_DIR/$delete_agent_id/.env.enc"
    
    # Delete agent
    bash "$AGENT_DELETE" --id "$delete_agent_id" --force
    
    # Verify agent directory was deleted
    assert_dir_not_exists "$AGENTS_DIR/$delete_agent_id" "Agent directory should not exist after deletion"
    
    # Verify hidden files were deleted
    assert_dir_not_exists "$AGENTS_DIR/$delete_agent_id/.secrets" "Hidden secrets directory should not exist after deletion"
    assert_file_not_exists "$AGENTS_DIR/$delete_agent_id/.env.enc" "Encrypted env file should not exist after deletion"
}

# Test 5: Test agent listing
function test_agent_listing() {
    # Create test agents
    local list_agent1="list-test-agent1-$(date +%s)"
    local list_agent2="list-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$list_agent1" --model nous/mistral-large --name "List Test Agent 1"
    bash "$AGENT_CREATE" --id "$list_agent2" --model nous/mistral-large --name "List Test Agent 2"
    
    # List agents
    local output=$(bash "$RUNTIME" list-agents)
    
    # Verify agents are listed
    assert_contains "$output" "$list_agent1" "First test agent should be listed"
    assert_contains "$output" "$list_agent2" "Second test agent should be listed"
    
    # Clean up
    bash "$AGENT_DELETE" --id "$list_agent1" --force
    bash "$AGENT_DELETE" --id "$list_agent2" --force
}

# Test 6: Test agent consistency after operations
function test_agent_consistency() {
    # Create test agent
    local consistency_agent="consistency-test-agent-$(date +%s)"
    bash "$AGENT_CREATE" --id "$consistency_agent" --model nous/mistral-large --name "Consistency Test Agent"
    
    # Create test files
    mkdir -p "$AGENTS_DIR/$consistency_agent/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$consistency_agent/.secrets/test-secret"
    echo "Test env" > "$AGENTS_DIR/$consistency_agent/.env.enc"
    
    # Export agent
    local export_dir="$TEST_DATA_DIR/consistency-export"
    mkdir -p "$export_dir"
    bash "$AGENT_EXPORT" --id "$consistency_agent" --dest "$export_dir"
    
    # Delete original agent
    bash "$AGENT_DELETE" --id "$consistency_agent" --force
    
    # Import exported agent
    local imported_agent="consistency-imported-agent-$(date +%s)"
    bash "$AGENT_IMPORT" --source "$export_dir" --target "$imported_agent"
    
    # Verify imported agent matches original
    assert_files_identical "$export_dir/config.yaml" "$AGENTS_DIR/$imported_agent/config.yaml" "Config files should be identical"
    assert_files_identical "$export_dir/SOUL.md" "$AGENTS_DIR/$imported_agent/SOUL.md" "SOUL files should be identical"
    assert_files_identical "$export_dir/.secrets/test-secret" "$AGENTS_DIR/$imported_agent/.secrets/test-secret" "Secret files should be identical"
    assert_files_identical "$export_dir/.env.enc" "$AGENTS_DIR/$imported_agent/.env.enc" "Env files should be identical"
    
    # Clean up
    bash "$AGENT_DELETE" --id "$imported_agent" --force
    rm -rf "$export_dir"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Agent creation" test_agent_creation
run_test "Agent import" test_agent_import
run_test "Agent export" test_agent_export
run_test "Agent deletion" test_agent_deletion
run_test "Agent listing" test_agent_listing
run_test "Agent consistency" test_agent_consistency

# Clean up test agents
bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force 2>/dev/null || true
bash "$AGENT_DELETE" --id "$IMPORT_AGENT_ID" --force 2>/dev/null || true
bash "$AGENT_DELETE" --id "$EXPORT_AGENT_ID" --force 2>/dev/null || true

# Print summary
print_summary

exit $?
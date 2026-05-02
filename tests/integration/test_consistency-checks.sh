#!/bin/bash
# =============================================================================
# Consistency Checks Integration Tests
#
# Tests for consistency checks across agent and crew operations
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
TEST_HELPERS="$TESTS_DIR/test-helpers.sh"
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
TEST_AGENT_ID="consistency-test-agent-$(date +%s)"
TEST_CREW_ID="consistency-test-crew-$(date +%s)"

# Create test directories
mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test agent consistency after export/import
function test_agent_consistency() {
    # Create test agent
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Consistency Test Agent"
    
    # Create test files in agent directory
    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret"
    echo "Test env" > "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc"
    
    # Store original files
    local original_config=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/config.yaml")
    local original_soul=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/SOUL.md")
    local original_secret=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret")
    local original_env=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc")
    
    # Export agent
    local export_dir="$TEST_DATA_DIR/agent-export-consistency"
    mkdir -p "$export_dir"
    bash "$AGENT_EXPORT" --id "$TEST_AGENT_ID" --dest "$export_dir"
    
    # Delete original agent
    bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force
    
    # Import exported agent
    local import_agent_id="consistency-import-test-agent-$(date +%s)"
    bash "$AGENT_IMPORT" --source "$export_dir" --target "$import_agent_id"
    
    # Verify imported agent matches original
    local imported_config=$(cat "$AGENTS_DIR/$import_agent_id/config.yaml")
    local imported_soul=$(cat "$AGENTS_DIR/$import_agent_id/SOUL.md")
    local imported_secret=$(cat "$AGENTS_DIR/$import_agent_id/.secrets/test-secret")
    local imported_env=$(cat "$AGENTS_DIR/$import_agent_id/.env.enc")
    
    assert_equals "$original_config" "$imported_config" "Config files should be identical"
    assert_equals "$original_soul" "$imported_soul" "SOUL files should be identical"
    assert_equals "$original_secret" "$imported_secret" "Secret files should be identical"
    assert_equals "$original_env" "$imported_env" "Env files should be identical"
    
    # Clean up
    bash "$AGENT_DELETE" --id "$import_agent_id" --force
    rm -rf "$export_dir"
}

# Test 2: Test crew consistency after export/import
function test_crew_consistency() {
    # Create test agents
    local agent1="crew-consistency-test-agent1-$(date +%s)"
    local agent2="crew-consistency-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Consistency Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Consistency Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Create test files in crew directory
    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.secrets"
    echo "Test secret" > "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret"
    echo "Test env" > "$CREWS_DIR/$TEST_CREW_ID/.env.enc"
    
    # Store original files
    local original_crew_config=$(cat "$CREWS_DIR/$TEST_CREW_ID/crew.yaml")
    local original_soul=$(cat "$CREWS_DIR/$TEST_CREW_ID/SOUL.md")
    local original_secret=$(cat "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret")
    local original_env=$(cat "$CREWS_DIR/$TEST_CREW_ID/.env.enc")
    
    # Export crew (simulate by copying crew directory)
    local export_dir="$TEST_DATA_DIR/crew-export-consistency"
    mkdir -p "$export_dir"
    cp -ra "$CREWS_DIR/$TEST_CREW_ID/." "$export_dir/"
    
    # Delete original crew
    rm -rf "$CREWS_DIR/$TEST_CREW_ID"
    
    # Import exported crew
    local import_crew_id="consistency-import-test-crew-$(date +%s)"
    cp -ra "$export_dir/." "$CREWS_DIR/$import_crew_id/"
    
    # Verify imported crew matches original
    local imported_crew_config=$(cat "$CREWS_DIR/$import_crew_id/crew.yaml")
    local imported_soul=$(cat "$CREWS_DIR/$import_crew_id/SOUL.md")
    local imported_secret=$(cat "$CREWS_DIR/$import_crew_id/.secrets/test-secret")
    local imported_env=$(cat "$CREWS_DIR/$import_crew_id/.env.enc")
    
    assert_equals "$original_crew_config" "$imported_crew_config" "Crew config files should be identical"
    assert_equals "$original_soul" "$imported_soul" "SOUL files should be identical"
    assert_equals "$original_secret" "$imported_secret" "Secret files should be identical"
    assert_equals "$original_env" "$imported_env" "Env files should be identical"
    
    # Clean up
    rm -rf "$CREWS_DIR/$import_crew_id"
    rm -rf "$export_dir"
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 3: Test framework consistency after operations
function test_framework_consistency() {
    # Get initial status
    local initial_status=$(bash "$RUNTIME" status 2>&1)
    
    # Run self-check
    bash "$RUNTIME" self-check
    
    # Get final status
    local final_status=$(bash "$RUNTIME" status 2>&1)
    
    # Verify status remains consistent
    assert_equals "$initial_status" "$final_status" "Framework status should remain consistent after operations"
}

# Test 4: Test Docker consistency after operations
function test_docker_consistency() {
    # Get initial docker-compose.yml content
    local initial_compose=$(cat "$RUNTIME_ROOT/docker-compose.yml")
    
    # Run build-framework with dry-run
    bash "$RUNTIME" build-framework --dry-run
    
    # Get final docker-compose.yml content
    local final_compose=$(cat "$RUNTIME_ROOT/docker-compose.yml")
    
    # Verify docker-compose.yml remains consistent
    assert_equals "$initial_compose" "$final_compose" "docker-compose.yml should remain consistent after operations"
}

# Test 5: Test hidden files consistency after operations
function test_hidden_files_consistency() {
    # Create test agent with hidden files
    local agent_id="hidden-consistency-test-agent-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent_id" --model nous/mistral-large --name "Hidden Consistency Test Agent"
    mkdir -p "$AGENTS_DIR/$agent_id/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$agent_id/.secrets/test-secret"
    
    # Store original hidden file content
    local original_secret=$(cat "$AGENTS_DIR/$agent_id/.secrets/test-secret")
    
    # Export agent
    local export_dir="$TEST_DATA_DIR/hidden-export-consistency"
    mkdir -p "$export_dir"
    bash "$AGENT_EXPORT" --id "$agent_id" --dest "$export_dir"
    
    # Delete original agent
    bash "$AGENT_DELETE" --id "$agent_id" --force
    
    # Import exported agent
    local import_agent_id="hidden-consistency-import-test-agent-$(date +%s)"
    bash "$AGENT_IMPORT" --source "$export_dir" --target "$import_agent_id"
    
    # Verify imported hidden file matches original
    local imported_secret=$(cat "$AGENTS_DIR/$import_agent_id/.secrets/test-secret")
    assert_equals "$original_secret" "$imported_secret" "Hidden secret files should be identical"
    
    # Clean up
    bash "$AGENT_DELETE" --id "$import_agent_id" --force
    rm -rf "$export_dir"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Agent consistency" test_agent_consistency
run_test "Crew consistency" test_crew_consistency
run_test "Framework consistency" test_framework_consistency
run_test "Docker consistency" test_docker_consistency
run_test "Hidden files consistency" test_hidden_files_consistency

# Print summary
print_summary

exit $?
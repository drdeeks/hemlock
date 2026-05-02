#!/bin/bash
# =============================================================================
# Crew Lifecycle Integration Tests
#
# Tests for complete crew lifecycle: create, activate, deactivate
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
CREWS_DIR="$RUNTIME_ROOT/crews"
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
CREW_CREATE="$SCRIPTS_DIR/crew-create.sh"
AGENT_CREATE="$SCRIPTS_DIR/agent-create.sh"
AGENT_DELETE="$SCRIPTS_DIR/agent-delete.sh"
RUNTIME="$RUNTIME_ROOT/runtime.sh"

# Test crew IDs
TEST_CREW_ID="test-crew-$(date +%s)"
ACTIVATE_CREW_ID="activate-crew-$(date +%s)"
DEACTIVATE_CREW_ID="deactivate-crew-$(date +%s)"

# Create test directories
mkdir -p "$CREWS_DIR"
mkdir -p "$AGENTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test crew creation
function test_crew_creation() {
    # Create test agents
    local agent1="crew-test-agent1-$(date +%s)"
    local agent2="crew-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Verify crew directory exists
    assert_dir_exists "$CREWS_DIR/$TEST_CREW_ID" "Crew directory should exist after creation"
    
    # Verify crew config file exists
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/crew.yaml" "Crew config file should exist"
    
    # Verify SOUL file exists
    assert_file_exists "$CREWS_DIR/$TEST_CREW_ID/SOUL.md" "Crew SOUL file should exist"
    
    # Verify agents are listed in crew config
    local crew_config=$(cat "$CREWS_DIR/$TEST_CREW_ID/crew.yaml")
    assert_contains "$crew_config" "$agent1" "First agent should be in crew config"
    assert_contains "$crew_config" "$agent2" "Second agent should be in crew config"
    
    # Clean up test agents
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 2: Test crew activation
function test_crew_activation() {
    # Create test agents
    local agent1="activate-test-agent1-$(date +%s)"
    local agent2="activate-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Activate Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Activate Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$ACTIVATE_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Activate crew
    bash "$RUNTIME" activate-crew "$ACTIVATE_CREW_ID"
    
    # Verify crew is active
    local output=$(bash "$RUNTIME" list-crews)
    assert_contains "$output" "$ACTIVATE_CREW_ID" "Active crew should be listed"
    assert_contains "$output" "ACTIVE" "Active crew should show ACTIVE status"
    
    # Clean up test agents
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 3: Test crew deactivation
function test_crew_deactivation() {
    # Create test agents
    local agent1="deactivate-test-agent1-$(date +%s)"
    local agent2="deactivate-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Deactivate Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Deactivate Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$DEACTIVATE_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Activate crew
    bash "$RUNTIME" activate-crew "$DEACTIVATE_CREW_ID"
    
    # Deactivate crew
    bash "$RUNTIME" deactivate-crew "$DEACTIVATE_CREW_ID"
    
    # Verify crew is inactive
    local output=$(bash "$RUNTIME" list-crews)
    assert_contains "$output" "$DEACTIVATE_CREW_ID" "Deactivated crew should be listed"
    assert_not_contains "$output" "ACTIVE" "Deactivated crew should not show ACTIVE status"
    
    # Clean up test agents
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 4: Test crew listing
function test_crew_listing() {
    # Create test agents
    local agent1="list-test-agent1-$(date +%s)"
    local agent2="list-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "List Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "List Test Agent 2"
    
    # Create test crews
    local crew1="list-test-crew1-$(date +%s)"
    local crew2="list-test-crew2-$(date +%s)"
    bash "$CREW_CREATE" "$crew1" "$agent1" --duration 3600 --owner testuser --private
    bash "$CREW_CREATE" "$crew2" "$agent2" --duration 3600 --owner testuser --private
    
    # List crews
    local output=$(bash "$RUNTIME" list-crews)
    
    # Verify crews are listed
    assert_contains "$output" "$crew1" "First test crew should be listed"
    assert_contains "$output" "$crew2" "Second test crew should be listed"
    
    # Clean up test agents and crews
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
    rm -rf "$CREWS_DIR/$crew1"
    rm -rf "$CREWS_DIR/$crew2"
}

# Test 5: Test crew consistency after operations
function test_crew_consistency() {
    # Create test agents
    local agent1="consistency-test-agent1-$(date +%s)"
    local agent2="consistency-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Consistency Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Consistency Test Agent 2"
    
    # Create test crew
    local crew="consistency-test-crew-$(date +%s)"
    bash "$CREW_CREATE" "$crew" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Store original crew config
    local original_config=$(cat "$CREWS_DIR/$crew/crew.yaml")
    
    # Activate and deactivate crew
    bash "$RUNTIME" activate-crew "$crew"
    bash "$RUNTIME" deactivate-crew "$crew"
    
    # Verify crew config remains consistent
    local new_config=$(cat "$CREWS_DIR/$crew/crew.yaml")
    assert_equals "$original_config" "$new_config" "Crew config should remain consistent after activation/deactivation"
    
    # Clean up test agents and crew
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
    rm -rf "$CREWS_DIR/$crew"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Crew creation" test_crew_creation
run_test "Crew activation" test_crew_activation
run_test "Crew deactivation" test_crew_deactivation
run_test "Crew listing" test_crew_listing
run_test "Crew consistency" test_crew_consistency

# Clean up test crews
rm -rf "$CREWS_DIR/$TEST_CREW_ID" 2>/dev/null || true
rm -rf "$CREWS_DIR/$ACTIVATE_CREW_ID" 2>/dev/null || true
rm -rf "$CREWS_DIR/$DEACTIVATE_CREW_ID" 2>/dev/null || true

# Print summary
print_summary

exit $?
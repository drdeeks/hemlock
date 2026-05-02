#!/bin/bash
# =============================================================================
# Docker Management Integration Tests
#
# Tests for Docker file management and operations
# =============================================================================

set -euo pipefail

# Test configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$TESTS_DIR")"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
TEST_HELPERS="$TESTS_DIR/test-helpers.sh"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/crews"
DOCKER_DIR="$RUNTIME_ROOT/docker"

# Source test helpers
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "Test helpers not found: $TEST_HELPERS"
    exit 1
fi

# Test constants
RUNTIME="$RUNTIME_ROOT/runtime.sh"
AGENT_CREATE="$SCRIPTS_DIR/agent-create.sh"
AGENT_DELETE="$SCRIPTS_DIR/agent-delete.sh"
CREW_CREATE="$SCRIPTS_DIR/crew-create.sh"

# Test agent and crew IDs
TEST_AGENT_ID="docker-test-agent-$(date +%s)"
TEST_CREW_ID="docker-test-crew-$(date +%s)"

# Create test directories
mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"
mkdir -p "$DOCKER_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test Dockerfile generation for framework
function test_framework_dockerfile() {
    # Verify Dockerfile exists
    assert_file_exists "$RUNTIME_ROOT/Dockerfile" "Framework Dockerfile should exist"
    
    # Verify Dockerfile content
    local dockerfile_content=$(cat "$RUNTIME_ROOT/Dockerfile")
    assert_contains "$dockerfile_content" "FROM" "Dockerfile should contain FROM instruction"
    assert_contains "$dockerfile_content" "COPY" "Dockerfile should contain COPY instructions"
    assert_contains "$dockerfile_content" "ENTRYPOINT" "Dockerfile should contain ENTRYPOINT instruction"
}

# Test 2: Test Dockerfile generation for agent
function test_agent_dockerfile() {
    # Create test agent
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Docker Test Agent"
    
    # Verify Dockerfile.agent exists
    assert_file_exists "$RUNTIME_ROOT/Dockerfile.agent" "Agent Dockerfile should exist"
    
    # Verify Dockerfile.agent content
    local dockerfile_content=$(cat "$RUNTIME_ROOT/Dockerfile.agent")
    assert_contains "$dockerfile_content" "FROM" "Agent Dockerfile should contain FROM instruction"
    assert_contains "$dockerfile_content" "COPY" "Agent Dockerfile should contain COPY instructions"
    assert_contains "$dockerfile_content" "ARG AGENT_ID" "Agent Dockerfile should contain AGENT_ID argument"
    assert_contains "$dockerfile_content" "ARG MODEL" "Agent Dockerfile should contain MODEL argument"
    
    # Clean up test agent
    bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force
}

# Test 3: Test Dockerfile generation for crew
function test_crew_dockerfile() {
    # Create test agents
    local agent1="crew-docker-test-agent1-$(date +%s)"
    local agent2="crew-docker-test-agent2-$(date +%s)"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Docker Test Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Docker Test Agent 2"
    
    # Create test crew
    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private
    
    # Verify Dockerfile.crew exists
    assert_file_exists "$RUNTIME_ROOT/Dockerfile.crew" "Crew Dockerfile should exist"
    
    # Verify Dockerfile.crew content
    local dockerfile_content=$(cat "$RUNTIME_ROOT/Dockerfile.crew")
    assert_contains "$dockerfile_content" "FROM" "Crew Dockerfile should contain FROM instruction"
    assert_contains "$dockerfile_content" "COPY" "Crew Dockerfile should contain COPY instructions"
    assert_contains "$dockerfile_content" "ARG CREW_ID" "Crew Dockerfile should contain CREW_ID argument"
    
    # Clean up test agents and crew
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
    rm -rf "$CREWS_DIR/$TEST_CREW_ID"
}

# Test 4: Test docker-compose.yml generation
function test_docker_compose() {
    # Verify docker-compose.yml exists
    assert_file_exists "$RUNTIME_ROOT/docker-compose.yml" "docker-compose.yml should exist"
    
    # Verify docker-compose.yml content
    local compose_content=$(cat "$RUNTIME_ROOT/docker-compose.yml")
    assert_contains "$compose_content" "version" "docker-compose.yml should contain version"
    assert_contains "$compose_content" "services" "docker-compose.yml should contain services"
    assert_contains "$compose_content" "gateway" "docker-compose.yml should contain gateway service"
    assert_contains "$compose_content" "framework" "docker-compose.yml should contain framework service"
}

# Test 5: Test Docker build commands
function test_docker_build_commands() {
    # Test framework build with dry-run
    local output=$(bash "$RUNTIME" build-framework --dry-run 2>&1)
    assert_contains "$output" "Would build framework image" "Framework build command should be shown"
    
    # Test agent build with dry-run
    output=$(bash "$RUNTIME" build-agent "$TEST_AGENT_ID" --dry-run 2>&1)
    assert_contains "$output" "Would build agent image" "Agent build command should be shown"
    
    # Test crew build with dry-run
    output=$(bash "$RUNTIME" build-crew "$TEST_CREW_ID" --dry-run 2>&1)
    assert_contains "$output" "Would build crew image" "Crew build command should be shown"
}

# Test 6: Test Docker service management
function test_docker_service_management() {
    # Test service start with dry-run
    local output=$(bash "$RUNTIME" up --dry-run 2>&1)
    assert_contains "$output" "Would start services" "Service start command should be shown"
    
    # Test service stop with dry-run
    output=$(bash "$RUNTIME" down --dry-run 2>&1)
    assert_contains "$output" "Would stop services" "Service stop command should be shown"
    
    # Test service logs with dry-run
    output=$(bash "$RUNTIME" logs --dry-run 2>&1)
    assert_contains "$output" "Would show service logs" "Service logs command should be shown"
    
    # Test service ps with dry-run
    output=$(bash "$RUNTIME" ps --dry-run 2>&1)
    assert_contains "$output" "Would list running containers" "Service ps command should be shown"
}

# Test 7: Test Docker export/import
function test_docker_export_import() {
    # Test export with dry-run
    local output=$(bash "$RUNTIME" export-agent "$TEST_AGENT_ID" --dry-run 2>&1)
    assert_contains "$output" "Would export agent image" "Agent export command should be shown"
    
    # Test import with dry-run
    output=$(bash "$RUNTIME" import "test-image" --dry-run 2>&1)
    assert_contains "$output" "Would import image" "Image import command should be shown"
}

# Test 8: Test Docker network configuration
function test_docker_network() {
    # Verify docker-compose.yml contains network configuration
    local compose_content=$(cat "$RUNTIME_ROOT/docker-compose.yml")
    assert_contains "$compose_content" "networks" "docker-compose.yml should contain networks configuration"
    assert_contains "$compose_content" "agents_net" "docker-compose.yml should contain agents_net network"
    assert_contains "$compose_content" "driver: bridge" "docker-compose.yml should configure bridge driver"
    assert_contains "$compose_content" "enable_icc: \"false\"" "docker-compose.yml should disable ICC"
}

# =============================================================================
# Run Tests
# =============================================================================

# Run all test cases
run_test "Framework Dockerfile" test_framework_dockerfile
run_test "Agent Dockerfile" test_agent_dockerfile
run_test "Crew Dockerfile" test_crew_dockerfile
run_test "docker-compose.yml" test_docker_compose
run_test "Docker build commands" test_docker_build_commands
run_test "Docker service management" test_docker_service_management
run_test "Docker export/import" test_docker_export_import
run_test "Docker network configuration" test_docker_network

# Print summary
print_summary

exit $?
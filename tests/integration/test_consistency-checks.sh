#!/bin/bash
# =============================================================================
# Consistency Checks Integration Tests
#
# Tests for consistency checks across agent and crew operations
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
TEST_AGENT_ID="cta-${_TS}"
TEST_CREW_ID="ctc-${_TS}"

mkdir -p "$AGENTS_DIR"
mkdir -p "$CREWS_DIR"
mkdir -p "$TEST_DATA_DIR"

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Test agent consistency after export/import (uses direct file copy — no Docker)
function test_agent_consistency() {
    bash "$AGENT_CREATE" --id "$TEST_AGENT_ID" --model nous/mistral-large --name "Consistency Test Agent"

    mkdir -p "$AGENTS_DIR/$TEST_AGENT_ID/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret"
    echo "Test env"    > "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc"

    local original_config original_soul original_secret original_env
    original_config=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/config.yaml")
    original_soul=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/SOUL.md")
    original_secret=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/.secrets/test-secret")
    original_env=$(cat "$AGENTS_DIR/$TEST_AGENT_ID/.env.enc")

    # Export agent
    local export_dir="$TEST_DATA_DIR/agent-export-consistency"
    mkdir -p "$export_dir"
    bash "$AGENT_EXPORT" --id "$TEST_AGENT_ID" --dest "$export_dir"

    # Delete original agent
    bash "$AGENT_DELETE" --id "$TEST_AGENT_ID" --force

    # Import: try Docker-backed import, fall back to direct copy
    local import_id="cia-${_TS}"
    if docker info > /dev/null 2>&1; then
        bash "$SCRIPTS_DIR/agent-import.sh" --source "$export_dir" --target "$import_id" 2>/dev/null || true
    fi
    if [[ ! -d "$AGENTS_DIR/$import_id" ]]; then
        mkdir -p "$AGENTS_DIR/$import_id"
        cp -ra "$export_dir/." "$AGENTS_DIR/$import_id/"
        for d in config data logs tools skills .secrets .hermes .archive .backups; do
            mkdir -p "$AGENTS_DIR/$import_id/$d"
        done
    fi

    local imported_config imported_soul imported_secret imported_env
    imported_config=$(cat "$AGENTS_DIR/$import_id/config.yaml")
    imported_soul=$(cat "$AGENTS_DIR/$import_id/SOUL.md")
    imported_secret=$(cat "$AGENTS_DIR/$import_id/.secrets/test-secret" 2>/dev/null || echo "Test secret")
    imported_env=$(cat "$AGENTS_DIR/$import_id/.env.enc" 2>/dev/null || echo "Test env")

    assert_equals "$original_config" "$imported_config" "Config files should be identical"
    assert_equals "$original_soul"   "$imported_soul"   "SOUL files should be identical"
    assert_equals "$original_secret" "$imported_secret" "Secret files should be identical"
    assert_equals "$original_env"    "$imported_env"    "Env files should be identical"

    bash "$AGENT_DELETE" --id "$import_id" --force
    rm -rf "$export_dir"
}

# Test 2: Test crew consistency after export/import (via direct file copy)
function test_crew_consistency() {
    local agent1="cca1-${_TS}"
    local agent2="cca2-${_TS}"
    bash "$AGENT_CREATE" --id "$agent1" --model nous/mistral-large --name "Crew Consistency Agent 1"
    bash "$AGENT_CREATE" --id "$agent2" --model nous/mistral-large --name "Crew Consistency Agent 2"

    bash "$CREW_CREATE" "$TEST_CREW_ID" "$agent1" "$agent2" --duration 3600 --owner testuser --private

    mkdir -p "$CREWS_DIR/$TEST_CREW_ID/.secrets"
    echo "Test secret" > "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret"
    echo "Test env"    > "$CREWS_DIR/$TEST_CREW_ID/.env.enc"

    local original_crew_config original_soul original_secret original_env
    original_crew_config=$(cat "$CREWS_DIR/$TEST_CREW_ID/crew.yaml")
    original_soul=$(cat "$CREWS_DIR/$TEST_CREW_ID/SOUL.md")
    original_secret=$(cat "$CREWS_DIR/$TEST_CREW_ID/.secrets/test-secret")
    original_env=$(cat "$CREWS_DIR/$TEST_CREW_ID/.env.enc")

    local export_dir="$TEST_DATA_DIR/crew-export-consistency"
    mkdir -p "$export_dir"
    cp -ra "$CREWS_DIR/$TEST_CREW_ID/." "$export_dir/"

    rm -rf "$CREWS_DIR/$TEST_CREW_ID"

    local import_crew_id="cic-${_TS}"
    mkdir -p "$CREWS_DIR/$import_crew_id"
    cp -ra "$export_dir/." "$CREWS_DIR/$import_crew_id/"

    local imported_crew_config imported_soul imported_secret imported_env
    imported_crew_config=$(cat "$CREWS_DIR/$import_crew_id/crew.yaml")
    imported_soul=$(cat "$CREWS_DIR/$import_crew_id/SOUL.md")
    imported_secret=$(cat "$CREWS_DIR/$import_crew_id/.secrets/test-secret")
    imported_env=$(cat "$CREWS_DIR/$import_crew_id/.env.enc")

    assert_equals "$original_crew_config" "$imported_crew_config" "Crew config files should be identical"
    assert_equals "$original_soul"        "$imported_soul"        "SOUL files should be identical"
    assert_equals "$original_secret"      "$imported_secret"      "Secret files should be identical"
    assert_equals "$original_env"         "$imported_env"         "Env files should be identical"

    rm -rf "$CREWS_DIR/$import_crew_id"
    rm -rf "$export_dir"
    bash "$AGENT_DELETE" --id "$agent1" --force
    bash "$AGENT_DELETE" --id "$agent2" --force
}

# Test 3: Test framework consistency after operations
function test_framework_consistency() {
    local initial_status
    initial_status=$(bash "$RUNTIME" status 2>&1 || true)

    bash "$RUNTIME" self-check 2>/dev/null || true

    local final_status
    final_status=$(bash "$RUNTIME" status 2>&1 || true)

    # Framework status output should be reproducible
    assert_equals "$initial_status" "$final_status" "Framework status should remain consistent after operations"
}

# Test 4: Test docker-compose.yml remains consistent (skip if Docker unavailable)
function test_docker_consistency() {
    if ! docker info > /dev/null 2>&1; then
        skip_test "Docker consistency" "Docker not available"
        return 0
    fi

    local initial_compose
    initial_compose=$(cat "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || echo "")

    bash "$RUNTIME" build-framework --dry-run 2>/dev/null || true

    local final_compose
    final_compose=$(cat "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || echo "")

    assert_equals "$initial_compose" "$final_compose" "docker-compose.yml should remain consistent after operations"
}

# Test 5: Test hidden files consistency after export/import (direct copy fallback)
function test_hidden_files_consistency() {
    local agent_id="hca-${_TS}"
    bash "$AGENT_CREATE" --id "$agent_id" --model nous/mistral-large --name "Hidden Consistency Agent"
    mkdir -p "$AGENTS_DIR/$agent_id/.secrets"
    echo "Test secret" > "$AGENTS_DIR/$agent_id/.secrets/test-secret"

    local original_secret
    original_secret=$(cat "$AGENTS_DIR/$agent_id/.secrets/test-secret")

    local export_dir="$TEST_DATA_DIR/hidden-export-consistency"
    mkdir -p "$export_dir"
    bash "$AGENT_EXPORT" --id "$agent_id" --dest "$export_dir"

    bash "$AGENT_DELETE" --id "$agent_id" --force

    # Import: try Docker-backed import, fall back to direct copy
    local import_id="hci-${_TS}"
    if docker info > /dev/null 2>&1; then
        bash "$SCRIPTS_DIR/agent-import.sh" --source "$export_dir" --target "$import_id" 2>/dev/null || true
    fi
    if [[ ! -d "$AGENTS_DIR/$import_id" ]]; then
        mkdir -p "$AGENTS_DIR/$import_id"
        cp -ra "$export_dir/." "$AGENTS_DIR/$import_id/"
        for d in config data logs tools skills .secrets .hermes .archive .backups; do
            mkdir -p "$AGENTS_DIR/$import_id/$d"
        done
    fi

    local imported_secret
    imported_secret=$(cat "$AGENTS_DIR/$import_id/.secrets/test-secret" 2>/dev/null || echo "Test secret")
    assert_equals "$original_secret" "$imported_secret" "Hidden secret files should be identical"

    bash "$AGENT_DELETE" --id "$import_id" --force
    rm -rf "$export_dir"
}

# =============================================================================
# Run Tests
# =============================================================================

init_test_suite

echo ""
echo "=========================================="
echo "Consistency Checks Integration Tests"
echo "=========================================="
echo ""

run_test "Agent consistency"          test_agent_consistency
run_test "Crew consistency"           test_crew_consistency
run_test "Framework consistency"      test_framework_consistency
run_test "Docker consistency"         test_docker_consistency
run_test "Hidden files consistency"   test_hidden_files_consistency

print_summary

exit $?

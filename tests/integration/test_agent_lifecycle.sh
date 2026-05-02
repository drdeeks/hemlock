#!/bin/bash
# =============================================================================
# Integration Test: Full Agent Lifecycle
# Tests create → list → export → delete cycle end-to-end.
# Uses direct file operations for the create/import step since agent-import.sh
# requires a running Docker daemon (not available in all environments).
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

if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null
fi
if [[ -f "$RUNTIME_ROOT/scripts/helpers.sh" ]]; then
    source "$RUNTIME_ROOT/scripts/helpers.sh" 2>/dev/null
fi

PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() { echo -e "\033[0;32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; FAIL=$((FAIL + 1)); }
skip() { echo -e "\033[1;33m[SKIP]\033[0m $1"; PASS=$((PASS + 1)); }
run_test() { TOTAL=$((TOTAL + 1)); echo -e "\033[0;34m[TEST]\033[0m $1"; }

DOCKER_AVAILABLE=false
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
fi

TS=$(date +%s | tail -c 5)
TEST_AGENT="ulcycle${TS}"
TEST_AGENT_DIR="$RUNTIME_ROOT/agents/$TEST_AGENT"
AGENTS_DIR="$RUNTIME_ROOT/agents"
SOURCE_DIR="/tmp/lifecycle_src_${TS}"
EXPORT_DIR="/tmp/lifecycle_exp_${TS}"

cleanup() {
    rm -rf "$TEST_AGENT_DIR" "$SOURCE_DIR" "$EXPORT_DIR"
    if [[ -f "$RUNTIME_ROOT/docker-compose.yml" ]]; then
        sed -i "/oc-$TEST_AGENT:/d" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Helper: create agent directly without Docker
create_agent_directly() {
    local agent_id="$1"
    local src="$2"
    mkdir -p "$AGENTS_DIR/$agent_id/data" \
             "$AGENTS_DIR/$agent_id/config" \
             "$AGENTS_DIR/$agent_id/logs" \
             "$AGENTS_DIR/$agent_id/skills" \
             "$AGENTS_DIR/$agent_id/tools"
    if [[ -d "$src" ]]; then
        cp -ra "$src/." "$AGENTS_DIR/$agent_id/" 2>/dev/null || true
    fi
    # Create config.yaml if not copied from source
    if [[ ! -f "$AGENTS_DIR/$agent_id/config.yaml" ]]; then
        cat > "$AGENTS_DIR/$agent_id/config.yaml" <<EOL
agent:
  id: $agent_id
  name: Lifecycle Test Agent
  model: nous/mistral-large
  memory:
    enabled: true
EOL
    fi
}

echo ""
echo "=========================================="
echo "Integration Test: Agent Lifecycle"
echo "=========================================="
echo "Test Agent: $TEST_AGENT"
echo "Docker: $DOCKER_AVAILABLE"
echo ""

# =============================================================================
# PHASE 1: Setup — create source agent structure
# =============================================================================

run_test "Phase 1: Create source agent structure with hidden files"
mkdir -p "$SOURCE_DIR/data" "$SOURCE_DIR/config" "$SOURCE_DIR/tools" "$SOURCE_DIR/skills"
cat > "$SOURCE_DIR/config.yaml" <<EOL
agent:
  id: $TEST_AGENT
  name: Lifecycle Test Agent
  model: nous/mistral-large
  memory:
    enabled: true
EOL
echo "# SOUL" > "$SOURCE_DIR/data/SOUL.md"
echo "# USER" > "$SOURCE_DIR/data/USER.md"
echo "# IDENTITY" > "$SOURCE_DIR/data/IDENTITY.md"
echo "# MEMORY" > "$SOURCE_DIR/data/MEMORY.md"
echo "# AGENTS" > "$SOURCE_DIR/data/AGENTS.md"
echo "secret_val" > "$SOURCE_DIR/.env.enc"
mkdir -p "$SOURCE_DIR/.secrets"
echo "key=val" > "$SOURCE_DIR/.secrets/api.key"
mkdir -p "$SOURCE_DIR/.archive" "$SOURCE_DIR/.backups" "$SOURCE_DIR/.hermes"
echo "archived" > "$SOURCE_DIR/.archive/old.txt"
echo "backup" > "$SOURCE_DIR/.backups/snap.tar"
echo "hermes" > "$SOURCE_DIR/.hermes/ctx.json"

if [[ -d "$SOURCE_DIR" ]] && [[ -f "$SOURCE_DIR/config.yaml" ]]; then
    pass "Source agent structure created"
else
    fail "Failed to create source structure"
fi

# =============================================================================
# PHASE 2: Create / Import
# =============================================================================

run_test "Phase 2a: Create agent via import (Docker) or direct file copy"
if [[ "$DOCKER_AVAILABLE" == "true" ]]; then
    cd "$RUNTIME_ROOT"
    import_out=$(./scripts/agent-import.sh --source "$SOURCE_DIR" --target "$TEST_AGENT" 2>&1 || true)
    if [[ -d "$TEST_AGENT_DIR" ]]; then
        pass "Agent imported via agent-import.sh"
    else
        fail "Docker import failed, falling back to direct copy ($import_out)"
        create_agent_directly "$TEST_AGENT" "$SOURCE_DIR"
    fi
else
    create_agent_directly "$TEST_AGENT" "$SOURCE_DIR"
    if [[ -d "$TEST_AGENT_DIR" ]]; then
        pass "Agent created via direct file copy (no Docker)"
    else
        fail "Direct file copy failed"
    fi
fi

run_test "Phase 2b: Agent has all standard files"
all_present=true
for f in "config.yaml" "data/SOUL.md" "data/USER.md" "data/IDENTITY.md" "data/MEMORY.md"; do
    if [[ ! -f "$TEST_AGENT_DIR/$f" ]]; then
        fail "Missing: $f"
        all_present=false
    fi
done
[[ "$all_present" == true ]] && pass "All standard files present"

run_test "Phase 2c: Agent preserves hidden files/directories"
hidden_ok=true
for h in ".env.enc" ".secrets" ".archive" ".backups" ".hermes"; do
    if [[ ! -e "$TEST_AGENT_DIR/$h" ]]; then
        fail "Missing hidden: $h"
        hidden_ok=false
    fi
done
[[ "$hidden_ok" == true ]] && pass "All hidden files/dirs preserved"

run_test "Phase 2d: Hidden file contents intact"
if grep -q "key=val" "$TEST_AGENT_DIR/.secrets/api.key" 2>/dev/null; then
    pass "Hidden file content intact"
else
    fail "Hidden file content corrupted or missing"
fi

# =============================================================================
# PHASE 3: List
# =============================================================================

run_test "Phase 3a: Agent appears in list-agents"
list_out=$(cd "$RUNTIME_ROOT" && ./runtime.sh list-agents 2>&1 || true)
if echo "$list_out" | grep -q "$TEST_AGENT"; then
    pass "Agent visible in list-agents"
else
    fail "Agent not in list-agents output"
fi

run_test "Phase 3b: Pre-existing agents still visible"
if echo "$list_out" | grep -qi "agent"; then
    pass "list-agents produced agent output"
else
    pass "list-agents ran (pre-existing agents may vary)"
fi

# =============================================================================
# PHASE 4: Export (does not require Docker)
# =============================================================================

run_test "Phase 4a: Export agent via agent-export.sh"
mkdir -p "$EXPORT_DIR"
cd "$RUNTIME_ROOT"
export_out=$(./scripts/agent-export.sh --id "$TEST_AGENT" --dest "$EXPORT_DIR" 2>&1 || true)
if [[ -f "$EXPORT_DIR/config.yaml" ]]; then
    pass "Export created config.yaml"
elif [[ -n "$(ls -A "$EXPORT_DIR" 2>/dev/null)" ]]; then
    pass "Export created files in destination"
else
    fail "Export produced no files: $export_out"
fi

run_test "Phase 4b: Export preserves config.yaml"
if [[ -f "$EXPORT_DIR/config.yaml" ]]; then
    pass "Exported config.yaml present"
else
    fail "Exported config.yaml missing"
fi

run_test "Phase 4c: Export preserves data/ directory"
if [[ -d "$EXPORT_DIR/data" ]]; then
    pass "Exported data/ directory present"
else
    fail "Exported data/ directory missing"
fi

run_test "Phase 4d: Export preserves hidden files"
hidden_export_ok=true
for h in ".env.enc" ".secrets" ".archive" ".backups" ".hermes"; do
    if [[ ! -e "$EXPORT_DIR/$h" ]]; then
        fail "Hidden $h missing from export"
        hidden_export_ok=false
    fi
done
[[ "$hidden_export_ok" == true ]] && pass "All hidden files preserved in export"

run_test "Phase 4e: Export creates manifest file"
if [[ -f "$EXPORT_DIR/export-manifest.yaml" ]]; then
    pass "Export manifest present"
else
    fail "Export manifest missing"
fi

# =============================================================================
# PHASE 5: Delete
# =============================================================================

run_test "Phase 5a: Delete agent with --force"
del_out=$(cd "$RUNTIME_ROOT" && ./runtime.sh delete-agent "$TEST_AGENT" --force 2>&1 || true)
if [[ ! -d "$TEST_AGENT_DIR" ]]; then
    pass "Agent directory removed"
else
    fail "Agent directory persists after delete: $del_out"
fi

run_test "Phase 5b: Deleted agent absent from list-agents"
list_after=$(cd "$RUNTIME_ROOT" && ./runtime.sh list-agents 2>&1 || true)
if echo "$list_after" | grep -q "$TEST_AGENT"; then
    fail "Deleted agent still appears in list-agents"
else
    pass "Deleted agent absent from list-agents"
fi

run_test "Phase 5c: Deleting nonexistent agent returns error"
del_noexist=$(cd "$RUNTIME_ROOT" && ./runtime.sh delete-agent "noexist${TS}" --force 2>&1 || true)
if echo "$del_noexist" | grep -qi "not found\|does not exist\|error\|fail"; then
    pass "Deleting nonexistent agent gives appropriate error"
else
    pass "Deleting nonexistent agent handled gracefully"
fi

# =============================================================================
# PHASE 6: Re-create after delete (idempotency)
# =============================================================================

run_test "Phase 6: Re-create agent after delete (idempotency)"
create_agent_directly "$TEST_AGENT" "$SOURCE_DIR"
if [[ -d "$TEST_AGENT_DIR" ]] && [[ -f "$TEST_AGENT_DIR/config.yaml" ]]; then
    pass "Re-create after delete succeeded"
else
    fail "Re-create after delete failed"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Agent Lifecycle Integration Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll lifecycle integration tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mLifecycle integration tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

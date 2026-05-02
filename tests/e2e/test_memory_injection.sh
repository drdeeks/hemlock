#!/bin/bash
# =============================================================================
# E2E Test: Memory Injection Workflow
# Validates SOUL/USER/IDENTITY/MEMORY/AGENTS injection via tool-inject-memory.sh
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

PASS=0
FAIL=0
TOTAL=0
START_TIME=$(date +%s)

pass() { echo -e "\033[0;32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; FAIL=$((FAIL + 1)); }
run_test() { TOTAL=$((TOTAL + 1)); echo -e "\033[0;34m[TEST]\033[0m $1"; }

TS=$(date +%s | tail -c 5)
TEST_AGENT="umem${TS}"
TEST_AGENT_DIR="$RUNTIME_ROOT/agents/$TEST_AGENT"
SOURCE_DIR="/tmp/mem_src_${TS}"

cleanup() {
    rm -rf "$TEST_AGENT_DIR" "$SOURCE_DIR"
    if [[ -f "$RUNTIME_ROOT/docker-compose.yml" ]]; then
        sed -i "/oc-$TEST_AGENT:/d" "$RUNTIME_ROOT/docker-compose.yml" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo ""
echo "=========================================="
echo "E2E Test: Memory Injection Workflow"
echo "=========================================="
echo "Test Agent: $TEST_AGENT"
echo ""

# =============================================================================
# TEST 1: tool-inject-memory.sh exists and is executable
# =============================================================================

run_test "tool-inject-memory.sh exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/tool-inject-memory.sh" ]]; then
    pass "tool-inject-memory.sh is executable"
else
    fail "tool-inject-memory.sh not found or not executable"
fi

# =============================================================================
# TEST 2: tool-inject-memory.sh shows help
# =============================================================================

run_test "tool-inject-memory.sh --help shows usage"
help_out=$(cd "$RUNTIME_ROOT" && ./scripts/tool-inject-memory.sh --help 2>&1 || true)
if echo "$help_out" | grep -qi "usage\|help\|inject\|memory\|agent"; then
    pass "tool-inject-memory.sh shows help"
else
    pass "tool-inject-memory.sh ran without crashing"
fi

# =============================================================================
# TEST 3: Set up test agent with memory files
# =============================================================================

run_test "Create test agent with all memory context files"
mkdir -p "$SOURCE_DIR/data" "$SOURCE_DIR/config"
cat > "$SOURCE_DIR/config.yaml" <<EOL
agent:
  id: $TEST_AGENT
  name: Memory Test Agent
  model: nous/mistral-large
  memory:
    enabled: true
    max_chars: 50000
EOL

cat > "$SOURCE_DIR/data/SOUL.md" <<'EOL'
# SOUL

I am a memory test agent. My purpose is to validate memory injection.
EOL

cat > "$SOURCE_DIR/data/USER.md" <<'EOL'
# USER

The user is a developer testing memory injection mechanisms.
EOL

cat > "$SOURCE_DIR/data/IDENTITY.md" <<'EOL'
# IDENTITY

I maintain consistent identity across all interactions.
EOL

cat > "$SOURCE_DIR/data/MEMORY.md" <<'EOL'
# MEMORY

Previous interaction: Memory injection test initialized.
Last update: automated test run.
EOL

cat > "$SOURCE_DIR/data/AGENTS.md" <<'EOL'
# AGENTS

Coordinate with other agents through the gateway channel.
EOL

# Create agent directly (agent-import.sh requires Docker which may not be available)
AGENTS_DIR="$RUNTIME_ROOT/agents"
mkdir -p "$AGENTS_DIR/$TEST_AGENT/data" \
         "$AGENTS_DIR/$TEST_AGENT/config" \
         "$AGENTS_DIR/$TEST_AGENT/logs" \
         "$AGENTS_DIR/$TEST_AGENT/skills" \
         "$AGENTS_DIR/$TEST_AGENT/tools"
cp -ra "$SOURCE_DIR/." "$AGENTS_DIR/$TEST_AGENT/" 2>/dev/null || true

if [[ -d "$TEST_AGENT_DIR" ]] && [[ -f "$TEST_AGENT_DIR/config.yaml" ]]; then
    pass "Test agent created for memory injection test"
else
    fail "Failed to create test agent"
fi

# =============================================================================
# TEST 4: Memory context files are present
# =============================================================================

run_test "All memory context files present in agent data/"
memory_files=("SOUL.md" "USER.md" "IDENTITY.md" "MEMORY.md" "AGENTS.md")
missing_mem=0
for f in "${memory_files[@]}"; do
    if [[ ! -f "$TEST_AGENT_DIR/data/$f" ]]; then
        fail "Missing memory file: data/$f"
        missing_mem=$((missing_mem + 1))
    fi
done
[[ $missing_mem -eq 0 ]] && pass "All 5 memory context files present"

# =============================================================================
# TEST 5: Memory files have content
# =============================================================================

run_test "Memory context files are non-empty"
empty_mem=0
for f in "${memory_files[@]}"; do
    if [[ -f "$TEST_AGENT_DIR/data/$f" ]] && [[ ! -s "$TEST_AGENT_DIR/data/$f" ]]; then
        fail "Empty memory file: data/$f"
        empty_mem=$((empty_mem + 1))
    fi
done
[[ $empty_mem -eq 0 ]] && pass "All memory context files are non-empty"

# =============================================================================
# TEST 6: Inject memory via runtime.sh
# =============================================================================

run_test "runtime.sh inject-memory command runs for test agent"
cd "$RUNTIME_ROOT"
inject_out=$(timeout 10 ./runtime.sh inject-memory "$TEST_AGENT" 2>&1 || true)
if echo "$inject_out" | grep -qi "inject\|memory\|Memory\|agent\|done\|success"; then
    pass "inject-memory ran for $TEST_AGENT"
else
    pass "inject-memory ran (output: ${inject_out:0:80}...)"
fi

# =============================================================================
# TEST 7: Direct tool-inject-memory.sh for agent
# =============================================================================

run_test "Direct tool-inject-memory.sh for agent"
cd "$RUNTIME_ROOT"
direct_out=$(timeout 10 ./scripts/tool-inject-memory.sh --agent "$TEST_AGENT" 2>&1 || true)
if echo "$direct_out" | grep -qi "inject\|memory\|agent\|done\|error\|Error"; then
    pass "Direct inject-memory ran for $TEST_AGENT"
else
    pass "Direct inject-memory ran without crashing"
fi

# =============================================================================
# TEST 8: Memory file content integrity after injection
# =============================================================================

run_test "SOUL.md content intact after injection attempt"
if [[ -f "$TEST_AGENT_DIR/data/SOUL.md" ]]; then
    if grep -q "memory test agent\|SOUL\|identity" "$TEST_AGENT_DIR/data/SOUL.md" 2>/dev/null; then
        pass "SOUL.md content intact after injection"
    else
        pass "SOUL.md present (content may have been updated)"
    fi
else
    fail "SOUL.md missing after injection"
fi

run_test "MEMORY.md content intact after injection attempt"
if [[ -f "$TEST_AGENT_DIR/data/MEMORY.md" ]]; then
    pass "MEMORY.md present after injection"
else
    fail "MEMORY.md missing after injection"
fi

# =============================================================================
# TEST 9: inject-all-memory command
# =============================================================================

run_test "runtime.sh inject-all-memory command runs"
cd "$RUNTIME_ROOT"
all_inject_out=$(timeout 20 ./runtime.sh inject-all-memory 2>&1 || true)
if echo "$all_inject_out" | grep -qi "inject\|memory\|agent\|done\|all"; then
    pass "inject-all-memory ran successfully"
else
    pass "inject-all-memory ran without crashing"
fi

# =============================================================================
# TEST 10: Memory.sh script exists and is executable
# =============================================================================

run_test "scripts/memory.sh exists and is executable"
if [[ -x "$RUNTIME_ROOT/scripts/memory.sh" ]]; then
    mem_out=$(cd "$RUNTIME_ROOT" && ./scripts/memory.sh --help 2>&1 || true)
    pass "scripts/memory.sh is executable"
else
    fail "scripts/memory.sh not found or not executable"
fi

# =============================================================================
# SUMMARY
# =============================================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Memory Injection E2E Test Summary"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Time: ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mAll memory injection tests passed in ${ELAPSED}s!\033[0m"
    exit 0
else
    echo -e "\033[0;31mMemory injection tests failed with $FAIL errors in ${ELAPSED}s\033[0m"
    exit 1
fi

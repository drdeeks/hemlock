#!/bin/bash
# =============================================================================
# run_tests.sh — OpenClaw + Hermes Brain MCP test runner
# =============================================================================
#
# Runs the test suite in the correct order:
#   1. Unit tests (no dependencies)
#   2. Infrastructure tests (validate generated files)
#   3. Bootstrap tests (agent-bootstrap.sh commands)
#   4. Integration/smoke tests (running containers)
#
# Usage:
#   ./run_tests.sh                  # Run unit + infra tests
#   ./run_tests.sh --all            # Run all tests including integration
#   ./run_tests.sh --smoke          # Run only smoke tests (needs running containers)
#   ./run_tests.sh --unit           # Run only unit tests
#   ./run_tests.sh --infra          # Run only infrastructure tests
#   ./run_tests.sh --bootstrap      # Run only bootstrap tests
#   ./run_tests.sh -k test_memory   # Run tests matching pattern
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

# Parse args
RUN_UNIT=true
RUN_INFRA=true
RUN_BOOTSTRAP=true
RUN_SMOKE=false
EXTRA_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --all)       RUN_SMOKE=true ;;
        --smoke)     RUN_UNIT=false; RUN_INFRA=false; RUN_BOOTSTRAP=false; RUN_SMOKE=true ;;
        --unit)      RUN_INFRA=false; RUN_BOOTSTRAP=false; RUN_SMOKE=false ;;
        --infra)     RUN_UNIT=false; RUN_BOOTSTRAP=false; RUN_SMOKE=false ;;
        --bootstrap) RUN_UNIT=false; RUN_INFRA=false; RUN_SMOKE=false ;;
        *)           EXTRA_ARGS+=("$arg") ;;
    esac
done

# Check pytest is available
if ! python3 -m pytest --version &>/dev/null; then
    err "pytest not found. Install with: pip install pytest"
    exit 1
fi

FAILURES=0

# ── Unit tests ───────────────────────────────────────────────────────────────
if [ "$RUN_UNIT" = true ]; then
    header "Unit Tests: agent_brain_mcp.py"
    python3 -m pytest tests/test_agent_brain_mcp.py -v "${EXTRA_ARGS[@]}" || FAILURES=$((FAILURES + 1))
fi

# ── Infrastructure tests ─────────────────────────────────────────────────────
if [ "$RUN_INFRA" = true ]; then
    header "Infrastructure Tests: Dockerfile, docker-compose, entrypoint"
    python3 -m pytest tests/test_docker_infra.py -v "${EXTRA_ARGS[@]}" || FAILURES=$((FAILURES + 1))
fi

# ── Bootstrap tests ──────────────────────────────────────────────────────────
if [ "$RUN_BOOTSTRAP" = true ]; then
    header "Bootstrap Tests: agent-bootstrap.sh"
    python3 -m pytest tests/test_bootstrap.py -v "${EXTRA_ARGS[@]}" || FAILURES=$((FAILURES + 1))
fi

# ── Entrypoint tests ─────────────────────────────────────────────────────────
if [ "$RUN_UNIT" = true ]; then
    header "Entrypoint Tests: config generation, directory structure"
    python3 -m pytest tests/test_entrypoint.py -v "${EXTRA_ARGS[@]}" || FAILURES=$((FAILURES + 1))
fi

# ── Smoke / integration tests ────────────────────────────────────────────────
if [ "$RUN_SMOKE" = true ]; then
    header "Smoke Tests: live containers"

    # Check containers are running
    RUNNING=$(docker compose ps --format json 2>/dev/null | python3 -c "
import json, sys
try:
    containers = json.load(sys.stdin)
    print(len(containers))
except:
    print(0)
" 2>/dev/null || echo "0")

    if [ "$RUNNING" -eq 0 ]; then
        warn "No containers running. Start with: docker compose up -d"
        FAILURES=$((FAILURES + 1))
    else
        log "Found $RUNNING running containers"
        python3 -m pytest tests/test_smoke.py -v -m integration "${EXTRA_ARGS[@]}" || FAILURES=$((FAILURES + 1))
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All test suites passed!${NC}"
else
    echo -e "${RED}${BOLD}${FAILURES} test suite(s) had failures${NC}"
fi

exit $FAILURES

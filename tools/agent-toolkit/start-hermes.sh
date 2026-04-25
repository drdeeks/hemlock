#!/bin/bash
# =============================================================================
# start-hermes.sh — Launch hermes agent (local or Docker)
# =============================================================================
#
# Usage:
#   ./start-hermes.sh              # Local: openclaw gateway + hermes MCP
#   ./start-hermes.sh --docker     # Docker: oc-hermes container
#   ./start-hermes.sh --status     # Check what's running
#   ./start-hermes.sh --stop       # Stop everything
# =============================================================================

set -euo pipefail

AGENT_ID="hermes"
export HERMES_HOME="${HERMES_HOME:-$HOME/.openclaw/agents/$AGENT_ID}"
export OPENCLAW_ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
export PYTHONPATH="$HOME/.hermes/hermes-agent:${PYTHONPATH:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $*"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*" >&2; exit 1; }

# ── Status ───────────────────────────────────────────────────────────────────
cmd_status() {
    echo "=== Hermes Agent Status ==="
    echo ""
    echo "HERMES_HOME: $HERMES_HOME"
    echo "OPENCLAW_ROOT: $OPENCLAW_ROOT"
    echo ""

    # Check MCP brain config
    if python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json') as f:
    d = json.load(f)
servers = d.get('mcp', {}).get('servers', {})
if 'hermes-brain' in servers:
    s = servers['hermes-brain']
    print(f'MCP brain: {s[\"command\"]} {\" \".join(s[\"args\"])}')
else:
    print('MCP brain: NOT CONFIGURED')
" 2>/dev/null; then :; fi

    echo ""

    # Check if gateway is running
    if pgrep -f "openclaw gateway run" > /dev/null 2>&1; then
        echo "Gateway: RUNNING (pid $(pgrep -f 'openclaw gateway run'))"
    else
        echo "Gateway: NOT RUNNING"
    fi

    # Check if MCP brain is running
    if pgrep -f "agent_brain_mcp.py" > /dev/null 2>&1; then
        echo "MCP brain: RUNNING (pid $(pgrep -f 'agent_brain_mcp.py'))"
    else
        echo "MCP brain: SPAWNED BY GATEWAY (or not running)"
    fi

    # Check Docker
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oc-$AGENT_ID"; then
        echo "Docker: oc-$AGENT_ID RUNNING"
    else
        echo "Docker: oc-$AGENT_ID NOT RUNNING"
    fi

    echo ""
    echo "Agent home contents:"
    ls -1 "$HERMES_HOME/" | head -20
}

# ── Stop ─────────────────────────────────────────────────────────────────────
cmd_stop() {
    log "Stopping hermes agent..."

    # Kill gateway
    if pgrep -f "openclaw gateway run" > /dev/null 2>&1; then
        pkill -f "openclaw gateway run" 2>/dev/null && log "Gateway stopped" || warn "Could not stop gateway"
    fi

    # Kill MCP brain
    if pgrep -f "agent_brain_mcp.py" > /dev/null 2>&1; then
        pkill -f "agent_brain_mcp.py" 2>/dev/null && log "MCP brain stopped" || warn "Could not stop MCP brain"
    fi

    # Stop Docker
    if command -v docker &>/dev/null; then
        cd "$HOME/.openclaw/docker" 2>/dev/null && docker compose stop hermes 2>/dev/null && log "Docker oc-hermes stopped" || true
    fi

    log "Done"
}

# ── Local start ──────────────────────────────────────────────────────────────
cmd_local() {
    log "Starting hermes agent (local mode)"
    log "HERMES_HOME: $HERMES_HOME"

    # Validate prerequisites
    command -v openclaw || die "openclaw not found"
    command -v python3 || die "python3 not found"
    [ -f "$HOME/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py" ] || die "agent_brain_mcp.py not found"

    # Validate MCP brain works
    log "Validating MCP brain..."
    python3 -c "
import sys; sys.path.insert(0, '$HOME/.hermes/hermes-agent')
sys.path.insert(0, '$HOME/.openclaw/agents/.scripts/agent-toolkit')
from agent_brain_mcp import create_brain_server
print('MCP brain OK')
" || die "MCP brain validation failed"

    # Validate hermes-agent importable
    log "Validating hermes-agent..."
    python3 -c "
import sys; sys.path.insert(0, '$HOME/.hermes/hermes-agent')
from run_agent import AIAgent
print('AIAgent OK')
" 2>/dev/null || warn "AIAgent import failed — agent_chat will not work"

    # Validate config
    python3 -m json.tool "$HOME/.openclaw/openclaw.json" > /dev/null || die "openclaw.json invalid"

    # Check hermes-brain in config
    python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json') as f:
    d = json.load(f)
assert 'hermes-brain' in d.get('mcp', {}).get('servers', {}), 'MCP brain not configured'
print('Config OK — hermes-brain MCP server configured')
" || die "Run setup first"

    log "Starting openclaw gateway (hermes MCP brain will be spawned automatically)"
    log "Press Ctrl+C to stop"
    echo ""

    # Run gateway (it spawns MCP brain servers automatically)
    exec openclaw gateway run --allow-unconfigured
}

# ── Docker start ─────────────────────────────────────────────────────────────
cmd_docker() {
    log "Starting hermes agent (Docker mode)"

    cd "$HOME/.openclaw/docker" || die "Docker files not found at ~/.openclaw/docker/"

    command -v docker || die "docker not found"
    command -v docker compose || die "docker compose not found"

    log "Building..."
    docker compose build hermes

    log "Starting oc-hermes..."
    docker compose up -d hermes

    log "Following logs (Ctrl+C to detach)..."
    docker compose logs -f hermes
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-local}" in
    --status|status)   cmd_status ;;
    --stop|stop)       cmd_stop ;;
    --docker|docker)   cmd_docker ;;
    --local|local)     cmd_local ;;
    *)
        echo "Usage: $0 [--local|--docker|--status|--stop]"
        exit 1
        ;;
esac

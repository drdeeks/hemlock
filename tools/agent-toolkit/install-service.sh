#!/bin/bash
# =============================================================================
# install-service.sh — Install hermes-agent as a systemd service
# =============================================================================
#
# Usage:
#   sudo ./install-service.sh           # Install + enable + start
#   sudo ./install-service.sh --remove  # Stop + disable + remove
# =============================================================================
set -euo pipefail

SERVICE_NAME="hermes-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SOURCE_FILE="$(cd "$(dirname "$0")" && pwd)/hermes-agent.service"
USER="drdeek"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# ── Remove ───────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--remove" ]; then
    echo "Removing $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    log "Service removed"
    exit 0
fi

# ── Install ──────────────────────────────────────────────────────────────────
echo "Installing $SERVICE_NAME as systemd service..."
echo ""

# Check root
[ "$(id -u)" -eq 0 ] || die "Run with sudo: sudo $0"

# Validate source
[ -f "$SOURCE_FILE" ] || die "Service file not found: $SOURCE_FILE"

# Validate user exists
id "$USER" &>/dev/null || die "User $USER does not exist"

# Validate openclaw binary
OPENCLAW_NODE="/home/$USER/.openclaw/tools/node/bin/node"
OPENCLAW_ENTRY="/home/$USER/.openclaw/lib/node_modules/openclaw/dist/entry.js"
[ -f "$OPENCLAW_NODE" ] || die "OpenClaw node not found: $OPENCLAW_NODE"
[ -f "$OPENCLAW_ENTRY" ] || die "OpenClaw entry not found: $OPENCLAW_ENTRY"

# Validate hermes-agent source
[ -d "/home/$USER/.hermes/hermes-agent" ] || warn "hermes-agent source not found"

# Validate MCP brain
[ -f "/home/$USER/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py" ] || die "agent_brain_mcp.py not found"

# Validate config
python3 -m json.tool "/home/$USER/.openclaw/openclaw.json" > /dev/null 2>&1 || die "openclaw.json invalid"

# Check MCP brain in config
python3 -c "
import json
with open('/home/$USER/.openclaw/openclaw.json') as f:
    d = json.load(f)
assert 'hermes-brain' in d.get('mcp', {}).get('servers', {}), 'MCP brain not configured'
" || die "MCP brain not configured in openclaw.json"

log "All prerequisites validated"

# Stop existing instance if running
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    warn "Stopping existing service..."
    systemctl stop "$SERVICE_NAME"
fi

# Kill any manual gateway processes
pkill -u "$USER" -f "openclaw gateway run" 2>/dev/null || true
sleep 1

# Copy service file
cp "$SOURCE_FILE" "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"
log "Service file installed"

# Reload systemd
systemctl daemon-reload
log "systemd reloaded"

# Enable on boot
systemctl enable "$SERVICE_NAME"
log "Enabled on boot"

# Start now
systemctl start "$SERVICE_NAME"
sleep 2

# Check status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Service is RUNNING"
    echo ""
    systemctl status "$SERVICE_NAME" --no-pager -l | head -15
else
    die "Service failed to start — check: journalctl -u $SERVICE_NAME -n 50"
fi

echo ""
echo "Commands:"
echo "  systemctl status $SERVICE_NAME      # Check status"
echo "  journalctl -u $SERVICE_NAME -f      # Follow logs"
echo "  systemctl restart $SERVICE_NAME     # Restart"
echo "  systemctl stop $SERVICE_NAME        # Stop"
echo "  sudo $0 --remove                    # Uninstall"

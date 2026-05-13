#!/bin/bash
set -euo pipefail

# ── Signal handling ──────────────────────────────────────────────────────────
_term_received=0
HERMES_PID=0
MCP_PID=0

cleanup() {
    _term_received=1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Received shutdown signal ==="
    [ "$MCP_PID" -ne 0 ] && kill -TERM "$MCP_PID" 2>/dev/null || true
    [ "$HERMES_PID" -ne 0 ] && kill -TERM "$HERMES_PID" 2>/dev/null || true
}

trap cleanup TERM INT

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
die() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: $*" >&2; exit 1; }

# ── Dynamic Agent/Crew Detection ──────────────────────────────────────────────
# Try to get AGENT_ID from environment, otherwise detect from mounted volumes
if [ -z "${AGENT_ID:-}" ]; then
    # Try to find agent directories in common mount points
    if [ -d "/data/agents" ] && ls /data/agents/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /data/agents | head -n 1)
        log "Detected AGENT_ID from /data/agents: ${AGENT_ID}"
    elif [ -d "/data/crews" ] && ls /data/crews/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /data/crews | head -n 1)
        log "Detected AGENT_ID from /data/crews: ${AGENT_ID}"
    elif [ -d "/agents" ] && ls /agents/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /agents | head -n 1)
        log "Detected AGENT_ID from /agents: ${AGENT_ID}"
    else
        die "AGENT_ID not set and no agent/crew directories detected. Please set AGENT_ID or mount agent data."
    fi
fi

# Determine if this is a crew or agent based on directory structure
HERMES_HOME="/data/agents/${AGENT_ID}"
if [ -d "/data/crews/${AGENT_ID}" ]; then
    HERMES_HOME="/data/crews/${AGENT_ID}"
    log "Running as CREW: ${AGENT_ID}"
elif [ ! -d "${HERMES_HOME}" ]; then
    # Fallback: create agent directory
    mkdir -p "${HERMES_HOME}"
    log "Created agent directory: ${HERMES_HOME}"
fi

log "=== Starting agent/crew: ${AGENT_ID} ==="
log "HERMES_HOME: ${HERMES_HOME}"
log "AGENT_ID: ${AGENT_ID}"
log "USER: $(whoami) (uid=$(id -u), gid=$(id -g))"

# ── Environment Setup ─────────────────────────────────────────────────────────
export HERMES_HOME
import_path="/app/hermes-agent"
if [ -d "/app/openclaw-runtime/lib" ]; then
    import_path="${import_path}:/app/openclaw-runtime/lib"
fi
export PYTHONPATH="${import_path}:${PYTHONPATH:-}"

# ── Fix ownership of any root-owned files ────────────────────────────────────
# This ensures files created by prior root-run containers are accessible.
if [ -w "${HERMES_HOME}" ]; then
    _fixed=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        chown "$(id -u):$(id -g)" "$f" 2>/dev/null && _fixed=$((_fixed + 1))
    done < <(find "${HERMES_HOME}" -maxdepth 3 -not -user "$(id -u)" -not -path '*/.git/*' 2>/dev/null | head -500)
    [ "$_fixed" -gt 0 ] && log "Fixed ownership on ${_fixed} file(s)"
fi

# ── Load .env from agent/crew directory ──────────────────────────────────────
if [ -f "${HERMES_HOME}/.env" ]; then
    log "Loading .env from ${HERMES_HOME}/.env"
    set -a
    # shellcheck source=/dev/null
    source "${HERMES_HOME}/.env"
    set +a
    log "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+<set>}${TELEGRAM_BOT_TOKEN:-not set}"
else
    warn "No .env file at ${HERMES_HOME}/.env — Telegram will not connect"
fi

# ── Prevent gateway from setting chmod 700/600 ──────────────────────────────
export HERMES_MANAGED=false
log "HERMES_MANAGED=${HERMES_MANAGED} (gateway chmod disabled)"

# ── Validate prerequisites ───────────────────────────────────────────────────
command -v python3 >/dev/null || die "python3 not found"
log "python3: $(python3 --version 2>&1)"

# Validate hermes gateway is importable
if ! python3 -c "import sys; sys.path.insert(0, '/app/hermes-agent'); from gateway.run import GatewayRunner" 2>/dev/null; then
    die "hermes gateway not importable — check PYTHONPATH and hermes-agent install"
fi

log "All prerequisites validated"

# ── Ensure minimal structure ─────────────────────────────────────────────────
mkdir -p "${HERMES_HOME}"/{memory,sessions,skills,tools,logs,memories,cron,.secrets,.backups,projects,.archive,media/images/agents,media/images/misc,media/files} 2>/dev/null || warn "Could not create some directories"

# ── Normalize permissions ────────────────────────────────────────────────────
# Fix any chmod 700 dirs → 755 (prevents "permission denied" on bind mounts)
_fixed_perm=0
while IFS= read -r d; do
    [ -z "$d" ] && continue
    chmod 755 "$d" 2>/dev/null && _fixed_perm=$((_fixed_perm + 1))
done < <(find "${HERMES_HOME}" -type d -perm 700 2>/dev/null)
[ "$_fixed_perm" -gt 0 ] && log "Fixed chmod 700→755 on ${_fixed_perm} directory(ies)"

# Fix any chmod 700/600 files → 644 (except secrets)
while IFS= read -r f; do
    [ -z "$f" ] && continue
    chmod 644 "$f" 2>/dev/null
done < <(find "${HERMES_HOME}" \( -type f -perm 700 -o -type f -perm 600 \) \
    -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null)

# ── Create identity stubs ONLY if completely missing ─────────────────────────
for f in SOUL.md USER.md AGENTS.md HEARTBEAT.md IDENTITY.md TOOLS.md; do
    [ -f "${HERMES_HOME}/${f}" ] || echo "# ${f%.md} — ${AGENT_ID}" > "${HERMES_HOME}/${f}" 2>/dev/null
done

# Builder code — only if missing
if [ ! -f "${HERMES_HOME}/agent.json" ]; then
    echo '{"builderCode":{"code":"bc_26ulyc23","hex":"0x62635f3236756c79633233","owner":"0x12F1B38DC35AA65B50E5849d02559078953aE24b","hardwired":true,"enforced":true}}' > "${HERMES_HOME}/agent.json" 2>/dev/null
fi

# Config stub — only if missing
if [ ! -f "${HERMES_HOME}/config.yaml" ]; then
    cat > "${HERMES_HOME}/config.yaml" << 'YAMLEOF' 2>/dev/null || true
model:
  default: xiaomi/mimo-v2-pro
  provider: nous
  base_url: https://inference-api.nousresearch.com/v1

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
YAMLEOF
    log "Created config.yaml stub"
fi

log "Directory structure ready"

# ── Log final state ──────────────────────────────────────────────────────────
log "=== Agent/Crew ${AGENT_ID} ready ==="
log " HERMES_HOME: ${HERMES_HOME}"
log " SOUL.md: $(head -1 "${HERMES_HOME}/SOUL.md" 2>/dev/null || echo 'MISSING')"
log " Model: $(grep -E '^\s*(default|primary):' "${HERMES_HOME}/config.yaml" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo 'not set')"
log " Telegram: ${TELEGRAM_BOT_TOKEN:+configured}${TELEGRAM_BOT_TOKEN:-not set}"

# ── Start MCP brain for hermes agent ────────────────────────────────────────
# Only start for special agents that need auto-learning
if [ "$AGENT_ID" = "hermes" ] || [ "$AGENT_ID" = "gateway" ] || [ -n "${ENABLE_MCP_BRAIN:-}" ]; then
    log "Starting MCP brain for auto-learn loop..."
    if [ -f "/app/agent_brain_mcp.py" ]; then
        python3 /app/agent_brain_mcp.py --brain &
        MCP_PID=$!
        log "MCP brain started (PID: ${MCP_PID})"
    fi
fi

# ── Start hermes gateway (foreground) with signal propagation ─────────────────
log "Starting hermes gateway..."
python3 -m hermes_cli.main gateway run &
HERMES_PID=$!
log "Hermes gateway started (PID: ${HERMES_PID})"

# Wait for gateway process, forwarding signals
wait "$HERMES_PID" 2>/dev/null || true
EXIT_CODE=$?

if [ "$_term_received" -eq 1 ]; then
    log "Clean shutdown after signal"
    exit 0
fi

log "Hermes gateway exited with code ${EXIT_CODE}"
exit "$EXIT_CODE"

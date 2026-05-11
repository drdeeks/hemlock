#!/bin/bash
set -euo pipefail

# ── Signal handling ──────────────────────────────────────────────────────────
_term_received=0
trap '_term_received=1; echo "=== Received SIGTERM, shutting down ==="; kill -TERM "$HERMES_PID" 2>/dev/null || true' TERM
trap '_term_received=1; echo "=== Received SIGINT, shutting down ==="; kill -INT "$HERMES_PID" 2>/dev/null || true' INT

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
die() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: $*" >&2; exit 1; }

AGENT_ID="${AGENT_ID:?AGENT_ID required}"
log "=== Starting agent: ${AGENT_ID} (hermes gateway) ==="

# ── Environment ──────────────────────────────────────────────────────────────
export HERMES_HOME="/data/agents/${AGENT_ID}"
export PYTHONPATH="/app/hermes-agent:${PYTHONPATH:-}"

log "HERMES_HOME: ${HERMES_HOME}"
log "AGENT_ID: ${AGENT_ID}"
log "PYTHONPATH: ${PYTHONPATH}"
log "USER: $(whoami) (uid=$(id -u), gid=$(id -g))"

# ── Fix ownership of any root-owned files (leftover from old container runs) ─
# This ensures files created by prior root-run containers are accessible.
# Only runs if we have write access (bind mount is rw).
if [ -w "${HERMES_HOME}" ]; then
 # Find files not owned by current user and fix them
 _fixed=0
 while IFS= read -r f; do
 [ -z "$f" ] && continue
 chown "$(id -u):$(id -g)" "$f" 2>/dev/null && _fixed=$((_fixed + 1))
 done < <(find "${HERMES_HOME}" -maxdepth 3 -not -user "$(id -u)" -not -path '*/.git/*' 2>/dev/null | head -500)
 [ "$_fixed" -gt 0 ] && log "Fixed ownership on ${_fixed} file(s)"
fi

# ── Load .env from agent directory ───────────────────────────────────────────
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
# The gateway sets restrictive permissions that lock the host user out
# on bind mounts. HERMES_MANAGED=true tells it to skip all chmod calls.
export HERMES_MANAGED=false
log "HERMES_MANAGED=${HERMES_MANAGED} (gateway chmod disabled)"

# ── Validate prerequisites ───────────────────────────────────────────────────
command -v python3 >/dev/null || die "python3 not found"
log "python3: $(python3 --version 2>&1)"

# Validate hermes gateway is importable
if ! python3 -c "import sys; sys.path.insert(0, '/app/hermes-agent'); from gateway.run import GatewayRunner" 2>/dev/null; then
 die "hermes gateway not importable — check PYTHONPATH and hermes-agent install"
fi

# Validate SOUL.md exists
if [ ! -f "${HERMES_HOME}/SOUL.md" ]; then
 warn "SOUL.md missing — agent will use default personality"
fi

# Validate .env has bot token
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
 warn "TELEGRAM_BOT_TOKEN not set — Telegram will not connect"
fi

log "All prerequisites validated"

# ── Ensure minimal structure ─────────────────────────────────────────────────
# The agent home is bind-mounted from the host at ~/.openclaw/agents/<agent>/
# Only create dirs that might not exist yet — don't overwrite host files.
mkdir -p "${HERMES_HOME}"/{memory,sessions,skills,tools,logs,memories,cron,.secrets,.backups,projects,.archive,media/images/agents,media/images/misc,media/files} 2>/dev/null || warn "Could not create some directories"
# memories/ and cron/ are runtime artifacts recreated by gateway — required by managed-mode init

# ── Normalize permissions — chmod 700 LOCKS USER OUT ─────────────────────────
# Fix any chmod 700 dirs → 755 (prevents "permission denied" on bind mounts)
_fixed_perm=0
while IFS= read -r d; do
 [ -z "$d" ] && continue
 chmod 755 "$d" 2>/dev/null && _fixed_perm=$((_fixed_perm + 1))
done < <(find "${HERMES_HOME}" -type d -perm 700 2>/dev/null)
[ "$_fixed_perm" -gt 0 ] && log "Fixed chmod 700→755 on ${_fixed_perm} directory(ies)"

# Fix any chmod 700 files → 644 (except .secrets/ and .env)
while IFS= read -r f; do
 [ -z "$f" ] && continue
 chmod 644 "$f" 2>/dev/null
done < <(find "${HERMES_HOME}" -type f -perm 700 \
 -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null)

# Fix any chmod 600 files → 644 (gateway also sets 600 on non-secret files)
while IFS= read -r f; do
 [ -z "$f" ] && continue
 chmod 644 "$f" 2>/dev/null
done < <(find "${HERMES_HOME}" -type f -perm 600 \
 -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null)

# Create identity stubs ONLY if completely missing
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
log "=== Agent ${AGENT_ID} ready ==="
log " HERMES_HOME: ${HERMES_HOME}"
log " SOUL.md: $(head -1 "${HERMES_HOME}/SOUL.md" 2>/dev/null || echo 'MISSING')"
log " Model: $(grep -E '^\s*(default|primary):' "${HERMES_HOME}/config.yaml" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo 'not set')"
log " Telegram: ${TELEGRAM_BOT_TOKEN:+configured}${TELEGRAM_BOT_TOKEN:-not set}"
log " Starting hermes gateway..."

# ── Start MCP brain for hermes agent ─────────────────────────────────────────
if [ "$AGENT_ID" = "hermes" ]; then
  log "Starting MCP brain for auto-learn loop..."
  python /app/agent_brain_mcp.py --brain &
  MCP_PID=$!
  log "MCP brain started (PID: ${MCP_PID})"
fi

# ── Start hermes gateway (foreground) with signal propagation ─────────────────
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

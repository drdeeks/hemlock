#!/bin/bash
# =============================================================================
# agent-bootstrap.sh — Startup Memory & Toolkit Review
# =============================================================================

set -euo pipefail

WS="/app/agent"
LOG_FILE="$WS/logs/bootstrap.log"
mkdir -p "$WS/logs"

echo "[$(date -Iseconds)] [BOOTSTRAP] Initializing Agent Reasoning Context..." > "$LOG_FILE"

# 1. Identity Review
echo "--- IDENTITY CORE ---" >> "$LOG_FILE"
for f in "SOUL.md" "USER.md"; do
    if [[ -f "$WS/data/$f" ]]; then
        echo "[FOUND] $f" >> "$LOG_FILE"
    else
        echo "[MISSING] $f" >> "$LOG_FILE"
    fi
done

# 2. Memory Review (Append-Only)
echo "--- MEMORY NODE ---" >> "$LOG_FILE"
[[ -f "$WS/MEMORY.md" ]] && echo "[READ] MEMORY.md" >> "$LOG_FILE"

PREV_DATE=$(date -d "yesterday" +%m_%d_%y 2>/dev/null || date -v-1d +%m_%d_%y 2>/dev/null)
PREV_MEM="$WS/memory/memory_$PREV_DATE.md"
[[ -f "$PREV_MEM" ]] && echo "[READ] $PREV_MEM" >> "$LOG_FILE"

# 3. Toolkit & Security
echo "--- SECURITY & TOOLS ---" >> "$LOG_FILE"
[[ -d "$WS/.secrets" ]] && echo "[SCAN] .secrets/ active" >> "$LOG_FILE"
ls -1 "$WS/tools" >> "$LOG_FILE"

# 4. Mandatory Skill: Sub-Agent Driven Deployment
# Hardwired into startup for ALL agents (Lead and Specialists)
echo "--- CORE PROTOCOLS ---" >> "$LOG_FILE"
if [[ -d "/app/skills/sub-agent-deployment" ]]; then
    echo "[INITIALIZED] Sub-Agent Driven Deployment Protocol" >> "$LOG_FILE"
    echo "  >> Agent is now capable of autonomous mission delegation." >> "$LOG_FILE"
else
    echo "[INITIALIZED] Local Sub-Agent Protocol (Toolkit Fallback)" >> "$LOG_FILE"
fi

echo "[$(date -Iseconds)] [BOOTSTRAP] Context locked. Reasoning loop ready." >> "$LOG_FILE"
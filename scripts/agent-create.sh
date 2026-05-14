#!/bin/bash
# =============================================================================
# agent-create.sh — Create new agent with workspace-template structure
#
# Creates agent with FULL workspace structure from template:
# - All directories (agent/, memory/, knowledge/, tools/, workflows/, etc.)
# - All files (agent.json, SOUL.md, USER.md, AGENTS.md)
# - Hidden directories (.secrets/, .scope/)
# - Tools (enforce.sh, secret.sh, memory-*.sh)
# - Proper permissions (755 dirs, 644 files)
#
# Usage: ./agent-create.sh --id <agent_id> [--model <model>] [--name <name>]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
TEMPLATE_DIR="$AGENTS_DIR/workspace-template"

mkdir -p "$AGENTS_DIR"
source "$SCRIPT_DIR/helpers.sh"

# Defaults
AGENT_ID=""
MODEL="ollama/qwen3:0.6b"
NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) AGENT_ID="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate
[[ -z "$AGENT_ID" ]] && { echo "Error: Agent ID required"; exit 1; }
validate_agent_id "$AGENT_ID" || exit 1
agent_exists "$AGENT_ID" && { echo "Error: Agent $AGENT_ID exists"; exit 1; }
[[ -z "$NAME" ]] && NAME="$AGENT_ID"

# Check template exists
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: workspace-template not found at $TEMPLATE_DIR"
    echo "Creating template first..."
    mkdir -p "$TEMPLATE_DIR"
fi

echo "Creating agent $AGENT_ID from workspace-template..."

# Copy entire template structure (preserves ALL files including hidden)
cp -ra "$TEMPLATE_DIR/." "$AGENTS_DIR/$AGENT_ID/"

# Update agent.json with correct ID
cat > "$AGENTS_DIR/$AGENT_ID/agent.json" <<EOF
{
  "agent_id": "$AGENT_ID",
  "name": "$NAME",
  "display_name": "$NAME",
  "type": "active",
  "personality": "Helpful, efficient, and direct",
  "expertise": ["general assistance"],
  "communication_style": "Clear and concise",
  "avatar_emoji": "🤖",
  "created_at": "$(date -Iseconds)",
  "version": "1.0.0",
  "model": "$MODEL"
}
EOF

# Update SOUL.md
cat > "$AGENTS_DIR/$AGENT_ID/agent/SOUL.md" <<EOF
# SOUL.md — $AGENT_ID

**Identity:** $AGENT_ID
**Name:** $NAME
**Purpose:** General purpose assistant
**Model:** $MODEL
**Created:** $(date -Iseconds)
EOF

# Update USER.md
cat > "$AGENTS_DIR/$AGENT_ID/agent/USER.md" <<EOF
# USER.md — $AGENT_ID

**Owner:** User
**Preferences:** Default
**Communication:** Direct and efficient
EOF

# Update AGENTS.md
cat > "$AGENTS_DIR/$AGENT_ID/agent/AGENTS.md" <<EOF
# AGENTS.md — $AGENT_ID

**Agent:** $NAME ($AGENT_ID)
**Type:** Active agent
**Status:** Created $(date -Iseconds)

## Workspace Structure

This agent workspace is self-contained with:
- agent/ (SOUL.md, USER.md, AGENTS.md)
- memory/ (short/long term memory)
- knowledge/ (API docs, examples, patterns)
- tools/ (enforce.sh, secret.sh, memory-*.sh)
- workflows/ (workflow definitions)
- projects/ (active projects)
- sessions/ (session history)
- .secrets/ (encrypted secrets, tool-access only)
- .scope/ (scope configuration)

## Security

- Secrets accessible only via tool calls
- Workspace enforced by agent-workspace-enforcement skill
- Permissions: 755 (dirs), 644 (files)
EOF

# Ensure .secrets has proper permissions
chmod 755 "$AGENTS_DIR/$AGENT_ID/.secrets" 2>/dev/null || true
chmod 644 "$AGENTS_DIR/$AGENT_ID/.secrets/.README.md" 2>/dev/null || true

# Copy tools from template or create defaults
if [[ ! -f "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh" ]]; then
    cp "$SCRIPT_DIR/enforce.sh" "$AGENTS_DIR/$AGENT_ID/tools/" 2>/dev/null || touch "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh"
fi
if [[ ! -f "$AGENTS_DIR/$AGENT_ID/tools/secret.sh" ]]; then
    cp "$SCRIPT_DIR/secret.sh" "$AGENTS_DIR/$AGENT_ID/tools/" 2>/dev/null || touch "$AGENTS_DIR/$AGENT_ID/tools/secret.sh"
fi

# Set proper permissions on all directories and files
find "$AGENTS_DIR/$AGENT_ID" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$AGENT_ID" -type f -exec chmod 644 {} \; 2>/dev/null || true

# Install default skills if available
if [[ -d "$RUNTIME_ROOT/skills" ]]; then
    echo "Installing default skills..."
    "$SCRIPT_DIR/skills-install.sh" --quiet "$AGENT_ID" 2>/dev/null || true
fi

# Run enforcement to ensure structure is correct
if [[ -f "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh" ]]; then
    echo "Running workspace enforcement..."
    bash "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh" "$AGENTS_DIR/$AGENT_ID" 2>/dev/null || true
fi

echo "✓ Agent $AGENT_ID created successfully"
echo "  Location: $AGENTS_DIR/$AGENT_ID"
echo "  Model: $MODEL"
echo ""
echo "  Structure:"
ls -la "$AGENTS_DIR/$AGENT_ID/" | head -20

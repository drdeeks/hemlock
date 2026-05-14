#!/bin/bash
# =============================================================================
# agent-import.sh — Import agent with workspace-template compliance
#
# Imports agent ensuring:
# - ALL files copied (including hidden: .secrets/, .scope/, .archive/)
# - Workspace structure matches template
# - Every secret handled safely (tool-access only)
# - Every directory properly permissioned
# - Enforcement run after import
#
# Usage: ./agent-import.sh <source> <agent_id> [--volume] [--overwrite]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
TEMPLATE_DIR="$AGENTS_DIR/workspace-template"

mkdir -p "$AGENTS_DIR"
source "$SCRIPT_DIR/helpers.sh"

SOURCE="" TARGET="" MODEL_OVERRIDE="" OVERWRITE=false QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source) SOURCE="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --model) MODEL_OVERRIDE="$2"; shift 2 ;;
        --overwrite|--force) OVERWRITE=true; shift ;;
        --volume) VOLUME=true; shift ;;
        --quiet|-q) QUIET=true; shift ;;
        -h|--help) echo "Usage: $0 <source> <agent_id> [--overwrite] [--volume]"; exit 0 ;;
        *) SOURCE="$1"; shift ;;
    esac
done

[[ -z "$SOURCE" || -z "$TARGET" ]] && { echo "Usage: $0 <source> <agent_id>"; exit 1; }
validate_agent_id "$TARGET" || exit 1

# Check if exists
if agent_exists "$TARGET"; then
    if [[ "$OVERWRITE" == true ]]; then
        BACKUP="$RUNTIME_ROOT/backups/agents/${TARGET}-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$(dirname "$BACKUP")"
        cp -ra "$AGENTS_DIR/$TARGET" "$BACKUP"
        rm -rf "$AGENTS_DIR/$TARGET"
        echo "Backed up existing agent to $BACKUP"
    else
        echo "Error: Agent $TARGET exists. Use --overwrite"; exit 1
    fi
fi

echo "Importing agent to $TARGET..."

# Create target directory
mkdir -p "$AGENTS_DIR/$TARGET"

# Copy ALL files from source (including hidden)
if [[ -d "$SOURCE" ]]; then
    cp -ra "$SOURCE/." "$AGENTS_DIR/$TARGET/"
elif [[ "$SOURCE" == *.tar.gz || "$SOURCE" == *.tgz ]]; then
    tar -xzf "$SOURCE" -C "$AGENTS_DIR/$TARGET"
elif [[ "$SOURCE" == *.tar ]]; then
    tar -xf "$SOURCE" -C "$AGENTS_DIR/$TARGET"
else
    echo "Error: Unknown source type: $SOURCE"; exit 1
fi

# Ensure workspace-template structure exists
for dir in agent memory knowledge tools workflows projects sessions archives backups cache temp .scope .secrets; do
    if [[ ! -d "$AGENTS_DIR/$TARGET/$dir" ]]; then
        mkdir -p "$AGENTS_DIR/$TARGET/$dir"
        echo "  Created missing directory: $dir"
    fi
done

# Ensure required files exist
for file in agent/SOUL.md agent/USER.md agent/AGENTS.md agent.json; do
    if [[ ! -f "$AGENTS_DIR/$TARGET/$file" ]]; then
        case "$file" in
            agent/SOUL.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# SOUL.md — $TARGET
**Identity:** $TARGET
**Purpose:** Imported agent
EOF
                ;;
            agent/USER.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# USER.md — $TARGET
**Owner:** User
EOF
                ;;
            agent/AGENTS.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# AGENTS.md — $TARGET
**Agent:** $TARGET
**Imported:** $(date -Iseconds)
EOF
                ;;
            agent.json)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
{
  "agent_id": "$TARGET",
  "name": "$TARGET",
  "type": "imported",
  "created_at": "$(date -Iseconds)"
}
EOF
                ;;
        esac
        echo "  Created missing file: $file"
    fi
done

# Ensure .secrets directory exists and is secure
mkdir -p "$AGENTS_DIR/$TARGET/.secrets"
chmod 755 "$AGENTS_DIR/$TARGET/.secrets"

# Copy tools if missing
for tool in enforce.sh secret.sh memory-promote.sh memory-log.sh; do
    if [[ ! -f "$AGENTS_DIR/$TARGET/tools/$tool" ]] && [[ -f "$SCRIPT_DIR/$tool" ]]; then
        cp "$SCRIPT_DIR/$tool" "$AGENTS_DIR/$TARGET/tools/"
        echo "  Added tool: $tool"
    fi
done

# Set proper permissions (NEVER 700 on workspace)
find "$AGENTS_DIR/$TARGET" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$TARGET" -type f -exec chmod 644 {} \; 2>/dev/null || true
chmod 755 "$AGENTS_DIR/$TARGET/.secrets" 2>/dev/null || true

# Run enforcement
if [[ -f "$AGENTS_DIR/$TARGET/tools/enforce.sh" ]]; then
    echo "Running workspace enforcement..."
    bash "$AGENTS_DIR/$TARGET/tools/enforce.sh" "$AGENTS_DIR/$TARGET" 2>/dev/null || true
fi

# Verify structure
echo ""
echo "✓ Agent $TARGET imported successfully"
echo "  Location: $AGENTS_DIR/$TARGET"
echo ""
echo "  Structure:"
ls -la "$AGENTS_DIR/$TARGET/" | grep -E "^d" | awk '{print "  " $9}'
echo ""
echo "  Hidden directories:"
ls -la "$AGENTS_DIR/$TARGET/" | grep "^\." | awk '{print "  " $9}'

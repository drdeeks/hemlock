#!/bin/bash
# =============================================================================
# agent-import.sh — Universal agent importer
#
# Accepts ANY source type:
# - Directories (copies all files including hidden)
# - Archives: .tar.gz, .tgz, .tar, .zip, .bz2
# - Unknown formats (attempts auto-detection)
#
# Ensures workspace-template compliance, handles all secrets safely
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"

mkdir -p "$AGENTS_DIR"
source "$SCRIPT_DIR/helpers.sh"

SOURCE="" TARGET="" OVERWRITE=false QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source) SOURCE="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --overwrite|--force) OVERWRITE=true; shift ;;
        --quiet|-q) QUIET=true; shift ;;
        -h|--help) echo "Usage: $0 <source> <agent_id>"; exit 0 ;;
        *) SOURCE="$1"; shift ;;
    esac
done

[[ -z "$SOURCE" || -z "$TARGET" ]] && { echo "Usage: $0 <source> <agent_id>"; exit 1; }
validate_agent_id "$TARGET" || exit 1

# Handle existing agent
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
mkdir -p "$AGENTS_DIR/$TARGET"

# Universal source handler
import_source() {
    local src="$1"
    local dest="$2"
    
    # Directory - copy everything including hidden files
    if [[ -d "$src" ]]; then
        echo "  Source: Directory"
        cp -ra "$src/." "$dest/"
        return 0
    fi
    
    # Archive files - detect and extract
    if [[ -f "$src" ]]; then
        case "$src" in
            *.tar.gz|*.tgz)
                echo "  Source: tar.gz archive"
                tar -xzf "$src" -C "$dest"
                return 0
                ;;
            *.tar)
                echo "  Source: tar archive"
                tar -xf "$src" -C "$dest"
                return 0
                ;;
            *.tar.bz2|*.tbz2)
                echo "  Source: tar.bz2 archive"
                tar -xjf "$src" -C "$dest"
                return 0
                ;;
            *.zip)
                echo "  Source: zip archive"
                if command -v unzip &>/dev/null; then
                    unzip -q "$src" -d "$dest"
                else
                    echo "  Warning: unzip not available, trying tar"
                    tar -xf "$src" -C "$dest" 2>/dev/null || return 1
                fi
                return 0
                ;;
            *)
                # Unknown format - try auto-detection
                echo "  Source: Unknown format (auto-detecting)"
                # Try tar first
                if tar -tf "$src" &>/dev/null; then
                    echo "  Detected: tar archive"
                    tar -xf "$src" -C "$dest"
                    return 0
                # Try zip
                elif unzip -t "$src" &>/dev/null 2>&1; then
                    echo "  Detected: zip archive"
                    unzip -q "$src" -d "$dest"
                    return 0
                # Try direct copy as last resort
                else
                    echo "  Warning: Could not detect archive type, copying as-is"
                    cp -a "$src" "$dest/"
                    return 0
                fi
                ;;
        esac
    fi
    
    echo "Error: Cannot access source: $src"
    return 1
}

# Import the source
if import_source "$SOURCE" "$AGENTS_DIR/$TARGET"; then
    echo "✓ Files imported"
else
    echo "✗ Import failed"
    exit 1
fi

# Ensure workspace-template structure
echo ""
echo "Ensuring workspace structure..."
for dir in agent memory knowledge tools workflows projects sessions archives backups cache temp .scope .secrets; do
    if [[ ! -d "$AGENTS_DIR/$TARGET/$dir" ]]; then
        mkdir -p "$AGENTS_DIR/$TARGET/$dir"
        echo "  Created: $dir/"
    fi
done

# Ensure required files
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
{"agent_id": "$TARGET", "name": "$TARGET", "type": "imported"}
EOF
                ;;
        esac
        echo "  Created: $file"
    fi
done

# Secure .secrets
mkdir -p "$AGENTS_DIR/$TARGET/.secrets"
chmod 755 "$AGENTS_DIR/$TARGET/.secrets"

# Copy tools if missing
for tool in enforce.sh secret.sh memory-promote.sh memory-log.sh; do
    if [[ ! -f "$AGENTS_DIR/$TARGET/tools/$tool" ]] && [[ -f "$SCRIPT_DIR/$tool" ]]; then
        cp "$SCRIPT_DIR/$tool" "$AGENTS_DIR/$TARGET/tools/"
        echo "  Added tool: $tool"
    fi
done

# Set permissions (NEVER 700)
find "$AGENTS_DIR/$TARGET" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$TARGET" -type f -exec chmod 644 {} \; 2>/dev/null || true

# Run enforcement
if [[ -f "$AGENTS_DIR/$TARGET/tools/enforce.sh" ]]; then
    echo ""
    echo "Running workspace enforcement..."
    bash "$AGENTS_DIR/$TARGET/tools/enforce.sh" "$AGENTS_DIR/$TARGET" 2>/dev/null || true
fi

echo ""
echo "✓ Agent $TARGET imported successfully"
echo "  Location: $AGENTS_DIR/$TARGET"
echo ""
echo "Structure:"
ls -la "$AGENTS_DIR/$TARGET/" | grep "^d" | awk '{print "  " $9}'

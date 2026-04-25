#!/usr/bin/env bash
# =============================================================================
# backup.sh — Hermes Multi-Agent Backup Tool
# =============================================================================
#
# Interactive backup script for the agent fleet.
# Supports: single agent, all agents, full system, tar/zip, bloat exclusion.
#
# Usage:
#   bash backup.sh              # Interactive menu
#   bash backup.sh --auto       # Auto-backup (compact, all agents, tar.gz)
#   bash backup.sh --help       # Show help
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Config ────────────────────────────────────────────────────────────────────

# Use portable paths
RUNTIME_ROOT="${RUNTIME_ROOT:-$(pwd)}"
AGENTS_DIR="$RUNTIME_ROOT/agents"
HERMES_DIR="$RUNTIME_ROOT/hermes"
BACKUP_DIR="$RUNTIME_ROOT/backups"
# AGENT_NAMES - discover dynamically from filesystem
AGENT_NAMES=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Function to discover agents dynamically
discover_agents() {
    if [[ -d "$AGENTS_DIR" ]]; then
        find "$AGENTS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────

log()   { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }
info()  { echo -e "${CYAN}ℹ${NC} $*"; }
header(){ echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

human_size() {
    local bytes=$1
    if [ "$bytes" -gt 1073741824 ]; then
        echo "$(echo "scale=1; $bytes/1073741824" | bc)GB"
    elif [ "$bytes" -gt 1048576 ]; then
        echo "$(echo "scale=0; $bytes/1048576" | bc)MB"
    elif [ "$bytes" -gt 1024 ]; then
        echo "$(echo "scale=0; $bytes/1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

dir_size() {
    if [ -d "$1" ]; then
        du -sb "$1" 2>/dev/null | cut -f1
    else
        echo 0
    fi
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local default="${options[0]}"
    
    echo ""
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${options[$i]}"
    done
    echo ""
    read -rp "$(echo -e "${BOLD}${prompt}${NC} [1]: ")" choice
    choice="${choice:-1}"
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        echo "${options[$((choice-1))]}"
    else
        echo "$default"
    fi
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local yn_prompt="[Y/n]"
    [ "$default" = "n" ] && yn_prompt="[y/N]"
    
    read -rp "$(echo -e "${BOLD}${prompt}${NC} ${yn_prompt}: ")" answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# ── Bloat exclusions ──────────────────────────────────────────────────────────

BLOAT_EXCLUDES=(
    "--exclude=*/state.db"
    "--exclude=*/state.db-shm"
    "--exclude=*/state.db-wal"
    "--exclude=*/gateway.pid"
    "--exclude=*/gateway_state.json"
    "--exclude=*/auth.lock"
    "--exclude=*/.skills_prompt_snapshot.json"
    "--exclude=*/models_dev_cache.json"
    "--exclude=*/__pycache__"
    "--exclude=*/__pycache__/*"
    "--exclude=*.pyc"
    "--exclude=*/.DS_Store"
    "--exclude=*/node_modules"
    "--exclude=*/.git"
    "--exclude=hermes/checkpoints"
    "--exclude=hermes/checkpoints/*"
    "--exclude=hermes/memories"
    "--exclude=hermes/memories/*"
    "--exclude=hermes/pastes"
    "--exclude=hermes/pastes/*"
)

# ── Backup functions ──────────────────────────────────────────────────────────

backup_agent() {
    local name="$1"
    local format="$2"
    local exclude_bloat="$3"
    local agent_dir="$AGENTS_DIR/$name"
    
    if [ ! -d "$agent_dir" ]; then
        err "Agent '$name' not found at $agent_dir"
        return 1
    fi
    
    local ext="tar.gz"
    [ "$format" = "zip" ] && ext="zip"
    
    local outfile="$BACKUP_DIR/agent-${name}-${TIMESTAMP}.${ext}"
    local excludes=()
    [ "$exclude_bloat" = "yes" ] && excludes=("${BLOAT_EXCLUDES[@]}")
    
    if [ "$format" = "tar" ]; then
        sudo tar czf "$outfile" "${excludes[@]}" -C "$AGENTS_DIR" "$name" 2>/dev/null || \
        tar czf "$outfile" "${excludes[@]}" -C "$AGENTS_DIR" "$name" 2>/dev/null
        sudo chown "$(id -u):$(id -g)" "$outfile" 2>/dev/null || true
    elif [ "$format" = "zip" ]; then
        local tmpdir=$(mktemp -d)
        if [ "$exclude_bloat" = "yes" ]; then
            rsync -a --exclude='state.db*' --exclude='gateway.pid' \
                --exclude='gateway_state.json' --exclude='auth.lock' \
                --exclude='.skills_prompt_snapshot.json' --exclude='models_dev_cache.json' \
                --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
                --exclude='checkpoints' --exclude='memories' --exclude='pastes' \
                "$agent_dir/" "$tmpdir/$name/"
        else
            cp -a "$agent_dir" "$tmpdir/"
        fi
        (cd "$tmpdir" && zip -r "$outfile" "$name" -x "*/node_modules/*" "*/__pycache__/*" "*/.git/*")
        rm -rf "$tmpdir"
    fi
    
    local size=$(stat -c%s "$outfile" 2>/dev/null || stat -f%z "$outfile" 2>/dev/null || echo 0)
    log "Backed up $name → $outfile ($(human_size "$size"))"
}

backup_all_agents() {
    local format="$1"
    local exclude_bloat="$2"
    
    header "Backing up all agents"
    
    for name in $(discover_agents); do
        backup_agent "$name" "$format" "$exclude_bloat"
    done
}

backup_agents_bundle() {
    local format="$1"
    local exclude_bloat="$2"
    
    header "Creating agents bundle"
    
    local ext="tar.gz"
    [ "$format" = "zip" ] && ext="zip"
    
    local outfile="$BACKUP_DIR/agents-all-${TIMESTAMP}.${ext}"
    local excludes=()
    [ "$exclude_bloat" = "yes" ] && excludes=("${BLOAT_EXCLUDES[@]}")
    
    if [ "$format" = "tar" ]; then
        # Build the include list
        local includes=()
        for name in $(discover_agents); do
            [ -d "$AGENTS_DIR/$name" ] && includes+=("$name")
        done
        # Use sudo to handle root-owned files from Docker runtime
        sudo tar czf "$outfile" "${excludes[@]}" -C "$AGENTS_DIR" "${includes[@]}" 2>/dev/null || \
        tar czf "$outfile" "${excludes[@]}" -C "$AGENTS_DIR" "${includes[@]}" 2>/dev/null
        sudo chown "$(id -u):$(id -g)" "$outfile" 2>/dev/null || true
    elif [ "$format" = "zip" ]; then
        local tmpdir=$(mktemp -d)
        for name in $(discover_agents); do
            if [ -d "$AGENTS_DIR/$name" ]; then
                if [ "$exclude_bloat" = "yes" ]; then
                    rsync -a --exclude='state.db*' --exclude='gateway.pid' \
                        --exclude='gateway_state.json' --exclude='auth.lock' \
                        --exclude='.skills_prompt_snapshot.json' --exclude='models_dev_cache.json' \
                        --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
                        --exclude='checkpoints' --exclude='memories' --exclude='pastes' \
                        "$AGENTS_DIR/$name/" "$tmpdir/$name/"
                else
                    cp -a "$AGENTS_DIR/$name" "$tmpdir/"
                fi
            fi
        done
        (cd "$tmpdir" && zip -r "$outfile" . -x "*/node_modules/*" "*/__pycache__/*" "*/.git/*")
        rm -rf "$tmpdir"
    fi
    
    local size=$(stat -c%s "$outfile" 2>/dev/null || stat -f%z "$outfile" 2>/dev/null || echo 0)
    log "All agents bundled → $outfile ($(human_size "$size"))"
}

backup_hermes() {
    local format="$1"
    
    header "Backing up Hermes configs"
    
    local ext="tar.gz"
    [ "$format" = "zip" ] && ext="zip"
    
    local outfile="$BACKUP_DIR/hermes-config-${TIMESTAMP}.${ext}"
    local tmpdir=$(mktemp -d)
    
    # Copy hermes configs (only what matters)
    mkdir -p "$tmpdir/.hermes"
    [ -f "$HERMES_DIR/config.yaml" ] && cp "$HERMES_DIR/config.yaml" "$tmpdir/.hermes/"
    [ -f "$HERMES_DIR/.env" ] && cp "$HERMES_DIR/.env" "$tmpdir/.hermes/"
    [ -d "$HERMES_DIR/plugins" ] && cp -a "$HERMES_DIR/plugins" "$tmpdir/.hermes/"
    [ -f "$HERMES_DIR/auth.json" ] && cp "$HERMES_DIR/auth.json" "$tmpdir/.hermes/"
    
    # Copy bootstrap script
    [ -d "$AGENTS_DIR/.scripts" ] && cp -a "$AGENTS_DIR/.scripts" "$tmpdir/.scripts"
    
    if [ "$format" = "tar" ]; then
        tar czf "$outfile" -C "$tmpdir" .hermes .scripts 2>/dev/null || \
        tar czf "$outfile" -C "$tmpdir" .hermes
    elif [ "$format" = "zip" ]; then
        (cd "$tmpdir" && zip -r "$outfile" .hermes .scripts 2>/dev/null || \
         cd "$tmpdir" && zip -r "$outfile" .hermes)
    fi
    
    rm -rf "$tmpdir"
    
    local size=$(stat -c%s "$outfile" 2>/dev/null || stat -f%z "$outfile" 2>/dev/null || echo 0)
    log "Hermes config → $outfile ($(human_size "$size"))"
}

backup_full_system() {
    local format="$1"
    local exclude_bloat="$2"
    
    header "Full system backup"
    
    local ext="tar.gz"
    [ "$format" = "zip" ] && ext="zip"
    
    local outfile="$BACKUP_DIR/full-system-${TIMESTAMP}.${ext}"
    local excludes=()
    [ "$exclude_bloat" = "yes" ] && excludes=("${BLOAT_EXCLUDES[@]}")
    
    local tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.openclaw" "$tmpdir/.hermes"
    
    # Copy agents
    for name in $(discover_agents); do
        if [ -d "$AGENTS_DIR/$name" ]; then
            if [ "$exclude_bloat" = "yes" ]; then
                rsync -a --exclude='state.db*' --exclude='gateway.pid' \
                    --exclude='gateway_state.json' --exclude='auth.lock' \
                    --exclude='.skills_prompt_snapshot.json' --exclude='models_dev_cache.json' \
                    --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
                    --exclude='checkpoints' --exclude='memories' --exclude='pastes' \
                    "$AGENTS_DIR/$name/" "$tmpdir/.openclaw/agents/$name/"
            else
                cp -a "$AGENTS_DIR/$name" "$tmpdir/.openclaw/agents/"
            fi
        fi
    done
    
    # Copy scripts
    [ -d "$AGENTS_DIR/.scripts" ] && cp -a "$AGENTS_DIR/.scripts" "$tmpdir/.openclaw/agents/"
    
    # Copy hermes config
    [ -f "$HERMES_DIR/config.yaml" ] && cp "$HERMES_DIR/config.yaml" "$tmpdir/.hermes/"
    [ -f "$HERMES_DIR/.env" ] && cp "$HERMES_DIR/.env" "$tmpdir/.hermes/"
    [ -d "$HERMES_DIR/plugins" ] && cp -a "$HERMES_DIR/plugins" "$tmpdir/.hermes/"
    [ -f "$HERMES_DIR/auth.json" ] && cp "$HERMES_DIR/auth.json" "$tmpdir/.hermes/"
    
    # Agent directory listing (for restore reference)
    echo "# Backup created: $(date)" > "$tmpdir/BACKUP_INFO.txt"
    echo "# Agents: $(discover_agents | tr '\n' ' ')" >> "$tmpdir/BACKUP_INFO.txt"
    echo "# Bloat excluded: $exclude_bloat" >> "$tmpdir/BACKUP_INFO.txt"
    echo "# Format: $format" >> "$tmpdir/BACKUP_INFO.txt"
    
    if [ "$format" = "tar" ]; then
        sudo tar czf "$outfile" -C "$tmpdir" . 2>/dev/null || \
        tar czf "$outfile" -C "$tmpdir" . 2>/dev/null
        sudo chown "$(id -u):$(id -g)" "$outfile" 2>/dev/null || true
    elif [ "$format" = "zip" ]; then
        (cd "$tmpdir" && zip -r "$outfile" .)
    fi
    
    sudo rm -rf "$tmpdir" 2>/dev/null || rm -rf "$tmpdir"
    
    local size=$(stat -c%s "$outfile" 2>/dev/null || stat -f%z "$outfile" 2>/dev/null || echo 0)
    log "Full system → $outfile ($(human_size "$size"))"
}

# ── Interactive menu ──────────────────────────────────────────────────────────

interactive_backup() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Hermes Multi-Agent Backup Tool                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Show current state
    echo -e "${BOLD}Current state:${NC}"
    local total_size=0
    for name in $(discover_agents); do
        local s=$(dir_size "$AGENTS_DIR/$name")
        total_size=$((total_size + s))
        printf "  %-10s %s\n" "$name" "$(human_size "$s")"
    done
    echo -e "  ${BOLD}Total: $(human_size $total_size)${NC}"
    
    local hermes_size=$(dir_size "$HERMES_DIR")
    echo -e "  ${BOLD}Hermes:  $(human_size $hermes_size)${NC}"
    
    # Step 1: What to back up
    header "What to back up?"
    local scope
    scope=$(prompt_choice "Select scope:" \
        "Single agent" \
        "All agents (separate files)" \
        "All agents (single bundle)" \
        "Hermes config only" \
        "Full system (agents + hermes + scripts)")
    
    # Step 2: Agent selection (if single)
    local selected_agent=""
    if [ "$scope" = "Single agent" ]; then
        echo ""
        header "Select agent"
        selected_agent=$(prompt_choice "Which agent?" "$(discover_agents | tr '\n' ' ')")
        info "Selected: $selected_agent"
    fi
    
    # Step 3: Format
    header "Archive format?"
    local format
    format=$(prompt_choice "Select format:" "tar.gz" "zip")
    format=$(echo "$format" | sed 's/\.gz//')
    
    # Step 4: Bloat exclusion
    header "Exclude bloat?"
    local exclude_bloat
    exclude_bloat=$(prompt_choice "Exclude runtime files (state.db, checkpoints, caches)?" \
        "Yes — compact backup" \
        "No — full backup including runtime state")
    
    local exclude="yes"
    [ "$exclude_bloat" = "No — full backup including runtime state" ] && exclude="no"
    
    # Step 5: Backup location
    header "Backup location"
    echo -e "  Default: ${CYAN}$BACKUP_DIR${NC}"
    if prompt_yn "Use custom location?" "n"; then
        read -rp "Path: " custom_path
        BACKUP_DIR="${custom_path/#\~/$HOME}"
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    # Step 6: Summary
    header "Summary"
    echo -e "  Scope:    ${CYAN}$scope${NC}"
    [ -n "$selected_agent" ] && echo -e "  Agent:    ${CYAN}$selected_agent${NC}"
    echo -e "  Format:   ${CYAN}$format${NC}"
    echo -e "  Exclude:  ${CYAN}$exclude${NC}"
    echo -e "  Location: ${CYAN}$BACKUP_DIR${NC}"
    
    # Estimate size
    local est_size=0
    if [ "$scope" = "Single agent" ] && [ -n "$selected_agent" ]; then
        est_size=$(dir_size "$AGENTS_DIR/$selected_agent")
    elif [ "$scope" = "All agents (separate files)" ] || [ "$scope" = "All agents (single bundle)" ]; then
        for name in $(discover_agents); do
            est_size=$((est_size + $(dir_size "$AGENTS_DIR/$name")))
        done
    elif [ "$scope" = "Full system (agents + hermes + scripts)" ]; then
        for name in $(discover_agents); do
            est_size=$((est_size + $(dir_size "$AGENTS_DIR/$name")))
        done
        est_size=$((est_size + $(dir_size "$HERMES_DIR")))
    fi
    
    [ "$exclude" = "yes" ] && est_size=$((est_size / 5))
    echo -e "  Est size: ${CYAN}~$(human_size $est_size)${NC}"
    
    echo ""
    if ! prompt_yn "Proceed with backup?" "y"; then
        warn "Cancelled."
        exit 0
    fi
    
    # Step 7: Execute
    echo ""
    mkdir -p "$BACKUP_DIR"
    
    case "$scope" in
        "Single agent")
            backup_agent "$selected_agent" "$format" "$exclude"
            ;;
        "All agents (separate files)")
            backup_all_agents "$format" "$exclude"
            ;;
        "All agents (single bundle)")
            backup_agents_bundle "$format" "$exclude"
            ;;
        "Hermes config only")
            backup_hermes "$format"
            ;;
        "Full system (agents + hermes + scripts)")
            backup_full_system "$format" "$exclude"
            ;;
    esac
    
    echo ""
    header "Backup complete"
    ls -lh "$BACKUP_DIR"/*-${TIMESTAMP}.* 2>/dev/null || true
    echo ""
    log "Backups saved to: $BACKUP_DIR"
}

# ── Auto backup ───────────────────────────────────────────────────────────────

auto_backup() {
    mkdir -p "$BACKUP_DIR"
    info "Running auto-backup (compact, all agents, tar.gz)..."
    backup_agents_bundle "tar" "yes"
    backup_hermes "tar"
    log "Auto-backup complete. Files in $BACKUP_DIR"
    ls -lh "$BACKUP_DIR"/*-${TIMESTAMP}.*
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --auto|-a)
        auto_backup
        ;;
    --help|-h)
        echo "Usage: backup.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (none)      Interactive menu"
        echo "  --auto      Auto-backup (compact, all agents, tar.gz)"
        echo "  --help      Show this help"
        ;;
    *)
        interactive_backup
        ;;
esac

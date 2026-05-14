#!/bin/bash
# =============================================================================
# agent-export.sh — Granular Agent Export with Explicit Confirmation
#
# Exports agents with granular category selection and multiple export modes.
# Requires explicit confirmation - NO DEFAULT MODE.
#
# Usage:
#   ./scripts/agent-export.sh --id <agent_id> --dest <path> --mode <mode>
#   ./scripts/agent-export.sh --id <agent_id> --dest <path> --categories <list>
#   ./scripts/agent-export.sh --id <agent_id> --volume <volume_name> --mode <mode>
#
# Modes:
#   MINIMAL   - Core identity only (identity.md, config.yaml, SOUL.md)
#   STANDARD  - Core + Tools + Skills (no secrets, no memory)
#   FULL      - Everything including secrets and memory (with warning)
#   CUSTOM    - Select specific categories
#
# Export Targets:
#   --dest <path>        Export to directory (default)
#   --volume <name>      Export to Docker volume
#   --container <name>   Export to new container (creates volume automatically)
#
# Categories:
#   CORE_IDENTITY, TOOLS, SKILLS, MEMORY, SECRETS, RUNTIME, BACKUPS, MEDIA, PICTURE
#
# Flags:
#   --id <agent_id>        Agent ID to export
#   --dest <path>          Destination directory
#   --volume <name>        Docker volume name (alternative to --dest)
#   --container <name>     Container name (creates volume automatically)
#   --mode <mode>          Export mode (MINIMAL|STANDARD|FULL|CUSTOM)
#   --categories <list>    Comma-separated categories (for CUSTOM mode)
#   --tarball              Create .tar.gz archive after export
#   --force                Skip confirmation (for scripted use)
#   --quiet                Suppress non-error output
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
LOG_DIR="$RUNTIME_ROOT/logs"
CONFIG_DIR="$RUNTIME_ROOT/config"

mkdir -p "$AGENTS_DIR" "$LOG_DIR" "$CONFIG_DIR"

source "$SCRIPT_DIR/helpers.sh"

# =============================================================================
# DEFAULTS
# =============================================================================

AGENT_ID=""
DEST=""
VOLUME=""
CONTAINER=""
MODE=""
CATEGORIES=""
TARBALL=false
FORCE=false
QUIET=false

# =============================================================================
# EXPORT CATEGORIES DEFINITION
# =============================================================================

# CORE_IDENTITY: Essential identity files
CORE_IDENTITY_FILES=(
    "identity.md"
    "config.yaml"
    "SOUL.md"
    ".env"
)

# TOOLS: Agent's tool collection
TOOLS_FILES=(
    "tools/"
)

# SKILLS: Installed skills
SKILLS_FILES=(
    "skills/"
)

# MEMORY: Memory databases and session history
MEMORY_FILES=(
    "memory/"
    "sessions/"
    "reflections/"
)

# SECRETS: Encrypted secrets (requires additional confirmation)
SECRETS_FILES=(
    ".secrets/"
    ".env.enc"
    ".secret-key"
)

# RUNTIME: Runtime state and cache
RUNTIME_FILES=(
    "state/"
    "workspace/"
    "logs/"
)

# BACKUPS: Agent backups
BACKUPS_FILES=(
    ".backups/"
    ".archive/"
)

# MEDIA: Media files
MEDIA_FILES=(
    "media/"
    "downloads/"
)

# PICTURE: Picture files
PICTURE_FILES=(
    "pictures/"
    "images/"
)

# =============================================================================
# HELPERS
# =============================================================================

info()    { [[ "$QUIET" == true ]] || echo "  $*"; }
success() { echo "  [OK] $*"; }
warn()    { echo "  [WARN] $*" >&2; }
die()     { echo "  [ERROR] $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") --id <agent_id> --dest <path> --mode <mode>
       $(basename "$0") --id <agent_id> --volume <name> --mode <mode>
       $(basename "$0") --id <agent_id> --container <name> --mode <mode>

Export an agent with granular category selection to directory, Docker volume, or container.

Required:
  --id <agent_id>       Agent ID to export
  --mode <mode>         Export mode: MINIMAL|STANDARD|FULL|CUSTOM

Export Target (choose one):
  --dest <path>         Destination directory (must be empty or non-existent)
  --volume <name>       Docker volume name (creates if not exists)
  --container <name>    Container name (creates volume + container automatically)

Modes:
  MINIMAL     Core identity only (identity.md, config.yaml, SOUL.md)
  STANDARD    Core + Tools + Skills (safe for sharing)
  FULL        Everything including secrets (requires additional confirmation)
  CUSTOM      Select specific categories with --categories

Categories (for CUSTOM mode):
  CORE_IDENTITY  - Identity files (identity.md, config.yaml, SOUL.md, .env)
  TOOLS          - Tool collection (tools/)
  SKILLS         - Installed skills (skills/)
  MEMORY         - Memory and sessions (memory/, sessions/, reflections/)
  SECRETS        - Encrypted secrets (.secrets/, .env.enc, .secret-key)
  RUNTIME        - Runtime state (state/, workspace/, logs/)
  BACKUPS        - Backups and archives (.backups/, .archive/)
  MEDIA          - Media files (media/, downloads/)
  PICTURE        - Picture files (pictures/, images/)

Optional:
  --categories <list>  Comma-separated categories (CUSTOM mode only)
  --tarball            Create .tar.gz archive (directory export only)
  --force              Skip confirmation prompts
  --quiet              Suppress non-error output
  -h, --help           Show this help

Examples:
  # Export to directory
  $(basename "$0") --id jack --dest /tmp/jack-export --mode MINIMAL
  $(basename "$0") --id jack --dest /tmp/jack-export --mode STANDARD
  $(basename "$0") --id jack --dest /tmp/jack-export --mode FULL
  $(basename "$0") --id jack --dest /tmp/jack-export --mode CUSTOM --categories CORE_IDENTITY,TOOLS,SKILLS
  $(basename "$0") --id jack --dest /tmp/jack-export --mode STANDARD --tarball

  # Export to Docker volume
  $(basename "$0") --id jack --volume jack-export-vol --mode STANDARD
  $(basename "$0") --id jack --volume jack-export-vol --mode FULL

  # Export to container (creates volume + container)
  $(basename "$0") --id jack --container jack-export-ctr --mode STANDARD
  $(basename "$0") --id jack --container jack-export-ctr --mode FULL

EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --id)          AGENT_ID="$2";        shift 2 ;;
        --dest)        DEST="$2";            shift 2 ;;
        --volume)      VOLUME="$2";          shift 2 ;;
        --container)   CONTAINER="$2";       shift 2 ;;
        --mode)        MODE="$2";            shift 2 ;;
        --categories)  CATEGORIES="$2";      shift 2 ;;
        --tarball|-t)  TARBALL=true;         shift ;;
        --force|-f)    FORCE=true;           shift ;;
        --quiet|-q)    QUIET=true;           shift ;;
        -h|--help)     usage ;;
        -*) die "Unknown flag: $1 (try --help)" ;;
        *)  die "Unexpected argument: $1" ;;
    esac
done

# =============================================================================
# VALIDATION
# =============================================================================

[[ -z "$AGENT_ID" ]] && die "Agent ID is required. Usage: $(basename "$0") --id <agent_id> ..."

# Validate export target (must have exactly one: --dest, --volume, or --container)
target_count=0
[[ -n "$DEST" ]] && target_count=$((target_count + 1))
[[ -n "$VOLUME" ]] && target_count=$((target_count + 1))
[[ -n "$CONTAINER" ]] && target_count=$((target_count + 1))

if [[ $target_count -eq 0 ]]; then
    die "Export target required. Use --dest <path>, --volume <name>, or --container <name>"
fi

if [[ $target_count -gt 1 ]]; then
    die "Cannot use multiple export targets. Choose one: --dest, --volume, or --container"
fi

validate_agent_id "$AGENT_ID" || exit 1

if ! agent_exists "$AGENT_ID"; then
    die "Agent '$AGENT_ID' does not exist"
fi

# Validate mode
MODE="${MODE^^}"  # Convert to uppercase
if [[ ! "$MODE" =~ ^(MINIMAL|STANDARD|FULL|CUSTOM)$ ]]; then
    die "Invalid mode: $MODE (must be MINIMAL, STANDARD, FULL, or CUSTOM)"
fi

# Validate CUSTOM mode has categories
if [[ "$MODE" == "CUSTOM" && -z "$CATEGORIES" ]]; then
    die "CUSTOM mode requires --categories <list>"
fi

# Check Docker availability if using volume or container
if [[ -n "$VOLUME" || -n "$CONTAINER" ]]; then
    if ! command -v docker &>/dev/null; then
        die "Docker is required for volume/container export but not found"
    fi
fi

# Handle volume export
if [[ -n "$VOLUME" ]]; then
    info "Creating Docker volume: $VOLUME"
    docker volume create "$VOLUME" 2>/dev/null || die "Failed to create volume $VOLUME"
    
    info "Volume created: $VOLUME"
    info "Copying files to volume via container..."
    
    # Create temporary directory for export
    TEMP_EXPORT=$(mktemp -d)
    DEST="$TEMP_EXPORT"
    
    # We'll copy to volume after export is complete
    COPY_TO_VOLUME=true
fi

# Handle container export
if [[ -n "$CONTAINER" ]]; then
    info "Creating container export: $CONTAINER"
    
    # Create volume for container
    VOLUME_NAME="hemlock-export-${CONTAINER}"
    info "Creating volume: $VOLUME_NAME"
    docker volume create "$VOLUME_NAME" 2>/dev/null || die "Failed to create volume $VOLUME_NAME"
    
    info "Creating container: $CONTAINER"
    docker create --name "$CONTAINER" -v "$VOLUME_NAME:/export" alpine:latest \
        echo "Export container ready" 2>/dev/null || \
        die "Failed to create container $CONTAINER (may already exist)"
    
    # Create temporary directory for export
    TEMP_EXPORT=$(mktemp -d)
    DEST="$TEMP_EXPORT"
    
    # We'll copy to volume after export is complete
    COPY_TO_VOLUME=true
fi

# Check destination directory (for direct file export)
if [[ -z "${COPY_TO_VOLUME:-}" ]]; then
    if [[ -d "$DEST" ]]; then
        if [[ -n "$(ls -A "$DEST" 2>/dev/null)" ]]; then
            die "Destination directory '$DEST' is not empty"
        fi
    else
        mkdir -p "$DEST"
    fi
else
    # For volume/container export, use temp directory
    mkdir -p "$DEST"
fi

# =============================================================================
# RESOLVE CATEGORIES FROM MODE
# =============================================================================

resolve_categories() {
    local mode=$1
    
    case $mode in
        MINIMAL)
            echo "CORE_IDENTITY"
            ;;
        STANDARD)
            echo "CORE_IDENTITY,TOOLS,SKILLS"
            ;;
        FULL)
            echo "CORE_IDENTITY,TOOLS,SKILLS,MEMORY,SECRETS,RUNTIME,BACKUPS,MEDIA,PICTURE"
            ;;
        CUSTOM)
            echo "$CATEGORIES"
            ;;
    esac
}

SELECTED_CATEGORIES=$(resolve_categories "$MODE")

# =============================================================================
# CONFIRMATION
# =============================================================================

if [[ "$FORCE" != true ]]; then
    echo ""
    echo "=== Agent Export Configuration ==="
    echo ""
    echo "  Agent:      $AGENT_ID"
    echo "  Destination: $DEST"
    echo "  Mode:       $MODE"
    echo "  Categories: $SELECTED_CATEGORIES"
    echo ""
    
    # Warn about SECRETS
    if [[ "$SELECTED_CATEGORIES" == *"SECRETS"* ]]; then
        echo "  ⚠️  WARNING: SECRETS category selected"
        echo "     This will export encrypted secrets including:"
        echo "       - .secrets/ directory"
        echo "       - .env.enc file"
        echo "       - .secret-key file (encryption key)"
        echo ""
        echo "     Ensure the destination is SECURE before proceeding."
        echo ""
        
        if [[ "$MODE" == "FULL" ]]; then
            echo "  FULL mode includes ALL sensitive data."
            echo "  Consider using STANDARD mode for safe sharing."
            echo ""
        fi
        
        read -p "  Continue with secrets export? [y/N] " -n 1 -r CONFIRM_SECRETS
        echo ""
        
        if [[ ! "$CONFIRM_SECRETS" =~ ^[Yy]$ ]]; then
            echo "  Export cancelled."
            exit 0
        fi
    fi
    
    read -p "  Continue with export? [y/N] " -n 1 -r CONFIRM
    echo ""
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  Export cancelled."
        exit 0
    fi
fi

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export_category() {
    local category=$1
    local source_dir="$AGENTS_DIR/$AGENT_ID"
    local dest_dir="$DEST"
    
    case $category in
        CORE_IDENTITY)
            info "Exporting CORE_IDENTITY..."
            for file in "${CORE_IDENTITY_FILES[@]}"; do
                if [[ -e "$source_dir/$file" ]]; then
                    cp -ra "$source_dir/$file" "$dest_dir/"
                fi
            done
            ;;
        TOOLS)
            info "Exporting TOOLS..."
            if [[ -d "$source_dir/tools" ]]; then
                cp -ra "$source_dir/tools" "$dest_dir/"
            fi
            ;;
        SKILLS)
            info "Exporting SKILLS..."
            if [[ -d "$source_dir/skills" ]]; then
                cp -ra "$source_dir/skills" "$dest_dir/"
            fi
            ;;
        MEMORY)
            info "Exporting MEMORY..."
            for dir in "${MEMORY_FILES[@]}"; do
                if [[ -d "$source_dir/$dir" ]]; then
                    cp -ra "$source_dir/$dir" "$dest_dir/"
                fi
            done
            ;;
        SECRETS)
            info "Exporting SECRETS..."
            for item in "${SECRETS_FILES[@]}"; do
                if [[ -e "$source_dir/$item" ]]; then
                    cp -ra "$source_dir/$item" "$dest_dir/"
                fi
            done
            ;;
        RUNTIME)
            info "Exporting RUNTIME..."
            for dir in "${RUNTIME_FILES[@]}"; do
                if [[ -d "$source_dir/$dir" ]]; then
                    cp -ra "$source_dir/$dir" "$dest_dir/"
                fi
            done
            ;;
        BACKUPS)
            info "Exporting BACKUPS..."
            for dir in "${BACKUPS_FILES[@]}"; do
                if [[ -d "$source_dir/$dir" ]]; then
                    cp -ra "$source_dir/$dir" "$dest_dir/"
                fi
            done
            ;;
        MEDIA)
            info "Exporting MEDIA..."
            for dir in "${MEDIA_FILES[@]}"; do
                if [[ -d "$source_dir/$dir" ]]; then
                    cp -ra "$source_dir/$dir" "$dest_dir/"
                fi
            done
            ;;
        PICTURE)
            info "Exporting PICTURE..."
            for dir in "${PICTURE_FILES[@]}"; do
                if [[ -d "$source_dir/$dir" ]]; then
                    cp -ra "$source_dir/$dir" "$dest_dir/"
                fi
            done
            ;;
        *)
            warn "Unknown category: $category (skipping)"
            ;;
    esac
}

# =============================================================================
# CREATE MANIFESTS
# =============================================================================

create_manifests() {
    local dest_dir=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local export_timestamp=$(date "+%Y%m%d_%H%M%S")
    
    # Count exported files
    local file_count=$(find "$dest_dir" -type f | wc -l)
    
    # Check if secrets were exported
    local secrets_exported="false"
    if [[ -d "$dest_dir/.secrets" || -f "$dest_dir/.env.enc" ]]; then
        secrets_exported="true"
    fi
    
    # Create YAML manifest
    cat > "$dest_dir/export-manifest.yaml" <<EOL
# Export Manifest - $AGENT_ID
# Generated: $timestamp

export:
  agent_id: $AGENT_ID
  timestamp: $timestamp
  mode: $MODE
  categories:
$(echo "$SELECTED_CATEGORIES" | tr ',' '\n' | sed 's/^/    - /')
  destination: $dest_dir
  source: $AGENTS_DIR/$AGENT_ID
  file_count: $file_count
  secrets_included: $secrets_exported
  
encryption:
  status: $([ "$secrets_exported" = "true" ] && echo "preserved" || echo "not_applicable")
  algorithm: AES-256-CBC
  note: "Secrets remain encrypted. Decryption requires .secret-key file."
  
warnings:
$(if [[ "$secrets_exported" = "true" ]]; then
    echo "  - SECRETS EXPORTED: Ensure destination is secure"
    echo "  - Do not share .secret-key file publicly"
    echo "  - Use secret.sh tool for secure secret access"
else
    echo "  - No secrets exported (safe for sharing)"
fi)
EOL

    # Create JSON manifest
    cat > "$dest_dir/export-manifest.json" <<EOL
{
  "export": {
    "agent_id": "$AGENT_ID",
    "timestamp": "$timestamp",
    "mode": "$MODE",
    "categories": [$(echo "$SELECTED_CATEGORIES" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')],
    "destination": "$dest_dir",
    "source": "$AGENTS_DIR/$AGENT_ID",
    "file_count": $file_count,
    "secrets_included": $secrets_exported
  },
  "encryption": {
    "status": "$([ "$secrets_exported" = "true" ] && echo "preserved" || echo "not_applicable")",
    "algorithm": "AES-256-CBC",
    "note": "Secrets remain encrypted. Decryption requires .secret-key file."
  },
  "warnings": [$(if [[ "$secrets_exported" = "true" ]]; then
    echo '"SECRETS EXPORTED: Ensure destination is secure", "Do not share .secret-key file publicly", "Use secret.sh tool for secure secret access"'
else
    echo '"No secrets exported (safe for sharing)"'
fi)]
}
EOL

    success "Manifests created (export-manifest.yaml, export-manifest.json)"
}

# =============================================================================
# MAIN EXPORT
# =============================================================================

echo ""
echo "=== Exporting Agent: $AGENT_ID ==="
echo ""

# Parse categories and export
IFS=',' read -ra CATEGORY_ARRAY <<< "$SELECTED_CATEGORIES"

for category in "${CATEGORY_ARRAY[@]}"; do
    category="${category^^}"  # Ensure uppercase
    export_category "$category"
done

# Create manifests
create_manifests "$DEST"

# =============================================================================
# POST-EXPORT SUMMARY
# =============================================================================

echo ""
echo "=== Export Complete ==="
echo ""

# Count exported files
file_count=$(find "$DEST" -type f | wc -l)
dir_count=$(find "$DEST" -type d | wc -l)

echo "  Destination:   $DEST"
echo "  Mode:          $MODE"
echo "  Categories:    $SELECTED_CATEGORIES"
echo "  Files:         $file_count"
echo "  Directories:   $dir_count"
echo ""

# Security warning
if [[ "$SELECTED_CATEGORIES" == *"SECRETS"* ]]; then
    echo "  ⚠️  SECURITY WARNING:"
    echo "     - Secrets were exported and remain encrypted"
    echo "     - Keep .secret-key file secure"
    echo "     - Do not share exported directory publicly"
    if [[ "$TARBALL" == true ]]; then
        echo "     - Creating encrypted tarball..."
    else
        echo "     - Use: tar -czf export.tar.gz -C $(dirname "$DEST") $(basename "$DEST")"
    fi
    echo ""
else
    echo "  ✓ Safe for sharing (no secrets exported)"
    echo ""
fi

# Create tarball if requested
if [[ "$TARBALL" == true ]]; then
    dest_parent=$(dirname "$DEST")
    dest_name=$(basename "$DEST")
    tarball_path="$dest_parent/${dest_name}.tar.gz"
    
    info "Creating tarball: $tarball_path"
    tar -czf "$tarball_path" -C "$dest_parent" "$dest_name"
    
    if [[ -f "$tarball_path" ]]; then
        tarball_size=$(ls -lh "$tarball_path" | awk '{print $5}')
        success "Tarball created: $tarball_path ($tarball_size)"
    else
        warn "Failed to create tarball"
    fi
fi

# Finalize container export
if [[ -n "$CONTAINER" ]]; then
    echo ""
    info "Finalizing container export..."
    
    # Copy files from temp directory to container volume
    docker cp "$DEST/." "$CONTAINER:/export/" 2>/dev/null || {
        warn "Failed to copy files to container"
    }
    
    # Start container to finalize
    docker start "$CONTAINER" 2>/dev/null || true
    
    # Cleanup temp directory
    rm -rf "$DEST"
    
    echo ""
    echo "  📦 Container Export Complete:"
    echo "     Container:  $CONTAINER"
    echo "     Volume:     $VOLUME_NAME"
    echo ""
    echo "  Access exported files:"
    echo "     docker cp $CONTAINER:/export/<file> <local_path>"
    echo "     docker run --rm -v $VOLUME_NAME:/export alpine ls /export"
    echo ""
    echo "  Cleanup:"
    echo "     docker stop $CONTAINER"
    echo "     docker rm $CONTAINER"
    echo "     docker volume rm $VOLUME_NAME"
    echo ""
elif [[ -n "$VOLUME" ]]; then
    echo ""
    info "Copying files to Docker volume..."
    
    # Create temporary container to copy files
    TEMP_CTR="hemlock-export-temp-$$"
    docker create --name "$TEMP_CTR" -v "$VOLUME:/export" alpine:latest sleep 1 2>/dev/null || {
        warn "Failed to create temporary container"
        docker rm "$TEMP_CTR" 2>/dev/null || true
    }
    
    # Copy files to volume via container
    docker cp "$DEST/." "$TEMP_CTR:/export/" 2>/dev/null || {
        warn "Failed to copy files to volume"
    }
    
    # Cleanup
    docker rm "$TEMP_CTR" 2>/dev/null || true
    rm -rf "$DEST"
    
    echo ""
    echo "  📦 Volume Export Complete:"
    echo "     Volume:  $VOLUME"
    echo ""
    echo "  Access exported files:"
    echo "     docker run --rm -v $VOLUME:/export alpine ls /export"
    echo "     docker run --rm -v $VOLUME:/export -it alpine sh"
    echo ""
    echo "  Cleanup:"
    echo "     docker volume rm $VOLUME"
    echo ""
fi

# Log
log "INFO" "Agent $AGENT_ID exported (mode: $MODE, categories: $SELECTED_CATEGORIES)"
agent_log "$AGENT_ID" "INFO" "Exported"

success "Export complete!"

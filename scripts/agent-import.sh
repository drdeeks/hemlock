#!/bin/bash
# =============================================================================
# agent-import.sh — Import an agent from a directory or archive
#
# Handles everything: extraction, file copy (including hidden files), model
# detection from imported config, docker-compose.yml injection, Docker image
# build, and permission hardening.
#
# Usage:
#   ./scripts/agent-import.sh <source> <agent_id> [flags]
#   ./scripts/agent-import.sh --source <path> --target <id> [flags]
#
# Flags:
#   --source <path>     Source directory or archive (.tar.gz / .zip / .tar.bz2)
#   --target <id>       Agent ID for the imported agent
#   --model <model>     Override model (default: read from imported config.yaml)
#   --overwrite         Replace existing agent (backs up first)
#   --no-build          Skip Docker image build
#   --no-compose        Skip docker-compose.yml update
#   --quiet             Suppress non-error output
#
# Examples:
#   ./scripts/agent-import.sh /backups/titan/ titan
#   ./scripts/agent-import.sh /tmp/titan-export.tar.gz titan
#   ./scripts/agent-import.sh --source ./titan --target titan --no-build
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$RUNTIME_ROOT/agents"
LOG_DIR="$RUNTIME_ROOT/logs"
CONFIG_DIR="$RUNTIME_ROOT/config"
DOCKER_COMPOSE_FILE="$RUNTIME_ROOT/docker-compose.yml"

mkdir -p "$AGENTS_DIR" "$LOG_DIR" "$CONFIG_DIR"

source "$SCRIPT_DIR/helpers.sh"

# =============================================================================
# DEFAULTS
# =============================================================================

SOURCE=""
TARGET=""
MODEL_OVERRIDE=""
OVERWRITE=false
NO_BUILD=false
NO_COMPOSE=false
QUIET=false
TEMP_DIR=""

# =============================================================================
# HELPERS
# =============================================================================

info()    { [[ "$QUIET" == true ]] || echo "  $*"; }
success() { echo "  [OK] $*"; }
warn()    { echo "  [WARN] $*" >&2; }
die()     { echo "  [ERROR] $*" >&2; exit 1; }

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $(basename "$0") <source> <agent_id> [flags]
       $(basename "$0") --source <path> --target <id> [flags]

Import an agent from a directory or archive. Handles extraction, file copy
(including all hidden files), docker-compose.yml registration, Docker build,
and permission hardening.

Positional:
  <source>            Source directory or archive (.tar.gz / .zip / .tar.bz2)
  <agent_id>          Agent ID to import as (3-16 chars, lowercase, a-z0-9_-)

Flags:
  --source <path>     Source path (alternative to positional)
  --target <id>       Agent ID (alternative to positional)
  --model <model>     Override model (default: read from imported config.yaml)
  --overwrite         Replace existing agent (backs up first)
  --no-build          Skip Docker image build step
  --no-compose        Skip docker-compose.yml update
  --quiet             Suppress non-error output
  -h, --help          Show this help

Examples:
  $(basename "$0") /backups/titan/ titan
  $(basename "$0") /tmp/titan-export.tar.gz titan
  $(basename "$0") --source ./exported/titan --target titan --no-build
  $(basename "$0") --source backup.tar.gz --target myagent --overwrite
EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)      SOURCE="$2";        shift 2 ;;
        --target)      TARGET="$2";        shift 2 ;;
        --model)       MODEL_OVERRIDE="$2"; shift 2 ;;
        --overwrite)   OVERWRITE=true;      shift ;;
        --no-build)    NO_BUILD=true;       shift ;;
        --no-compose)  NO_COMPOSE=true;     shift ;;
        --quiet|-q)    QUIET=true;          shift ;;
        -h|--help)     usage ;;
        -*) die "Unknown flag: $1 (try --help)" ;;
        *)  POSITIONAL+=("$1"); shift ;;
    esac
done

# Accept positional args as fallback
if [[ -z "$SOURCE" && ${#POSITIONAL[@]} -ge 1 ]]; then SOURCE="${POSITIONAL[0]}"; fi
if [[ -z "$TARGET" && ${#POSITIONAL[@]} -ge 2 ]]; then TARGET="${POSITIONAL[1]}"; fi

# =============================================================================
# VALIDATION
# =============================================================================

[[ -z "$SOURCE" ]] && die "Source path is required. Usage: $(basename "$0") <source> <agent_id>"
[[ -z "$TARGET" ]] && die "Agent ID is required. Usage: $(basename "$0") <source> <agent_id>"

validate_agent_id "$TARGET" || exit 1

if agent_exists "$TARGET"; then
    if [[ "$OVERWRITE" == true ]]; then
        BACKUP_PATH="$RUNTIME_ROOT/backups/agents/${TARGET}-pre-import-$(date +%Y%m%d-%H%M%S)"
        warn "Agent '$TARGET' already exists — backing up to $BACKUP_PATH"
        mkdir -p "$(dirname "$BACKUP_PATH")"
        cp -ra "$AGENTS_DIR/$TARGET" "$BACKUP_PATH"
        rm -rf "$AGENTS_DIR/$TARGET"
    else
        die "Agent '$TARGET' already exists. Use --overwrite to replace it."
    fi
fi

# =============================================================================
# STEP 1 — Resolve source (directory or archive)
# =============================================================================

echo ""
echo "=== Importing agent: $TARGET ==="
echo ""

info "Source: $SOURCE"

EXTRACT_DIR=""

if [[ -d "$SOURCE" ]]; then
    EXTRACT_DIR="$SOURCE"
    info "Source type: directory"

elif [[ -f "$SOURCE" ]]; then
    TEMP_DIR="$(mktemp -d)"
    info "Source type: archive — extracting..."

    case "$SOURCE" in
        *.tar.gz|*.tgz)
            tar -xzf "$SOURCE" -C "$TEMP_DIR" || die "Failed to extract $SOURCE"
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "$SOURCE" -C "$TEMP_DIR" || die "Failed to extract $SOURCE"
            ;;
        *.tar)
            tar -xf "$SOURCE" -C "$TEMP_DIR" || die "Failed to extract $SOURCE"
            ;;
        *.zip)
            command -v unzip >/dev/null || die "'unzip' is required to extract .zip archives (apt install unzip)"
            unzip -q "$SOURCE" -d "$TEMP_DIR" || die "Failed to extract $SOURCE"
            ;;
        *)
            die "Unsupported archive format: $SOURCE (supported: .tar.gz .tgz .tar.bz2 .zip .tar)"
            ;;
    esac

    # If the archive extracted to a single subdirectory, descend into it
    EXTRACTED_CONTENTS=("$TEMP_DIR"/*/)
    if [[ ${#EXTRACTED_CONTENTS[@]} -eq 1 && -d "${EXTRACTED_CONTENTS[0]}" ]]; then
        EXTRACT_DIR="${EXTRACTED_CONTENTS[0]}"
        info "Archive root: $(basename "$EXTRACT_DIR")"
    else
        EXTRACT_DIR="$TEMP_DIR"
    fi

else
    die "Source not found: $SOURCE (must be a directory or archive file)"
fi

# =============================================================================
# STEP 2 — Detect model from imported config
# =============================================================================

IMPORTED_MODEL="nous/mistral-large"

if [[ -f "$EXTRACT_DIR/config.yaml" ]]; then
    DETECTED=$(grep -E '^\s*model:' "$EXTRACT_DIR/config.yaml" | head -1 | sed 's/.*model:[[:space:]]*//' | tr -d '"'"'" | xargs)
    if [[ -n "$DETECTED" ]]; then
        IMPORTED_MODEL="$DETECTED"
        info "Detected model from config.yaml: $IMPORTED_MODEL"
    fi
elif [[ -f "$EXTRACT_DIR/agent.json" ]]; then
    DETECTED=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$EXTRACT_DIR/agent.json" | head -1 | sed 's/.*"model"[[:space:]]*:[[:space:]]*"//' | tr -d '"')
    if [[ -n "$DETECTED" ]]; then
        IMPORTED_MODEL="$DETECTED"
        info "Detected model from agent.json: $IMPORTED_MODEL"
    fi
fi

# Apply override if given
MODEL="${MODEL_OVERRIDE:-$IMPORTED_MODEL}"
[[ -n "$MODEL_OVERRIDE" ]] && info "Model overridden to: $MODEL"

# =============================================================================
# STEP 3 — Copy all agent files (including hidden files/directories)
# =============================================================================

info "Copying agent files..."

mkdir -p "$AGENTS_DIR/$TARGET"

# The trailing /. on SOURCE ensures cp -ra copies all hidden files too
cp -ra "$EXTRACT_DIR/." "$AGENTS_DIR/$TARGET/" 2>/dev/null || {
    warn "Some files could not be copied (permissions?) — continuing"
}

success "Files copied to agents/$TARGET/"

# =============================================================================
# STEP 4 — Ensure required files exist (create defaults if missing)
# =============================================================================

# config.yaml
if [[ ! -f "$AGENTS_DIR/$TARGET/config.yaml" ]]; then
    info "No config.yaml found — creating default..."
    cat > "$AGENTS_DIR/$TARGET/config.yaml" <<EOF
agent:
  id: $TARGET
  name: $TARGET
  model: "$MODEL"
  personality: "imported"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOF
fi

# SOUL.md (at agent root — required by lifecycle scripts)
if [[ ! -f "$AGENTS_DIR/$TARGET/SOUL.md" ]]; then
    # Try to find it in a data/ subdirectory
    if [[ -f "$AGENTS_DIR/$TARGET/data/SOUL.md" ]]; then
        cp "$AGENTS_DIR/$TARGET/data/SOUL.md" "$AGENTS_DIR/$TARGET/SOUL.md"
    else
        cat > "$AGENTS_DIR/$TARGET/SOUL.md" <<EOF
# SOUL.md — $TARGET

**Identity:** $TARGET
**Purpose:** Imported agent
**Model:** $MODEL
EOF
    fi
fi

# .env (must exist; preserve imported one if present)
if [[ ! -f "$AGENTS_DIR/$TARGET/.env" ]]; then
    touch "$AGENTS_DIR/$TARGET/.env"
    info "Created empty .env — add TELEGRAM_BOT_TOKEN and API keys before starting"
fi

# Ensure required directories exist
mkdir -p \
    "$AGENTS_DIR/$TARGET/data" \
    "$AGENTS_DIR/$TARGET/config" \
    "$AGENTS_DIR/$TARGET/logs" \
    "$AGENTS_DIR/$TARGET/skills" \
    "$AGENTS_DIR/$TARGET/tools" \
    "$AGENTS_DIR/$TARGET/memory" \
    "$AGENTS_DIR/$TARGET/sessions" \
    "$AGENTS_DIR/$TARGET/.secrets"

success "Required directories and files verified"

# =============================================================================
# STEP 5 — Harden file permissions
# =============================================================================

chmod 700 "$AGENTS_DIR/$TARGET/.secrets" 2>/dev/null || true
chmod 600 "$AGENTS_DIR/$TARGET/.env"     2>/dev/null || true

success "Permissions hardened (.secrets/=700, .env=600)"

# =============================================================================
# STEP 6 — Register in docker-compose.yml
# =============================================================================

if [[ "$NO_COMPOSE" == true ]]; then
    info "Skipping docker-compose.yml update (--no-compose)"
elif [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    warn "docker-compose.yml not found — skipping registration"
else
    if grep -q "container_name: oc-${TARGET}$" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        info "Agent $TARGET already registered in docker-compose.yml"
    else
        info "Adding agent to docker-compose.yml..."

        # Build the service block as a variable
        SERVICE_BLOCK="
  # ---------------------------------------------------------------------------
  # $TARGET (imported)
  # ---------------------------------------------------------------------------
  oc-${TARGET}:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: ${TARGET}
        MODEL: ${MODEL}
    image: hemlock/agent-${TARGET}:1.0.0
    container_name: oc-${TARGET}
    restart: unless-stopped
    environment:
      - AGENT_ID=${TARGET}
      - MODEL=${MODEL}
      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - ./agents/${TARGET}/data:/app/data
      - ./agents/${TARGET}/config:/app/config
    networks:
      - agents_net
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:size=64m
    depends_on:
      openclaw-gateway:
        condition: service_healthy
    healthcheck:
      test: [\"CMD\", \"pgrep\", \"-x\", \"hermes\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s"

        # Insert the service block before the networks section using awk
        # Matches the line that starts the networks block comment or the networks: key
        awk -v block="$SERVICE_BLOCK" '
            /^# ={5,}$/ && found_services && !inserted {
                print block
                inserted=1
            }
            /^networks:/ && !inserted {
                print block
                inserted=1
            }
            /^services:/ { found_services=1 }
            { print }
        ' "$DOCKER_COMPOSE_FILE" > "${DOCKER_COMPOSE_FILE}.tmp"

        mv "${DOCKER_COMPOSE_FILE}.tmp" "$DOCKER_COMPOSE_FILE"
        success "Registered oc-${TARGET} in docker-compose.yml"
    fi
fi

# =============================================================================
# STEP 7 — Build Docker image
# =============================================================================

if [[ "$NO_BUILD" == true ]]; then
    info "Skipping Docker build (--no-build)"
elif ! check_docker 2>/dev/null; then
    warn "Docker not available — skipping image build"
    warn "Run 'docker compose build oc-${TARGET}' when Docker is ready"
else
    info "Building Docker image for oc-${TARGET}..."
    docker compose -f "$DOCKER_COMPOSE_FILE" build "oc-${TARGET}" 2>&1 || {
        warn "Docker build failed — you can retry manually:"
        warn "  docker compose build oc-${TARGET}"
    }
    success "Docker image built: oc-${TARGET}"
fi

# =============================================================================
# STEP 8 — Log and summarise
# =============================================================================

log "INFO" "Agent $TARGET imported from $SOURCE (model: $MODEL)"
agent_log "$TARGET" "INFO" "Imported from $SOURCE"

echo ""
echo "=== Import complete: $TARGET ==="
echo ""

# Check for missing secrets and warn specifically
if [[ -f "$AGENTS_DIR/$TARGET/.env" ]]; then
    if ! grep -q "TELEGRAM_BOT_TOKEN" "$AGENTS_DIR/$TARGET/.env" 2>/dev/null; then
        echo "  [!] TELEGRAM_BOT_TOKEN not set — add it before starting:"
        echo "      echo 'TELEGRAM_BOT_TOKEN=<token>' >> agents/${TARGET}/.env"
        echo ""
    fi
    if ! grep -qE "NOUS_API_KEY|OPENROUTER_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY" "$AGENTS_DIR/$TARGET/.env" 2>/dev/null; then
        echo "  [!] No LLM API key found — add one before starting:"
        echo "      echo 'NOUS_API_KEY=<key>' >> agents/${TARGET}/.env"
        echo ""
    fi
fi

echo "  Agent directory:  agents/${TARGET}/"
echo "  Model:            $MODEL"
echo "  Container name:   oc-${TARGET}"
echo ""
echo "  Next steps:"
echo "    1. Add secrets if needed:  vim agents/${TARGET}/.env"
echo "    2. Start the agent:        ./scripts/agent-control.sh start ${TARGET}"
echo "    3. Or start all services:  docker compose up -d"
echo "    4. Stream logs:            ./scripts/agent-logs.sh ${TARGET}"
echo ""

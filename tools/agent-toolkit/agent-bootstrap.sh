#!/usr/bin/env bash
# ==============================================================================
# agent-bootstrap.sh — Hermes Multi-Agent Manager
# ==============================================================================
#
# Commands:
#   init   <name>     Bootstrap a new agent (interactive)
#   scan              Diagnose all agents — config, symlinks, services, health
#   sync              Detect changes, reconcile config, create missing links
#   link   <name>     Wire symlinks for an existing agent
#   unlink <name>     Remove symlinks (keeps agent files intact)
#   repair <name>     Fix broken config / symlinks / env for one agent
#   list              Show all agents and their status
#   delete <name>     Remove agent (backs up first)
#
# Works with: cloud-only, local-only, or hybrid provider setups.
# No hardcoded provider assumptions. You pick what you use.
#
# Requirements: bash 4+, hermes CLI
# Optional:     curl, jq, git, systemctl
# ==============================================================================

set -euo pipefail

VERSION="3.5.0"

# ── Error handling ────────────────────────────────────────────────────────────

_SCRIPT_NAME="$(basename "$0")"
_ON_ERROR_MSG=""

on_error() {
    local exit_code=$?
    echo "" >&2
    echo -e "\033[0;31m✗ ${_SCRIPT_NAME} failed (exit ${exit_code})\033[0m" >&2
    if [ -n "$_ON_ERROR_MSG" ]; then
        echo -e "  ${_ON_ERROR_MSG}" >&2
    fi
    echo "  Check: ${0} scan    — to diagnose agent state" >&2
    echo "  Check: ${0} repair  — to fix broken config" >&2
    echo "  Backups may be in: /tmp/hermes-backup-*/" >&2
    exit "$exit_code"
}
trap on_error ERR

# ── Safe sed replacement ──────────────────────────────────────────────────────
# Replace a line in a file, safely handling ANY characters in the replacement.
# Usage: safe_replace <file> <pattern> <replacement>
# Pattern is an extended regex matched against line start.
safe_replace() {
    local file="$1" pattern="$2" replacement="$3"
    [ -f "$file" ] || return 1

    # Find a safe delimiter not in the replacement
    local delim="/"
    for d in '|' '#' '%' '@' ',' '!' '^' '~'; do
        if [[ "$replacement" != *"$d"* ]]; then
            delim="$d"
            break
        fi
    done

    # Escape the delimiter in the replacement (if any remain)
    local escaped="${replacement//${delim}/\\${delim}}"

    sed -i "s${delim}${pattern}${delim}${escaped}${delim}" "$file"
}

# ── Safe env set ──────────────────────────────────────────────────────────────
# Set KEY=VALUE in an env file, handling any special characters.
# Usage: safe_env_set <file> <key> <value>
safe_env_set() {
    local file="$1" key="$2" value="$3"
    [ -f "$file" ] || return 1

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Replace existing (may have special chars — use awk)
        awk -v key="$key" -v val="$value" '
            BEGIN { FS=OFS="=" }
            $1 == key { $0 = key "=" val; found=1 }
            { print }
            END { if (!found) print key "=" val }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    elif grep -q "^# ${key}=" "$file" 2>/dev/null; then
        # Uncomment and set
        awk -v key="$key" -v val="$value" '
            $0 == "# " key "=" || $0 ~ "^# " key "=.*" { print key "=" val; next }
            { print }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        # Append
        echo "${key}=${value}" >> "$file"
    fi
}

# ── Global flags ──────────────────────────────────────────────────────────────
# Parse before any command dispatch. All flags are position-independent.

DRY_RUN=false
FORCE=false
OPENCLAW_MODE=false
NO_CONFIRM=false

_args=()
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)     DRY_RUN=true ;;
        --force|-f)       FORCE=true ;;
        --openclaw|-o)    OPENCLAW_MODE=true ;;
        --yes|-y)         NO_CONFIRM=true ;;
        *)                _args+=("$arg") ;;
    esac
done
set -- "${_args[@]}"

# Wrapper: execute command unless dry-run
run() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} $*"
        return 0
    fi
    "$@"
}

# Wrapper for commands with complex output redirection
run_eval() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} $1"
        return 0
    fi
    eval "$1"
}

# Safe file write — refuses to overwrite existing non-empty files unless --force
# Usage: safe_write <path> <label> [content_via_heredoc]
safe_write() {
    local path="$1" label="$2"
    if [ -f "$path" ] && [ -s "$path" ]; then
        if [ "${FORCE:-false}" = "true" ]; then
            backup_file "$path" "$(dirname "$path")/.backups"
            warn "Overwriting existing ${label} (backed up)"
            return 0  # caller may write
        else
            warn "Skipped ${label}: ${path} already exists (use --force to overwrite)"
            return 1
        fi
    fi
    return 0  # safe to write
}

# Safe prompt — skips if --yes flag set
safe_prompt_yn() {
    if [ "$NO_CONFIRM" = true ]; then
        return 0
    fi
    prompt_yn "$@"
}

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC} $*" >&2; }
info()   { echo -e "${CYAN}→${NC} $*"; }
header() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }
die()    { err "$*"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
#
# Two modes:
#   HERMES mode (default):  ~/.hermes/profiles/<agent>/
#   OPENCLAW mode:          ~/.openclaw/agents/<agent>/
#
# In OpenClaw mode, the agent directory IS the HERMES_HOME. OpenClaw owns
# the structure, Hermes reads from it. No symlinks needed.
#
# Legacy path ~/.hermes-<agent>/ is always detected and bridged.

HOME_DIR="${HOME}"
HERMES_ROOT="${HERMES_HOME:-${HOME_DIR}/.hermes}"
PROFILES_ROOT="${HERMES_ROOT}/profiles"                    # ~/.hermes/profiles/
OPENCLAW_ROOT="${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}"    # ~/.openclaw/
OPENCLAW_AGENTS="${OPENCLAW_ROOT}/agents"                  # ~/.openclaw/agents/
AGENTS_ROOT="${AGENTS_ROOT:-}"                             # optional separate workspace
HERMES_BIN="${HERMES_BIN:-$(command -v hermes 2>/dev/null || echo "")}"

# Auto-detect OpenClaw mode if running from inside ~/.openclaw/
if [ "$OPENCLAW_MODE" = false ]; then
    _sd="$(cd "$(dirname "$0")" && pwd 2>/dev/null || echo "")"
    [[ "$_sd" == *".openclaw"* ]] && OPENCLAW_MODE=true
    unset _sd
fi

VENV_BIN="${VENV_BIN:-}"

timestamp() { date -u +%Y%m%dT%H%M%SZ; }

# ── Resolve hermes binary ────────────────────────────────────────────────────

resolve_hermes() {
    if [ -n "$HERMES_BIN" ] && [ -x "$HERMES_BIN" ]; then
        echo "$HERMES_BIN"
        return
    fi
    # Try common locations
    for candidate in \
        "$(command -v hermes 2>/dev/null)" \
        "${HOME_DIR}/.hermes/hermes-agent/venv/bin/hermes" \
        "${HOME_DIR}/hermes-agent/venv/bin/hermes" \
        "/usr/local/bin/hermes"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            HERMES_BIN="$candidate"
            echo "$candidate"
            return
        fi
    done
    echo ""
}

# ── Agent directory helpers ───────────────────────────────────────────────────
#
# In OpenClaw mode:
#   Primary:  ~/.openclaw/agents/<agent>/    (HERMES_HOME for the agent)
#   No legacy bridge needed — OpenClaw IS the canonical location
#
# In Hermes mode:
#   Primary:  ~/.hermes/profiles/<agent>/    (what hermes -p reads)
#   Legacy:   ~/.hermes-<agent>/             (detected, bridged via symlinks)

# The canonical agent home — changes based on mode
profile_dir() {
    if [ "$OPENCLAW_MODE" = true ]; then
        echo "${OPENCLAW_AGENTS}/$1"
    else
        echo "${PROFILES_ROOT}/$1"
    fi
}

# Legacy HERMES_HOME pattern (always available for detection)
legacy_home()   { echo "${HOME_DIR}/.hermes-$1"; }

# Resolve the active HERMES_HOME for an agent
resolve_home() {
    if [ "$OPENCLAW_MODE" = true ]; then
        echo "${OPENCLAW_AGENTS}/$1"
        return
    fi
    # Check all sources in priority order
    local openclaw profile legacy
    openclaw="${OPENCLAW_AGENTS}/$1"
    profile="$(profile_dir "$1")"
    legacy="$(legacy_home "$1")"
    if [ -d "$openclaw" ]; then
        echo "$openclaw"
    elif [ -d "$profile" ]; then
        echo "$profile"
    elif [ -d "$legacy" ]; then
        echo "$legacy"
    else
        echo "$profile"
    fi
}

# Config/env/secrets/backup paths — always inside the profile dir
agent_config()      { echo "$(profile_dir "$1")/config.yaml"; }
agent_env()         { echo "$(profile_dir "$1")/.env"; }
agent_secrets()     { echo "$(profile_dir "$1")/.secrets"; }
agent_backup_dir()  { echo "$(profile_dir "$1")/.backups"; }

# Keep hermes_home() for backward compat
hermes_home() { resolve_home "$1"; }

# Mode label for display
mode_label() {
    if [ "$OPENCLAW_MODE" = true ]; then
        echo "openclaw"
    else
        echo "hermes"
    fi
}

# ── Prompt helpers ────────────────────────────────────────────────────────────

prompt() {
    local msg="$1" default="${2:-}"
    local input
    if [ -n "$default" ]; then
        read -rp "$(echo -e "${CYAN}?${NC} ${msg} [${default}]: ")" input
        echo "${input:-$default}"
    else
        while true; do
            read -rp "$(echo -e "${CYAN}?${NC} ${msg}: ")" input
            [ -n "$input" ] && { echo "$input"; return; }
            warn "Required"
        done
    fi
}

prompt_secret() {
    local msg="$1" allow_empty="${2:-false}"
    local input
    while true; do
        read -rsp "$(echo -e "${CYAN}?${NC} ${msg}: ")" input
        echo
        if [ -n "$input" ]; then echo "$input"; return; fi
        [ "$allow_empty" = "true" ] && { echo ""; return; }
        warn "Cannot be empty"
    done
}

prompt_yn() {
    local msg="$1" default="${2:-y}"
    local input
    read -rp "$(echo -e "${CYAN}?${NC} ${msg} [${default}]: ")" input
    input="${input:-$default}"
    [[ "$input" =~ ^[Yy] ]]
}

# ── Backup ────────────────────────────────────────────────────────────────────

backup_file() {
    local src="$1" backup_dir="$2"
    [ -e "$src" ] || [ -L "$src" ] || return 0
    run mkdir -p "$backup_dir" || return 0
    local fname ts dest
    fname="$(basename "$src")"
    ts="$(timestamp)"
    dest="${backup_dir}/${fname}.${ts}.bak"

    if [ -d "$src" ] && [ ! -L "$src" ]; then
        # Full directory — rsync with hidden files, exclude node_modules
        if command -v rsync &>/dev/null; then
            run rsync -a --exclude='node_modules' --exclude='__pycache__' --exclude='.git' \
                "$src/" "$dest/" 2>/dev/null && log "Backed up dir ${fname} → ${dest}/" || warn "Backup failed for ${fname}"
        else
            # Fallback: cp -a with find to exclude node_modules
            run mkdir -p "$dest" || true
            if run cp -a "$src/." "$dest/" 2>/dev/null; then
                run find "$dest" -type d \( -name 'node_modules' -o -name '__pycache__' -o -name '.git' \) \
                    -exec rm -rf {} + 2>/dev/null || true
                log "Backed up dir ${fname} → ${dest}/"
            else
                warn "Backup failed for ${fname} (cp error)"
            fi
        fi
    elif [ -L "$src" ]; then
        run cp -P "$src" "$dest" 2>/dev/null && log "Backed up symlink ${fname}" || warn "Backup failed for ${fname}"
    else
        run cp "$src" "$dest" 2>/dev/null && log "Backed up ${fname}" || warn "Backup failed for ${fname}"
    fi
}

# ── Validate API key (optional) ──────────────────────────────────────────────

validate_key() {
    local label="$1" key="$2" base_url="$3"
    command -v curl &>/dev/null || { warn "curl not found — skipping key validation"; return 0; }
    [ -z "$key" ] && { warn "Empty key for ${label}"; return 1; }
    [ -z "$base_url" ] && { warn "No URL for ${label} — skipping validation"; return 0; }

    info "Testing ${label}…"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${base_url}/models" \
        -H "Authorization: Bearer ${key}" \
        --connect-timeout 5 --max-time 10 2>/dev/null) || true
    [ -z "$http_code" ] && http_code="000"

    case "$http_code" in
        200|201) log "${label} — valid"; return 0 ;;
        401|403) warn "${label} — rejected (HTTP ${http_code})"; return 1 ;;
        429)     warn "${label} — rate limited (still usable)"; return 0 ;;
        000)     warn "${label} — unreachable"; return 1 ;;
        *)       warn "${label} — HTTP ${http_code}"; return 1 ;;
    esac
}

# ==============================================================================
# COMMAND: init
# ==============================================================================

cmd_init() {
    local AGENT="${1:-}"
    [ -z "$AGENT" ] && die "Usage: $0 init <agent-name>"

    # Sanitize name
    AGENT="${AGENT,,}"
    AGENT="${AGENT// /-}"
    AGENT="$(echo "$AGENT" | sed 's/[^a-z0-9-]//g')"
    [ -z "$AGENT" ] && die "Invalid agent name"

    local HH ENV_FILE CONF_FILE BK_DIR
    HH="$(resolve_home "$AGENT")"
    ENV_FILE="$(agent_env "$AGENT")"
    CONF_FILE="$(agent_config "$AGENT")"
    BK_DIR="$(agent_backup_dir "$AGENT")"

    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║         Hermes Agent Bootstrap v${VERSION}          ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Check existing ─────────────────────────────────────────────────────
    if [ -d "$HH" ]; then
        warn "Profile already exists: ${HH}"
        safe_prompt_yn "Update existing?" "n" || { info "Aborted."; return 0; }

        # Full directory backup before any modification
        local full_backup_dir
        full_backup_dir="/tmp/hermes-backup-${AGENT}-$(timestamp)"
        run mkdir -p "$full_backup_dir"
        backup_file "$HH" "$full_backup_dir"
        log "Full backup: ${full_backup_dir}/$(basename "$HH").*.bak/"
    fi

    header "Directory Structure"

    # Create the agent home directory (this is HERMES_HOME)
    run mkdir -p "$HH"
    if [ "$OPENCLAW_MODE" = true ]; then
        log "OpenClaw agent: ${HH}"
    else
        log "Profile: ${HH}"
    fi

    # Create subdirs — OpenClaw structure has more directories
    if [ "$OPENCLAW_MODE" = true ]; then
        for sub in sessions projects submissions memory tools knowledge archives \
                   skills logs .secrets .backups; do
            [ -d "${HH}/${sub}" ] || run mkdir -p "${HH}/${sub}"
        done
    else
        for sub in sessions projects skills tools docs logs .secrets .backups; do
            [ -d "${HH}/${sub}" ] || run mkdir -p "${HH}/${sub}"
        done
    fi

    # Create identity files if they don't exist
    for f in SOUL.md USER.md MEMORY.md TOOLS.md AGENTS.md HEARTBEAT.md README.md; do
        if [ ! -f "${HH}/${f}" ]; then
            run touch "${HH}/${f}"
        else
            info "Preserved existing: ${f}"
        fi
    done

    log "Directories ready"

    # ── Provider setup ─────────────────────────────────────────────────────
    header "Provider Configuration"
    echo ""
    echo "Configure your model provider. Works with any OpenAI-compatible API."
    echo ""

    local PROVIDER_NAME PROVIDER_URL PROVIDER_KEY MODEL_NAME
    local FALLBACK_NAME FALLBACK_URL FALLBACK_KEY FALLBACK_MODEL

    echo "Provider options:"
    echo "  1) Cloud API (OpenAI, Anthropic, Mistral, Nous, OpenRouter, Venice, etc.)"
    echo "  2) Local inference (Ollama, llama.cpp, vLLM, etc.)"
    echo "  3) Custom OpenAI-compatible endpoint"
    echo ""

    local ptype
    ptype=$(prompt "Select (1/2/3)" "1")

    case "$ptype" in
        1)
            PROVIDER_NAME=$(prompt "Provider name (e.g., openai, anthropic, nous, openrouter)")
            PROVIDER_URL=$(prompt "Base URL (e.g., https://api.openai.com/v1)")
            MODEL_NAME=$(prompt "Model ID (e.g., gpt-4o, claude-sonnet-4, xiaomi/mimo-v2-pro)")
            PROVIDER_KEY=$(prompt_secret "API key")
            ;;
        2)
            PROVIDER_NAME="local"
            PROVIDER_URL=$(prompt "Local endpoint URL" "http://localhost:11434/v1")
            MODEL_NAME=$(prompt "Model name (e.g., qwen2.5:7b, llama-3)")
            PROVIDER_KEY=""
            ;;
        3)
            PROVIDER_NAME="custom"
            PROVIDER_URL=$(prompt "Base URL")
            MODEL_NAME=$(prompt "Model ID")
            PROVIDER_KEY=$(prompt_secret "API key (leave blank if none)" "true")
            ;;
    esac

    # Optional validation
    if [ -n "$PROVIDER_KEY" ] && [ -n "$PROVIDER_URL" ]; then
        validate_key "Primary (${PROVIDER_NAME})" "$PROVIDER_KEY" "$PROVIDER_URL" || true
    fi

    # Fallback (optional)
    local HAS_FALLBACK=false
    if safe_prompt_yn "Add a fallback provider?" "n"; then
        HAS_FALLBACK=true
        echo ""
        echo "Fallback provider:"
        FALLBACK_NAME=$(prompt "Provider name")
        FALLBACK_URL=$(prompt "Base URL")
        FALLBACK_MODEL=$(prompt "Model ID")
        FALLBACK_KEY=$(prompt_secret "API key (leave blank if none)" "true")
        [ -n "$FALLBACK_KEY" ] && validate_key "Fallback (${FALLBACK_NAME})" "$FALLBACK_KEY" "$FALLBACK_URL" || true
    fi

    # ── Messaging platform ─────────────────────────────────────────────────
    header "Messaging Platform"
    echo ""
    echo "Supported: Telegram, Discord, Slack, WhatsApp, Signal, Matrix, Home Assistant, none"
    echo ""

    local PLATFORM
    PLATFORM=$(prompt "Platform (or 'none')" "none")

    local BOT_TOKEN=""
    local ALLOWED_USERS=""
    local HOME_CHANNEL=""

    if [ "$PLATFORM" != "none" ]; then
        BOT_TOKEN=$(prompt_secret "${PLATFORM} bot token")
        ALLOWED_USERS=$(prompt "Allowed user IDs (comma-separated)" "")
        HOME_CHANNEL=$(prompt "Home channel/chat ID" "")
    fi

    # ── Write .env ─────────────────────────────────────────────────────────
    header "Generating Config"

    local ENV_FILE CONF_FILE BK_DIR
    ENV_FILE="$(agent_env "$AGENT")"
    CONF_FILE="$(agent_config "$AGENT")"
    BK_DIR="$(agent_backup_dir "$AGENT")"

    if safe_write "$ENV_FILE" ".env"; then
        if [ "$DRY_RUN" = false ]; then
        {
            echo "# ============================================================"
            echo "# Agent: ${AGENT}"
            echo "# Generated: $(timestamp)"
            echo "# Managed by agent-bootstrap.sh"
            echo "# ============================================================"
            echo ""
            echo "# Primary provider: ${PROVIDER_NAME}"
            local key_var
            key_var="$(echo "${PROVIDER_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY"
            echo "${key_var}=${PROVIDER_KEY}"
            echo ""

            if [ "$HAS_FALLBACK" = true ]; then
                echo "# Fallback provider: ${FALLBACK_NAME}"
                local fb_key_var
                fb_key_var="$(echo "${FALLBACK_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY"
                echo "${fb_key_var}=${FALLBACK_KEY}"
                echo ""
            fi

            if [ "$PLATFORM" != "none" ]; then
                echo "# Platform: ${PLATFORM}"
                local plat_var
                plat_var="$(echo "${PLATFORM}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_BOT_TOKEN"
                echo "${plat_var}=${BOT_TOKEN}"
                [ -n "$ALLOWED_USERS" ] && {
                    local allow_var
                    allow_var="$(echo "${PLATFORM}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_ALLOWED_USERS"
                    echo "${allow_var}=${ALLOWED_USERS}"
                }
                [ -n "$HOME_CHANNEL" ] && {
                    local hc_var
                    hc_var="$(echo "${PLATFORM}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_HOME_CHANNEL"
                    echo "${hc_var}=${HOME_CHANNEL}"
                }
            fi

            echo ""
            echo "# Skip gateway chmod 700/600 — prevents locking host user out"
            echo "HERMES_MANAGED=true"
        } > "$ENV_FILE"
        else
            echo -e "  ${DIM}[dry-run]${NC} Write .env → ${ENV_FILE}"
        fi

        run chmod 600 "$ENV_FILE"
        log ".env written → ${ENV_FILE}"
    fi

    # ── Write config.yaml (clean minimal format) ──────────────────────────
    if safe_write "$CONF_FILE" "config.yaml"; then
        if [ "$DRY_RUN" = false ]; then
        {
            echo "model:"
            echo "  default: ${MODEL_NAME}"
            echo "  provider: ${PROVIDER_NAME}"
            echo "  base_url: ${PROVIDER_URL}"
            echo ""
            echo "tools:"
            echo "  profile: coding"
            echo ""
            echo "memory:"
            echo "  enabled: true"
            echo "  max_chars: 100000"
            echo ""
            echo "skills:"
            echo "  enabled: true"

            if [ "$HAS_FALLBACK" = true ]; then
                echo ""
                echo "# ── Provider Fallback Chain ─────────────────────────────────────────"
                echo "fallback_providers:"
                echo "  - provider: ${FALLBACK_NAME}"
                echo "    model: ${FALLBACK_MODEL}"
            else
                echo ""
                echo "# ── Provider Fallback Chain ─────────────────────────────────────────"
                echo "# Add fallback providers to prevent downtime if primary is unavailable."
                echo "# Supported: openrouter, openai, anthropic, mistral, nous, ollama"
                echo "# fallback_providers:"
                echo "#   - provider: openrouter"
                echo "#     model: google/gemma-3-27b-it"
                echo "#   - provider: mistral"
                echo "#     model: mistral-small-latest"
            fi
        } > "$CONF_FILE"
        else
            echo -e "  ${DIM}[dry-run]${NC} Write config.yaml → ${CONF_FILE}"
        fi

        log "config.yaml written → ${CONF_FILE}"
    fi

    # ── Symlinks ───────────────────────────────────────────────────────────
    header "Wiring"

    if [ "$OPENCLAW_MODE" = true ]; then
        # OpenClaw mode: files live directly in the agent dir, no symlinks needed
        log "OpenClaw mode: config in ${HH}"
    elif [ -n "$AGENTS_ROOT" ]; then
        # AGENTS_ROOT mode: canonical files elsewhere, profile gets symlinks
        info "Symlinking profile → workspace (AGENTS_ROOT mode)"
        _safe_link "$CONF_FILE" "${HH}/config.yaml" "$BK_DIR"
        _safe_link "$ENV_FILE" "${HH}/.env" "$BK_DIR"
    else
        # Hermes mode: files in profile, bridge legacy if exists
        local LEGACY
        LEGACY="$(legacy_home "$AGENT")"
        if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
            info "Legacy dir found at ${LEGACY} — symlinking legacy → profile"
            _safe_link "$CONF_FILE" "${LEGACY}/config.yaml" "$BK_DIR"
            _safe_link "$ENV_FILE" "${LEGACY}/.env" "$BK_DIR"
        fi
        log "Config lives in profile: ${HH}"
    fi

    # ── Git init ───────────────────────────────────────────────────────────
    if safe_prompt_yn "Initialize git repo?" "n"; then
        if [ ! -d "${HH}/.git" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${DIM}[dry-run]${NC} git init + .gitignore + initial commit in ${HH}"
            else
                run git -C "$HH" init -q
                cat > "${HH}/.gitignore" << 'EOF'
.secrets/
.env
.backups/
logs/
sessions/
*.log
*.bak
__pycache__/
*.pyc
EOF
                run git -C "$HH" add -A
                run git -C "$HH" commit -qm "init: ${AGENT} agent bootstrap"
            fi
            log "Git initialized"
        else
            warn "Git repo exists — skipping"
        fi
    fi

    # ── Service unit ───────────────────────────────────────────────────────
    header "Systemd Service (optional)"
    if safe_prompt_yn "Generate a systemd service unit?" "n"; then
        local svc_file="${HH}/${AGENT}-gateway.service"
        _generate_service_unit "$AGENT" "$HH" "$HH" "$svc_file"
        log "Service unit → ${svc_file}"
        echo ""
        info "To install:  sudo cp ${svc_file} /etc/systemd/system/"
        info "Then:        sudo systemctl daemon-reload && sudo systemctl enable --now ${AGENT}-gateway.service"
    fi

    # ── OpenClaw snippet ────────────────────────────────────────────────────
    _print_openclaw_snippet "$AGENT" "$HH" "$PLATFORM"

    # ── Summary ────────────────────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
    printf "${GREEN}${BOLD}║  Agent '%-20s' ready!%*s║${NC}\n" "$AGENT" $((26 - ${#AGENT})) ""
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ "$OPENCLAW_MODE" = true ]; then
        echo -e "  ${CYAN}Mode:${NC}         OpenClaw"
    else
        echo -e "  ${CYAN}Mode:${NC}         Hermes"
    fi
    echo -e "  ${CYAN}Directory:${NC}    ${HH}"
    echo -e "  ${CYAN}Config:${NC}       ${CONF_FILE}"
    echo -e "  ${CYAN}Env:${NC}          ${ENV_FILE}"
    echo -e "  ${CYAN}Provider:${NC}     ${PROVIDER_NAME} → ${MODEL_NAME}"
    [ "$HAS_FALLBACK" = true ] && echo -e "  ${CYAN}Fallback:${NC}     ${FALLBACK_NAME} → ${FALLBACK_MODEL}"
    [ "$PLATFORM" != "none" ] && echo -e "  ${CYAN}Platform:${NC}     ${PLATFORM}"

    if [ "$OPENCLAW_MODE" = true ]; then
        echo ""
        echo -e "  ${BOLD}HERMES_HOME for this agent:${NC}"
        echo -e "  ${HH}"
        echo ""
        echo -e "  ${BOLD}Systemd service should use:${NC}"
        echo -e "  Environment=HERMES_HOME=${HH}"
    elif [ -n "$AGENTS_ROOT" ]; then
        echo ""
        echo -e "  ${BOLD}Symlink map (AGENTS_ROOT mode):${NC}"
        echo -e "  ${HH}/config.yaml → ${CONF_FILE}"
        echo -e "  ${HH}/.env        → ${ENV_FILE}"
    else
        local LEGACY
        LEGACY="$(legacy_home "$AGENT")"
        if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
            echo ""
            echo -e "  ${BOLD}Symlink map (legacy bridge):${NC}"
            echo -e "  ${LEGACY}/config.yaml → ${CONF_FILE}"
            echo -e "  ${LEGACY}/.env        → ${ENV_FILE}"
        fi
    fi

    echo ""
    echo -e "  ${BOLD}Verify:${NC}"
    echo -e "  $0 scan"
    [ "$PLATFORM" != "none" ] && {
        echo ""
        echo -e "  ${BOLD}Start service:${NC}"
        echo -e "  sudo systemctl enable --now ${AGENT}-gateway.service"
    }
}

# =============================================================================
# Shared agent discovery — used by scan, sync, config, docker
# =============================================================================

_discover_agents() {
    declare -A _seen
    local _list=()

    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local n; n="$(basename "$d")"
            [ "$n" = "templates" ] && continue
            [ -z "${_seen[$n]:-}" ] && { _seen["$n"]=1; _list+=("$n"); }
        done
    fi
    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local n; n="$(basename "$d")"
            [ -z "${_seen[$n]:-}" ] && { _seen["$n"]=1; _list+=("$n"); }
        done
    fi
    if [ -n "$AGENTS_ROOT" ] && [ -d "$AGENTS_ROOT" ]; then
        for d in "$AGENTS_ROOT"/*/; do
            [ -d "$d" ] || continue
            local n; n="$(basename "$d")"
            [ "$n" = "templates" ] && continue
            [ -z "${_seen[$n]:-}" ] && { _seen["$n"]=1; _list+=("$n"); }
        done
    fi
    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local n; n="$(basename "$d")"
        n="${n#.hermes-}"
        [ "$n" = "gateway" ] && continue
        [ -z "${_seen[$n]:-}" ] && { _seen["$n"]=1; _list+=("$n"); }
    done
    if [ -d /etc/systemd/system ]; then
        for svc in /etc/systemd/system/*-gateway.service; do
            [ -f "$svc" ] || continue
            local n; n="$(basename "$svc" -gateway.service)"
            [ "$n" = "hermes" ] && continue
            [ "$n" = "openclaw" ] && continue
            [ -z "${_seen[$n]:-}" ] && { _seen["$n"]=1; _list+=("$n"); }
        done
    fi

    for name in "${_list[@]}"; do
        echo "${name}=$(resolve_home "$name")"
    done
}

# =============================================================================
# COMMAND: scan
# =============================================================================

cmd_scan() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║         Agent Configuration Scan v${VERSION}         ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local total=0 healthy=0 warnings=0 errors=0

    # Discover agents from multiple sources
    declare -A seen_agents
    local agent_list=()

    # From OpenClaw agents (if directory exists)
    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            seen_agents["$name"]=1
            agent_list+=("$name")
        done
    fi

    # From profiles (PRIMARY — the proper location)
    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    # From AGENTS_ROOT (optional workspace)
    if [ -n "$AGENTS_ROOT" ] && [ -d "$AGENTS_ROOT" ]; then
        for d in "$AGENTS_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    # From legacy HERMES_HOME pattern (~/.hermes-*)
    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        name="${name#.hermes-}"
        [ "$name" = "gateway" ] && continue
        if [ -z "${seen_agents[$name]:-}" ]; then
            seen_agents["$name"]=1
            agent_list+=("$name")
        fi
    done

    # From systemd services
    if [ -d /etc/systemd/system ]; then
        for svc in /etc/systemd/system/*-gateway.service; do
            [ -f "$svc" ] || continue
            local name
            name="$(basename "$svc" -gateway.service)"
            [ "$name" = "hermes" ] && continue
            [ "$name" = "openclaw" ] && continue
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    if [ ${#agent_list[@]} -eq 0 ]; then
        warn "No agents found. Run: $0 init <name>"
        return 0
    fi

    header "Discovered Agents (${#agent_list[@]})"
    for name in "${agent_list[@]}"; do
        echo "  • ${name}"
    done

    for agent in "${agent_list[@]}"; do
        total=$((total + 1))
        echo ""
        header "Scanning: ${agent}"

        local HH ENV_FILE CONF_FILE
        HH="$(resolve_home "$agent")"
        ENV_FILE="$(agent_env "$agent")"
        CONF_FILE="$(agent_config "$agent")"

        # Determine source
        local source_label="unknown"
        if [ -d "${OPENCLAW_AGENTS}/${agent}" ]; then
            source_label="openclaw"
        elif [ -d "$(profile_dir "$agent")" ]; then
            source_label="profile"
        elif [ -d "$(legacy_home "$agent")" ]; then
            source_label="legacy"
        fi

        info "Location: ${source_label} → ${HH}"

        local agent_ok=true
        local agent_warn=false

        # ── Profile/HERMES_HOME ────────────────────────────────────────
        if [ -d "$HH" ]; then
            log "HERMES_HOME exists: ${HH}"
        else
            err "HERMES_HOME MISSING: ${HH}"
            agent_ok=false
        fi

        # ── config.yaml ────────────────────────────────────────────────
        if [ -f "$CONF_FILE" ]; then
            log "config.yaml: ${CONF_FILE}"
            # Check symlink from HH if canonical is elsewhere
            if [ "$CONF_FILE" != "${HH}/config.yaml" ]; then
                if [ -L "${HH}/config.yaml" ]; then
                    local target
                    target="$(readlink "${HH}/config.yaml")"
                    if [ "$target" = "$CONF_FILE" ]; then
                        log "Symlink OK: ${HH}/config.yaml → ${target}"
                    else
                        warn "Symlink stale: ${HH}/config.yaml → ${target} (want ${CONF_FILE})"
                        agent_warn=true
                    fi
                elif [ -f "${HH}/config.yaml" ]; then
                    warn "Real file at ${HH}/config.yaml (not symlinked to canonical)"
                    agent_warn=true
                else
                    err "Missing link: ${HH}/config.yaml"
                    agent_ok=false
                fi
            else
                log "Config in profile directly (no symlink needed)"
            fi
            # Validate required fields
            if ! grep -q "^model:" "$CONF_FILE" 2>/dev/null; then
                warn "config.yaml missing 'model:' section"
                agent_warn=true
            fi
        else
            err "config.yaml MISSING: ${CONF_FILE}"
            agent_ok=false
            if [ -L "${HH}/config.yaml" ]; then
                err "  Broken symlink: $(readlink "${HH}/config.yaml" 2>/dev/null || echo '?')"
            fi
        fi

        # ── .env ───────────────────────────────────────────────────────
        if [ -f "$ENV_FILE" ]; then
            log ".env: ${ENV_FILE} ($(wc -l < "$ENV_FILE") lines)"
            # Check symlink from HH if canonical is elsewhere
            if [ "$ENV_FILE" != "${HH}/.env" ]; then
                if [ -L "${HH}/.env" ]; then
                    local target
                    target="$(readlink "${HH}/.env")"
                    if [ "$target" = "$ENV_FILE" ]; then
                        log "Symlink OK: ${HH}/.env → ${target}"
                    else
                        warn "Symlink stale: ${HH}/.env → ${target}"
                        agent_warn=true
                    fi
                elif [ -f "${HH}/.env" ]; then
                    warn "Real file at ${HH}/.env (not symlinked to canonical)"
                    agent_warn=true
                else
                    err "Missing link: ${HH}/.env"
                    agent_ok=false
                fi
            else
                log "Env in profile directly"
            fi
            # Check for bot token
            if grep -qE '^(TELEGRAM|DISCORD|SLACK).*BOT_TOKEN=.+' "$ENV_FILE" 2>/dev/null; then
                log "Bot token configured"
            else
                warn "No messaging platform token in .env"
                agent_warn=true
            fi
        else
            err ".env MISSING: ${ENV_FILE}"
            agent_ok=false
            if [ -L "${HH}/.env" ]; then
                err "  Broken symlink: $(readlink "${HH}/.env" 2>/dev/null || echo '?')"
            fi
        fi

        # ── Service status ─────────────────────────────────────────────
        local svc_name="${agent}-gateway.service"
        if systemctl list-unit-files "${svc_name}" &>/dev/null; then
            local svc_status
            svc_status="$(systemctl is-active "$svc_name" 2>/dev/null || echo "unknown")"
            case "$svc_status" in
                active) log "Service: ${svc_name} — active" ;;
                inactive) warn "Service: ${svc_name} — inactive"
                    agent_warn=true ;;
                failed) err "Service: ${svc_name} — FAILED"
                    agent_ok=false ;;
                *) warn "Service: ${svc_name} — ${svc_status}"
                    agent_warn=true ;;
            esac
        else
            info "No systemd service (${svc_name})"
        fi

        # ── Gateway state ──────────────────────────────────────────────
        if [ -f "${HH}/gateway_state.json" ]; then
            local gw_state
            gw_state=$(python3 -c "
import json
try:
    d = json.load(open('${HH}/gateway_state.json'))
    platforms = d.get('platforms', {})
    for p, s in platforms.items():
        print(f\"{p}:{s.get('state','unknown')}\")
except: pass
" 2>/dev/null)
            if [ -n "$gw_state" ]; then
                while IFS= read -r line; do
                    local p_name p_state
                    p_name="${line%%:*}"
                    p_state="${line#*:}"
                    if [ "$p_state" = "connected" ]; then
                        log "Platform ${p_name}: connected"
                    else
                        warn "Platform ${p_name}: ${p_state}"
                        agent_warn=true
                    fi
                done <<< "$gw_state"
            fi
        fi

        # ── Tally ──────────────────────────────────────────────────────
        if [ "$agent_ok" = true ] && [ "$agent_warn" = false ]; then
            healthy=$((healthy + 1))
        elif [ "$agent_ok" = false ]; then
            errors=$((errors + 1))
        else
            warnings=$((warnings + 1))
        fi
    done

    # ── Summary ────────────────────────────────────────────────────────────
    echo ""
    header "Scan Summary"
    echo -e "  Total agents:   ${total}"
    echo -e "  ${GREEN}Healthy:${NC}        ${healthy}"
    echo -e "  ${YELLOW}Warnings:${NC}       ${warnings}"
    echo -e "  ${RED}Errors:${NC}         ${errors}"
    echo ""

    if [ "$errors" -gt 0 ]; then
        if safe_prompt_yn "Run sync to attempt fixes?" "y"; then
            cmd_sync
        fi
    fi
}

# ==============================================================================
# COMMAND: sync
# ==============================================================================

cmd_sync() {
    header "Sync — Reconciling Agents"

    # Dry-run first to show what will happen
    if [ "$DRY_RUN" = false ]; then
        info "This will create missing profiles, stubs, and fix symlinks."
        info "Run with --dry-run first to preview."
        echo ""
        safe_prompt_yn "Proceed with sync?" "n" || { info "Aborted."; return 0; }
    fi

    local fixed=0 created=0 skipped=0

    # Discover agents (same as scan)
    declare -A seen_agents
    local agent_list=()

    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            seen_agents["$name"]=1
            agent_list+=("$name")
        done
    fi

    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    if [ -n "$AGENTS_ROOT" ] && [ -d "$AGENTS_ROOT" ]; then
        for d in "$AGENTS_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        name="${name#.hermes-}"
        [ "$name" = "gateway" ] && continue
        if [ -z "${seen_agents[$name]:-}" ]; then
            seen_agents["$name"]=1
            agent_list+=("$name")
        fi
    done

    local fixed=0 created=0 skipped=0

    for agent in "${agent_list[@]}"; do
        _sync_one_agent "$agent" || { warn "Failed: ${agent}, continuing..."; continue; }
    done

    echo ""
    log "Sync complete: ${#agent_list[@]} agents processed, ${created} created, ${fixed} fixed"

    # Offer Docker generation
    echo ""
    if [ "$NO_CONFIRM" = true ] || safe_prompt_yn "Generate Docker containers for ${#agent_list[@]} agents?" "n"; then
        cmd_docker "${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}/docker"
    else
        info "Skipped Docker generation. Run '$0 docker' later."
    fi
}

_sync_one_agent() {
    local agent="$1"
        local HH ENV_FILE CONF_FILE BK_DIR
        HH="$(resolve_home "$agent")"
        ENV_FILE="$(agent_env "$agent")"
        CONF_FILE="$(agent_config "$agent")"
        BK_DIR="$(agent_backup_dir "$agent")"

        info "Syncing: ${agent}"

        # Create profile dir if missing (NEVER destroy existing)
        if [ ! -d "$HH" ]; then
            run mkdir -p "$HH"/{sessions,projects,skills,tools,docs,logs,.secrets,.backups}
            for f in SOUL.md USER.md MEMORY.md TOOLS.md README.md; do
                [ -f "${HH}/${f}" ] || touch "${HH}/${f}"
            done
            log "Created profile: ${HH}"
            created=$((created + 1))
        else
            # Backup existing dir before adding stubs
            if [ "$DRY_RUN" = false ]; then
                local sync_backup
                sync_backup="/tmp/hermes-backup-${agent}-sync-$(timestamp)"
                backup_file "$HH" "$sync_backup"
            fi
            # Ensure subdirs exist without touching existing content
            for sub in sessions projects skills tools docs logs .secrets .backups; do
                [ -d "${HH}/${sub}" ] || run mkdir -p "${HH}/${sub}"
            done
            for f in SOUL.md USER.md MEMORY.md TOOLS.md README.md; do
                [ -f "${HH}/${f}" ] || run touch "${HH}/${f}"
            done
            info "Profile exists — ensured subdirs present: ${HH}"
        fi

        # In OpenClaw mode: copy identity files from ~/.hermes/profiles/
        if [ "$OPENCLAW_MODE" = true ]; then
            local profile_src="${PROFILES_ROOT}/${agent}"
            if [ -d "$profile_src" ]; then
                local copied=0
                for f in SOUL.md USER.md MEMORY.md TOOLS.md AGENTS.md HEARTBEAT.md IDENTITY.md README.md; do
                    if [ -f "${profile_src}/${f}" ] && [ ! -f "${HH}/${f}" ]; then
                        if [ "$DRY_RUN" = true ]; then
                            echo -e "  ${DIM}[dry-run]${NC} Copy ${f} from profiles → OpenClaw"
                        else
                            run cp "${profile_src}/${f}" "${HH}/${f}"
                        fi
                        log "Copied ${f} from profiles"
                        copied=$((copied + 1))
                    elif [ -f "${profile_src}/${f}" ] && [ -f "${HH}/${f}" ]; then
                        if ! diff -q "${profile_src}/${f}" "${HH}/${f}" &>/dev/null; then
                            warn "${f} differs: profiles vs OpenClaw (OpenClaw kept)"
                        fi
                    fi
                done
                [ "$copied" -gt 0 ] && log "Copied ${copied} identity file(s) from profiles"
            fi
        fi

        # Create .env if missing or incomplete
        local env_has_token=false
        if [ -f "$ENV_FILE" ]; then
            grep -qE '^TELEGRAM_BOT_TOKEN=.+' "$ENV_FILE" 2>/dev/null && env_has_token=true
        fi

        if [ ! -f "$ENV_FILE" ] || [ ! -s "$ENV_FILE" ] || [ "$env_has_token" = false ]; then
            if [ "$env_has_token" = true ]; then
                info "Preserving existing .env: ${ENV_FILE}"
            elif [ "$DRY_RUN" = true ]; then
                echo -e "  ${DIM}[dry-run]${NC} Create .env: ${ENV_FILE}"
            else
                # Check for existing bot token in legacy .env or gateway .env
                local existing_token=""
                for env_src in \
                    "${HOME_DIR}/.hermes-${agent}/.env" \
                    "${HOME_DIR}/.hermes.gateway/.env" \
                    "${HERMES_ROOT}/.env"; do
                    if [ -f "$env_src" ]; then
                        existing_token=$(grep -E '^TELEGRAM_BOT_TOKEN=.+' "$env_src" 2>/dev/null | head -1 | cut -d= -f2-) || true
                        [ -n "$existing_token" ] && break
                    fi
                done

                run mkdir -p "$(dirname "$ENV_FILE")"
                {
                    cat << ENVEOF
# ============================================================
# Agent: ${agent}
# Generated: $(timestamp)
# Managed by agent-bootstrap.sh
# ============================================================
#
# REQUIRED: At least one provider key and TELEGRAM_BOT_TOKEN
# The agent will not connect without these.
#
# To add your keys, uncomment and fill in the lines below.
# Run ./agent-bootstrap.sh config to generate openclaw.json entries.
#

# ── Telegram (REQUIRED for messaging) ────────────────────────────
#
# Get your token from @BotFather on Telegram.
# Format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz
#
ENVEOF

                    if [ -n "$existing_token" ]; then
                        echo "TELEGRAM_BOT_TOKEN=${existing_token}"
                    else
                        echo "# TELEGRAM_BOT_TOKEN=<your-bot-token-from-botfather>"
                    fi

                    cat << ENVEOF

# Who can message this bot (your Telegram user ID)
TELEGRAM_ALLOWED_USERS=6537959619

# Default chat for proactive messages
TELEGRAM_HOME_CHANNEL=6537959619

# Reply threading mode: off, first, all
# TELEGRAM_REPLY_TO_MODE=off

# ── Model Provider (REQUIRED — uncomment ONE primary) ────────────
#
# Pick the provider you have an API key for.
# Uncomment exactly ONE block below.
#

# --- Nous Portal (free tier available) ---
# NOUS_API_KEY=<your-nous-key>
# Model: xiaomi/mimo-v2-pro
# URL: https://inference-api.nousresearch.com/v1

# --- OpenRouter (access to 200+ models) ---
# OPENROUTER_API_KEY=<your-openrouter-key>
# Model: any model on openrouter.ai
# URL: https://openrouter.ai/api/v1

# --- OpenAI ---
# OPENAI_API_KEY=sk-<your-key>
# Model: gpt-4o, gpt-4o-mini
# URL: https://api.openai.com/v1

# --- Anthropic ---
# ANTHROPIC_API_KEY=sk-ant-<your-key>
# Model: claude-sonnet-4-20250514
# URL: https://api.anthropic.com/v1

# --- Mistral ---
# MISTRAL_API_KEY=<your-key>
# Model: mistral-large-latest
# URL: https://api.mistral.ai/v1

# --- Local Ollama (no API key needed) ---
# OLLAMA_API_KEY=ollama
# Model: qwen2.5:7b (or any model you have pulled)
# URL: http://localhost:11434/v1

# ── Terminal ──────────────────────────────────────────────────────
#
# SUDO_PASSWORD=<if-needed-for-sudo>
# TERMINAL_ENV=production
# HERMES_MAX_ITERATIONS=90

# ── SSH (if using SSH terminal backend) ──────────────────────────
#
# TERMINAL_SSH_HOST=<host>
# TERMINAL_SSH_USER=<user>
# TERMINAL_SSH_KEY=<path-to-key>

# ── Optional: Web Search ─────────────────────────────────────────
#
# PARALLEL_API_KEY=<key>
# FIRECRAWL_API_KEY=<key>

# ── Optional: Browser ────────────────────────────────────────────
#
# BROWSERBASE_API_KEY=<key>
# BROWSERBASE_PROJECT_ID=<id>

# ── Optional: TTS / Voice ────────────────────────────────────────
#
# ELEVENLABS_API_KEY=<key>

# ── Optional: Honcho ─────────────────────────────────────────────
#
# HONCHO_API_KEY=<key>
# HONCHO_APP_ID=<id>

# ── Optional: Farcaster / Neynar ─────────────────────────────────
#
# NEYNAR_API_KEY=<key>

# ── Optional: Other services ─────────────────────────────────────
#
# GITHUB_TOKEN=<token>
# NOTION_API_KEY=<key>
# LINEAR_API_KEY=<key>
ENVEOF
                } > "$ENV_FILE"
                run chmod 600 "$ENV_FILE"
                if [ -n "$existing_token" ]; then
                    log "Created .env with imported bot token: ${ENV_FILE}"
                else
                    warn "Created .env — UNCOMMENT a provider key and set TELEGRAM_BOT_TOKEN: ${ENV_FILE}"
                fi
                created=$((created + 1))
            fi
        fi

        # Create config.yaml if missing or incomplete
        local conf_has_model=false
        if [ -f "$CONF_FILE" ]; then
            grep -q "^model:" "$CONF_FILE" 2>/dev/null && conf_has_model=true
        fi

        if [ ! -f "$CONF_FILE" ] || [ ! -s "$CONF_FILE" ] || [ "$conf_has_model" = false ]; then
            if [ "$conf_has_model" = true ]; then
                info "Preserving existing config: ${CONF_FILE}"
            elif [ "$DRY_RUN" = true ]; then
                echo -e "  ${DIM}[dry-run]${NC} Create config.yaml: ${CONF_FILE}"
            else
                run mkdir -p "$(dirname "$CONF_FILE")"
                {
                    cat << CONFEOF
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

# ── Provider Fallback Chain ─────────────────────────────────────────
# Add fallback providers to prevent downtime if primary is unavailable.
# Supported: openrouter, openai, anthropic, mistral, nous, ollama
# fallback_providers:
#   - provider: openrouter
#     model: google/gemma-3-27b-it
#   - provider: mistral
#     model: mistral-small-latest
CONFEOF
                } > "$CONF_FILE"
                log "Created config.yaml: ${CONF_FILE}"
                created=$((created + 1))
            fi
        fi

        # Fix symlinks (skip in OpenClaw mode — files live directly in agent dir)
        run mkdir -p "$BK_DIR"
        if [ "$OPENCLAW_MODE" != true ]; then
            _safe_link "$CONF_FILE" "${HH}/config.yaml" "$BK_DIR"
            _safe_link "$ENV_FILE" "${HH}/.env" "$BK_DIR"
        fi
        fixed=$((fixed + 1))
    return 0
}

# ==============================================================================
# COMMAND: link / unlink
# ==============================================================================

cmd_link() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 link <agent-name>"

    local HH ENV_FILE CONF_FILE BK_DIR
    HH="$(resolve_home "$agent")"
    ENV_FILE="$(agent_env "$agent")"
    CONF_FILE="$(agent_config "$agent")"
    BK_DIR="$(agent_backup_dir "$agent")"

    [ -d "$HH" ] || die "Profile not found: ${HH}"
    [ -f "$CONF_FILE" ] || die "config.yaml not found: ${CONF_FILE}"

    if [ "$DRY_RUN" = false ]; then
        info "This will create symlinks in HERMES_HOME pointing to profile config."
        echo ""
        safe_prompt_yn "Proceed with link?" "n" || { info "Aborted."; return 0; }
    fi

    run mkdir -p "$BK_DIR"

    header "Linking: ${agent}"

    # If config lives in the profile directly, no symlink needed
    if [ "$CONF_FILE" = "${HH}/config.yaml" ]; then
        log "Config is in profile — no symlink needed"
    else
        _safe_link "$CONF_FILE" "${HH}/config.yaml" "$BK_DIR"
    fi

    if [ "$ENV_FILE" = "${HH}/.env" ]; then
        log "Env is in profile — no symlink needed"
    else
        _safe_link "$ENV_FILE" "${HH}/.env" "$BK_DIR"
    fi

    # Also link to legacy location if it exists
    local LEGACY
    LEGACY="$(legacy_home "$agent")"
    if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
        info "Legacy dir found — linking legacy → profile"
        _safe_link "$CONF_FILE" "${LEGACY}/config.yaml" "$BK_DIR"
        _safe_link "$ENV_FILE" "${LEGACY}/.env" "$BK_DIR"
    fi

    log "Done"
}

cmd_unlink() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 unlink <agent-name>"

    local HH BK_DIR
    HH="$(resolve_home "$agent")"
    BK_DIR="$(agent_backup_dir "$agent")"

    if [ "$DRY_RUN" = false ]; then
        info "This will remove symlinks for '${agent}' (files remain untouched)."
        echo ""
        safe_prompt_yn "Proceed with unlink?" "n" || { info "Aborted."; return 0; }
    fi

    header "Unlinking: ${agent}"
    run mkdir -p "$BK_DIR"

    # Check profile
    for link in "${HH}/config.yaml" "${HH}/.env"; do
        if [ -L "$link" ]; then
            backup_file "$link" "$BK_DIR"
            run rm -f "$link"
            log "Removed symlink: ${link}"
        elif [ -e "$link" ]; then
            warn "${link} is a real file (not a symlink) — use 'repair' to migrate"
        else
            info "${link} doesn't exist"
        fi
    done

    # Check legacy
    local LEGACY
    LEGACY="$(legacy_home "$agent")"
    if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
        for link in "${LEGACY}/config.yaml" "${LEGACY}/.env"; do
            if [ -L "$link" ]; then
                backup_file "$link" "$BK_DIR"
                run rm -f "$link"
                log "Removed legacy symlink: ${link}"
            fi
        done
    fi
}

# ==============================================================================
# COMMAND: repair
# ==============================================================================

cmd_repair() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 repair <agent-name>"

    header "Repair: ${agent}"

    local HH ENV_FILE CONF_FILE BK_DIR
    HH="$(resolve_home "$agent")"
    ENV_FILE="$(agent_env "$agent")"
    CONF_FILE="$(agent_config "$agent")"
    BK_DIR="$(agent_backup_dir "$agent")"

    if [ "$DRY_RUN" = false ]; then
        info "This will migrate files, create stubs, and fix symlinks for '${agent}'."
        info "Run with --dry-run first to preview."
        echo ""
        safe_prompt_yn "Proceed with repair?" "n" || { info "Aborted."; return 0; }
    fi

    run mkdir -p "$HH" "$BK_DIR"

    # Check for files in legacy location that should be in profile
    local LEGACY
    LEGACY="$(legacy_home "$agent")"
    if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
        info "Checking legacy dir: ${LEGACY}"

        # Full backup of legacy dir before migration
        if [ "$DRY_RUN" = false ]; then
            local legacy_backup
            legacy_backup="/tmp/hermes-backup-${agent}-legacy-$(timestamp)"
            backup_file "$LEGACY" "$legacy_backup"
        fi

        if [ -f "${LEGACY}/config.yaml" ] && [ ! -L "${LEGACY}/config.yaml" ]; then
            if [ ! -f "$CONF_FILE" ]; then
                run mv "${LEGACY}/config.yaml" "$CONF_FILE"
                log "Migrated config.yaml: legacy → profile"
            else
                backup_file "${LEGACY}/config.yaml" "$BK_DIR"
                warn "Both exist — legacy backed up, keeping profile version"
            fi
        fi

        if [ -f "${LEGACY}/.env" ] && [ ! -L "${LEGACY}/.env" ]; then
            if [ ! -f "$ENV_FILE" ]; then
                run mv "${LEGACY}/.env" "$ENV_FILE"
                run chmod 600 "$ENV_FILE"
                log "Migrated .env: legacy → profile"
            else
                backup_file "${LEGACY}/.env" "$BK_DIR"
                warn "Both exist — legacy backed up, keeping profile version"
            fi
        fi
    fi

    # If config.yaml exists in HERMES_HOME as regular file but canonical is elsewhere
    if [ "$CONF_FILE" != "${HH}/config.yaml" ]; then
        if [ -f "${HH}/config.yaml" ] && [ ! -L "${HH}/config.yaml" ]; then
            if [ ! -f "$CONF_FILE" ]; then
                run mv "${HH}/config.yaml" "$CONF_FILE"
                log "Moved config.yaml to canonical location"
            else
                backup_file "${HH}/config.yaml" "$BK_DIR"
            fi
        fi
    fi

    # Same for .env
    if [ "$ENV_FILE" != "${HH}/.env" ]; then
        if [ -f "${HH}/.env" ] && [ ! -L "${HH}/.env" ]; then
            if [ ! -f "$ENV_FILE" ]; then
                run mv "${HH}/.env" "$ENV_FILE"
                run chmod 600 "$ENV_FILE"
                log "Moved .env to canonical location"
            else
                backup_file "${HH}/.env" "$BK_DIR"
            fi
        fi
    fi

    # Recreate stubs if missing (NEVER overwrite non-empty existing files)
    if [ ! -f "$CONF_FILE" ] || [ ! -s "$CONF_FILE" ]; then
        if [ -f "$CONF_FILE" ] && [ -s "$CONF_FILE" ]; then
            info "Preserving existing config: ${CONF_FILE}"
        elif [ "$DRY_RUN" = true ]; then
            echo -e "  ${DIM}[dry-run]${NC} Create empty config.yaml: ${CONF_FILE}"
        else
            run mkdir -p "$(dirname "$CONF_FILE")"
            echo "# Agent: ${agent}" > "$CONF_FILE"
            log "Created empty config.yaml"
        fi
    fi
    if [ ! -f "$ENV_FILE" ] || [ ! -s "$ENV_FILE" ]; then
        if [ -f "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
            info "Preserving existing .env: ${ENV_FILE}"
        elif [ "$DRY_RUN" = true ]; then
            echo -e "  ${DIM}[dry-run]${NC} Create empty .env: ${ENV_FILE}"
        else
            run mkdir -p "$(dirname "$ENV_FILE")"
            echo "# Agent: ${agent}" > "$ENV_FILE"
            run chmod 600 "$ENV_FILE"
            log "Created empty .env"
        fi
    fi

    # Fix symlinks if canonical is outside the profile
    if [ "$CONF_FILE" != "${HH}/config.yaml" ]; then
        _safe_link "$CONF_FILE" "${HH}/config.yaml" "$BK_DIR"
    fi
    if [ "$ENV_FILE" != "${HH}/.env" ]; then
        _safe_link "$ENV_FILE" "${HH}/.env" "$BK_DIR"
    fi

    # Link legacy if it exists
    if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
        _safe_link "$CONF_FILE" "${LEGACY}/config.yaml" "$BK_DIR"
        _safe_link "$ENV_FILE" "${LEGACY}/.env" "$BK_DIR"
    fi

    log "Repair complete for ${agent}"
}

# ==============================================================================
# COMMAND: list
# ==============================================================================

cmd_list() {
    header "Registered Agents"

    declare -A seen_agents
    local agent_list=()

    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            seen_agents["$name"]=1
            agent_list+=("$name")
        done
    fi

    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    if [ -n "$AGENTS_ROOT" ] && [ -d "$AGENTS_ROOT" ]; then
        for d in "$AGENTS_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi

    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        name="${name#.hermes-}"
        [ "$name" = "gateway" ] && continue
        if [ -z "${seen_agents[$name]:-}" ]; then
            seen_agents["$name"]=1
            agent_list+=("$name")
        fi
    done

    if [ ${#agent_list[@]} -eq 0 ]; then
        warn "No agents found"
        return 0
    fi

    printf "\n  ${BOLD}%-16s %-10s %-36s %-10s %-10s${NC}\n" "AGENT" "TYPE" "LOCATION" "CONFIG" "SERVICE"
    printf "  %-16s %-10s %-36s %-10s %-10s\n" "────────────────" "──────────" "────────────────────────────────────" "──────────" "──────────"

    for agent in "${agent_list[@]}"; do
        local HH CONF_FILE
        HH="$(resolve_home "$agent")"
        CONF_FILE="$(agent_config "$agent")"

        local loc_type dir_status config_status svc_status

        # Determine type
        if [ -d "${OPENCLAW_AGENTS}/${agent}" ]; then
            loc_type="openclaw"
        elif [ -d "$(profile_dir "$agent")" ]; then
            loc_type="profile"
        elif [ -d "$(legacy_home "$agent")" ]; then
            loc_type="legacy"
        else
            loc_type="?"
        fi

        [ -d "$HH" ] && dir_status="${GREEN}✓${NC}" || dir_status="${RED}✗${NC}"

        if [ -f "$CONF_FILE" ]; then
            if [ "$CONF_FILE" = "${HH}/config.yaml" ]; then
                config_status="${GREEN}direct${NC}"
            elif [ -L "${HH}/config.yaml" ] && [ "$(readlink "${HH}/config.yaml")" = "$CONF_FILE" ]; then
                config_status="${GREEN}linked${NC}"
            else
                config_status="${YELLOW}drift${NC}"
            fi
        else
            config_status="${RED}missing${NC}"
        fi

        local svc_name="${agent}-gateway.service"
        if systemctl list-unit-files "${svc_name}" &>/dev/null 2>&1; then
            svc_status="$(systemctl is-active "$svc_name" 2>/dev/null || echo "?")"
            case "$svc_status" in
                active) svc_status="${GREEN}active${NC}" ;;
                inactive) svc_status="${YELLOW}inactive${NC}" ;;
                failed) svc_status="${RED}failed${NC}" ;;
            esac
        else
            svc_status="${DIM}none${NC}"
        fi

        printf "  %-16s %-10s %-36s %-20b %-20b\n" "$agent" "$loc_type" "$HH" "$config_status" "$svc_status"
    done
    echo ""
}

# ==============================================================================
# COMMAND: config — generate openclaw.json entries

# ==============================================================================
# COMMAND: configure — interactive setup for existing agent
# ==============================================================================

cmd_configure() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 configure <agent-name>"

    local HH ENV_FILE CONF_FILE BK_DIR
    HH="$(resolve_home "$agent")"
    ENV_FILE="$(agent_env "$agent")"
    CONF_FILE="$(agent_config "$agent")"
    BK_DIR="$(agent_backup_dir "$agent")"

    [ -d "$HH" ] || die "Agent not found: ${HH}"
    echo -e "${BOLD}${BLUE}── Configure: ${agent} ──${NC}"
    echo ""

    # ── Bot Token ─────────────────────────────────────────────────────
    echo -e "${BOLD}1. Telegram Bot Token${NC}"
    local current_token=""
    if [ -f "$ENV_FILE" ]; then
        current_token=$(grep -E '^TELEGRAM_BOT_TOKEN=.+' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-) || true
    fi

    if [ -n "$current_token" ]; then
        echo -e "   Current: ${current_token:0:10}...${current_token: -4} (${#current_token} chars)"
        if safe_prompt_yn "   Change?" "n"; then
            local new_token
            new_token=$(prompt_secret "   New bot token")
            if [ -n "$new_token" ]; then
                backup_file "$ENV_FILE" "$BK_DIR"
                if [ "$DRY_RUN" = false ]; then
                    safe_env_set "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$new_token"
                    log "Updated bot token"
                else
                    echo -e "  ${DIM}[dry-run]${NC} Update TELEGRAM_BOT_TOKEN"
                fi
            fi
        fi
    else
        echo -e "   ${RED}Not set${NC}"
        if [ -t 0 ]; then
            local new_token
            new_token=$(prompt_secret "   Bot token from @BotFather")
            if [ -n "$new_token" ]; then
                backup_file "$ENV_FILE" "$BK_DIR"
                if [ "$DRY_RUN" = false ]; then
                    safe_env_set "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$new_token"
                    log "Set bot token"
                else
                    echo -e "  ${DIM}[dry-run]${NC} Set TELEGRAM_BOT_TOKEN"
                fi
            fi
        else
            warn "Run interactively to set bot token: $0 configure ${agent}"
        fi
    fi

    # ── Provider ──────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}2. Model Provider${NC}"

    local current_provider=""
    if [ -f "$CONF_FILE" ]; then
        current_provider=$(grep "^  provider:" "$CONF_FILE" 2>/dev/null | head -1 | awk '{print $2}') || true
    fi

    if [ -n "$current_provider" ] && [ "$current_provider" != "''" ]; then
        local current_model=""
        current_model=$(grep "^  default:" "$CONF_FILE" 2>/dev/null | head -1 | awk '{print $2}') || true
        echo -e "   Current: ${current_provider} / ${current_model}"
        if ! safe_prompt_yn "   Change?" "n"; then
            echo -e "   ${GREEN}Keeping current provider${NC}"
        else
            _configure_provider "$agent" "$ENV_FILE" "$CONF_FILE" "$BK_DIR"
        fi
    else
        echo -e "   ${RED}Not configured${NC}"
        if [ -t 0 ]; then
            _configure_provider "$agent" "$ENV_FILE" "$CONF_FILE" "$BK_DIR"
        else
            warn "Run interactively to set provider: $0 configure ${agent}"
            echo "   Or edit manually:"
            echo "   nano ${CONF_FILE}   # set model.default, model.provider, model.base_url"
            echo "   nano ${ENV_FILE}    # uncomment the matching API key"
        fi
    fi

    # ── Summary ───────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}3. Current Config${NC}"
    if [ -f "$ENV_FILE" ]; then
        local has_token has_key
        has_token=$(grep -cE '^TELEGRAM_BOT_TOKEN=.+' "$ENV_FILE" 2>/dev/null)
        has_key=$(grep -cE '^[A-Z_]*API_KEY=.+' "$ENV_FILE" 2>/dev/null)
        echo -e "   .env:     $([ "${has_token:-0}" -gt 0 ] && echo "${GREEN}✓${NC} bot token" || echo "${RED}✗${NC} no bot token")"
        echo -e "   .env:     $([ "${has_key:-0}" -gt 0 ] && echo "${GREEN}✓${NC} provider key" || echo "${RED}✗${NC} no provider key")"
    fi
    if [ -f "$CONF_FILE" ]; then
        local has_model
        has_model=$(grep -c "^model:" "$CONF_FILE" 2>/dev/null)
        echo -e "   config:   $([ "${has_model:-0}" -gt 0 ] && echo "${GREEN}✓${NC} model configured" || echo "${RED}✗${NC} no model")"
    fi
    echo ""
    echo -e "   ${BOLD}Files:${NC}"
    echo -e "   ${ENV_FILE}"
    echo -e "   ${CONF_FILE}"
    echo ""
    echo -e "   ${BOLD}Next:${NC}"
    echo -e "   $0 config                    # generate openclaw.json entries"
    echo -e "   sudo systemctl restart openclaw-gateway.service"

    # Offer Docker update
    echo ""
    if safe_prompt_yn "Update Docker containers?" "n"; then
        cmd_docker "${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}/docker" 2>/dev/null || true
    fi
}

_configure_provider() {
    local agent="$1" ENV_FILE="$2" CONF_FILE="$3" BK_DIR="$4"

    echo ""
    echo "   Provider options:"
    echo "   1) Nous Portal (free tier, xiaomi/mimo-v2-pro)"
    echo "   2) OpenRouter (200+ models)"
    echo "   3) OpenAI (gpt-4o)"
    echo "   4) Anthropic (claude-sonnet-4)"
    echo "   5) Mistral (mistral-large-latest)"
    echo "   6) Local Ollama (no API key)"
    echo ""

    local choice
    choice=$(prompt "   Select (1-6)" "1")

    local provider model url key_var key_prompt
    case "$choice" in
        1) provider="nous"; model="xiaomi/mimo-v2-pro"; url="https://inference-api.nousresearch.com/v1"; key_var="NOUS_API_KEY"; key_prompt="Nous API key" ;;
        2) provider="openrouter"; model="meta-llama/llama-3.1-70b-instruct"; url="https://openrouter.ai/api/v1"; key_var="OPENROUTER_API_KEY"; key_prompt="OpenRouter API key" ;;
        3) provider="openai"; model="gpt-4o"; url="https://api.openai.com/v1"; key_var="OPENAI_API_KEY"; key_prompt="OpenAI API key (sk-...)" ;;
        4) provider="anthropic"; model="claude-sonnet-4-20250514"; url="https://api.anthropic.com/v1"; key_var="ANTHROPIC_API_KEY"; key_prompt="Anthropic API key (sk-ant-...)" ;;
        5) provider="mistral"; model="mistral-large-latest"; url="https://api.mistral.ai/v1"; key_var="MISTRAL_API_KEY"; key_prompt="Mistral API key" ;;
        6) provider="ollama"; model=$(prompt "   Model name" "qwen2.5:7b"); url="http://localhost:11434/v1"; key_var=""; key_prompt="" ;;
        *) warn "Invalid choice"; return ;;
    esac

    echo ""
    echo -e "   Selected: ${provider} / ${model}"

    # Update config.yaml (awk — safe for all special chars)
    backup_file "$CONF_FILE" "$BK_DIR"
    if [ "$DRY_RUN" = false ]; then
        awk -v model="$model" -v provider="$provider" -v url="$url" '
            /^  default:/   { print "  default: " model; next }
            /^  provider:/  { print "  provider: " provider; next }
            /^  base_url:/  { print "  base_url: " url; next }
            { print }
        ' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv "${CONF_FILE}.tmp" "$CONF_FILE"
        log "Updated config.yaml: ${provider}/${model}"
    else
        echo -e "  ${DIM}[dry-run]${NC} Update config.yaml: ${provider}/${model}"
    fi

    # Update .env with key
    if [ -n "$key_var" ] && [ -t 0 ]; then
        local api_key
        api_key=$(prompt_secret "   ${key_prompt}")
        if [ -n "$api_key" ]; then
            backup_file "$ENV_FILE" "$BK_DIR"
            if [ "$DRY_RUN" = false ]; then
                # Comment out active key (awk — safe for all chars), then set
                awk -v kv="$key_var" '
                    $0 == kv "=" || substr($0,1,length(kv)+1) == kv "=" {
                        print "# " $0; next
                    }
                    { print }
                ' "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
                safe_env_set "$ENV_FILE" "$key_var" "$api_key"
                log "Set ${key_var} in .env"
            else
                echo -e "  ${DIM}[dry-run]${NC} Set ${key_var}"
            fi
        fi
    fi
}

# ==============================================================================

cmd_config() {
    header "OpenClaw Config Generator"

    # Discover agents
    declare -A seen_agents
    local agent_list=()

    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            seen_agents["$name"]=1
            agent_list+=("$name")
        done
    fi
    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            if [ -z "${seen_agents[$name]:-}" ]; then
                seen_agents["$name"]=1
                agent_list+=("$name")
            fi
        done
    fi
    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        name="${name#.hermes-}"
        [ "$name" = "gateway" ] && continue
        if [ -z "${seen_agents[$name]:-}" ]; then
            seen_agents["$name"]=1
            agent_list+=("$name")
        fi
    done

    if [ ${#agent_list[@]} -eq 0 ]; then
        warn "No agents found. Run init or sync first."
        return 1
    fi

    info "Found ${#agent_list[@]} agent(s): ${agent_list[*]}"
    echo ""

    # Collect bot tokens from .env files
    declare -A bot_tokens
    local tokens_found=0
    for agent in "${agent_list[@]}"; do
        local env_file
        env_file="$(agent_env "$agent")"
        local token=""
        if [ -f "$env_file" ]; then
            token=$(grep -E '^TELEGRAM_BOT_TOKEN=.+' "$env_file" 2>/dev/null | head -1 | cut -d= -f2-) || true
        fi
        if [ -n "$token" ]; then
            bot_tokens["$agent"]="$token"
            log "${agent}: token found"
            tokens_found=$((tokens_found + 1))
        else
            info "${agent}: no token — using placeholder"
            if [ "$DRY_RUN" = false ] && [ -t 0 ]; then
                local input
                read -rsp "$(echo -e "${CYAN}?${NC} Bot token for ${agent} (enter to skip): ")" input
                echo
                [ -n "$input" ] && bot_tokens["$agent"]="$input"
            fi
        fi
    done

    if [ "$tokens_found" -eq 0 ] && [ ! -t 0 ]; then
        info "No tokens found. Using placeholders. Run interactively to enter tokens."
    fi

    # Generate output file
    local outfile="${OPENCLAW_ROOT}/agents.json"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Write ${outfile}"
    else
        backup_file "$outfile" "${OPENCLAW_ROOT}/.backups"
    fi

    # Build the JSON
    local json_buf=""
    json_buf+='{'
    json_buf+='"agents":{"defaults":{"workspace":"~/.openclaw/workspace"},"list":['
    local first=true
    for agent in "${agent_list[@]}"; do
        [ "$first" = true ] && first=false || json_buf+=","
        json_buf+="$(printf '{"id":"%s"}' "$agent")"
    done
    json_buf+=']},'
    json_buf+='"channels":{"telegram":{"accounts":{'
    first=true
    for agent in "${agent_list[@]}"; do
        local token="${bot_tokens[$agent]:-YOUR_${agent^^}_BOT_TOKEN}"
        [ "$first" = true ] && first=false || json_buf+=","
        json_buf+="$(printf '"%s":{"botToken":"%s","dmPolicy":"pairing"}' "$agent" "$token")"
    done
    json_buf+='}}},'
    json_buf+='"bindings":['
    first=true
    for agent in "${agent_list[@]}"; do
        [ "$first" = true ] && first=false || json_buf+=","
        json_buf+="$(printf '{"agentId":"%s","match":{"channel":"telegram","accountId":"%s"}}' "$agent" "$agent")"
    done
    json_buf+=']}'

    # Pretty-print if jq available, otherwise raw
    local formatted
    if command -v jq &>/dev/null; then
        formatted=$(echo "$json_buf" | jq . 2>/dev/null || echo "$json_buf")
    else
        formatted="$json_buf"
    fi

    # Write to file
    local outfile="${OPENCLAW_ROOT}/agents-config-generated.json"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Write ${outfile}"
    else
        run mkdir -p "$(dirname "$outfile")"
        echo "$formatted" > "$outfile"
        log "Wrote ${outfile}"
    fi

    # Also print to stdout
    header "Generated Config"
    echo ""
    echo "$formatted"
    echo ""
    echo -e "${DIM}File: ${outfile}${NC}"
    echo -e "${DIM}Merge into ~/.openclaw/openclaw.json as needed.${NC}"
}

# ==============================================================================
# COMMAND: delete
# ==============================================================================

cmd_delete() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 delete <agent-name>"

    local HH LEGACY
    HH="$(resolve_home "$agent")"
    LEGACY="$(legacy_home "$agent")"

    warn "This will remove agent '${agent}'"
    echo "  Profile:   ${HH}"
    [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ] && echo "  Legacy:    ${LEGACY}"
    echo ""

    # Always back up first — no exceptions
    local BK_DIR="/tmp/agent-backup-${agent}-$(timestamp)"
    run mkdir -p "$BK_DIR"
    [ -d "$HH" ] && cp -a "$HH" "${BK_DIR}/profile" && log "Backed up profile → ${BK_DIR}/profile"
    [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ] && cp -a "$LEGACY" "${BK_DIR}/legacy" && log "Backed up legacy → ${BK_DIR}/legacy"

    # Check for non-config files that would be destroyed
    local user_files=()
    if [ -d "$HH" ]; then
        while IFS= read -r -d '' f; do
            local rel="${f#${HH}/}"
            case "$rel" in
                config.yaml|.env|.secrets/*|.backups/*) ;; # expected — skip
                *) user_files+=("$rel") ;;
            esac
        done < <(find "$HH" -type f -print0 2>/dev/null)
    fi

    if [ ${#user_files[@]} -gt 0 ]; then
        warn "Profile contains ${#user_files[@]} user files that will be deleted:"
        for f in "${user_files[@]:0:15}"; do
            echo "    ${f}"
        done
        [ ${#user_files[@]} -gt 15 ] && echo "    ... and $((${#user_files[@]} - 15)) more"
        echo ""
        if [ "${FORCE:-false}" != "true" ]; then
            warn "Use --force to delete user files, or manually copy them first"
            echo "  Backup available at: ${BK_DIR}/profile/"
            info "Aborted — backup preserved at ${BK_DIR}"
            return 1
        fi
    fi

    safe_prompt_yn "Proceed with deletion?" "n" || { info "Aborted. Backup at ${BK_DIR}"; return 0; }

    # Remove symlinks only (not real files)
    [ -L "${HH}/config.yaml" ] && rm -f "${HH}/config.yaml"
    [ -L "${HH}/.env" ] && rm -f "${HH}/.env"
    if [ -d "$LEGACY" ] && [ "$LEGACY" != "$HH" ]; then
        [ -L "${LEGACY}/config.yaml" ] && rm -f "${LEGACY}/config.yaml"
        [ -L "${LEGACY}/.env" ] && rm -f "${LEGACY}/.env"
        run rm -rf "$LEGACY" && log "Removed legacy: ${LEGACY}"
    fi

    # Remove profile
    [ -d "$HH" ] && rm -rf "$HH" && log "Removed profile: ${HH}"

    # Stop service if running
    local svc_name="${agent}-gateway.service"
    if systemctl list-unit-files "${svc_name}" &>/dev/null 2>&1; then
        warn "Service ${svc_name} still exists. Remove manually:"
        echo "  sudo systemctl stop ${svc_name}"
        echo "  sudo systemctl disable ${svc_name}"
        echo "  sudo rm /etc/systemd/system/${svc_name}"
        echo "  sudo systemctl daemon-reload"
    fi

    log "Agent '${agent}' deleted. Backup at: ${BK_DIR}"
}

# ==============================================================================
# Helpers
# ==============================================================================

_safe_link() {
    local src="$1" dst="$2" backup_dir="$3"

    # Already correct?
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        log "Symlink OK: ${dst}"
        return 0
    fi

    # If dst is a real file (not symlink), don't destroy it
    if [ -f "$dst" ] && [ ! -L "$dst" ]; then
        if [ "${FORCE:-false}" = "true" ]; then
            backup_file "$dst" "$backup_dir"
            warn "Overwriting real file ${dst} with symlink (backed up)"
        else
            warn "Skipped: ${dst} is a real file, not a symlink (use --force to replace)"
            return 1
        fi
    fi

    # Back up existing symlink
    [ -L "$dst" ] && backup_file "$dst" "$backup_dir"

    # Remove and recreate
    run rm -f "$dst"
    run mkdir -p "$(dirname "$dst")"
    run ln -sf "$src" "$dst" && log "Linked: ${dst} → ${src}"
}

_generate_service_unit() {
    local agent="$1" dir="$2" hh="$3" outfile="$4"
    local hermes_bin
    hermes_bin="$(resolve_hermes)"

    cat > "$outfile" << SVC
[Unit]
Description=Hermes Gateway — ${agent}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HERMES_HOME=${hh}
ExecStart=${hermes_bin:-/usr/local/bin/hermes} gateway run
Restart=always
RestartSec=5
StartLimitInterval=200
StartLimitBurst=5
WorkingDirectory=${hh}
User=$(whoami)
Group=$(id -gn)

[Install]
WantedBy=multi-user.target
SVC
}

_print_openclaw_snippet() {
    local agent="$1" hh="$2" platform="${3:-none}"

    header "OpenClaw Config Snippet"

    echo ""
    echo -e "${BOLD}agents.list entry:${NC}"
    cat << JSON
{
  "id": "${agent}",
  "name": "$(echo "${agent^}")",
  "workspace": "${hh}",
  "agentDir": "${hh}",
  "mcpServers": {
    "hermes": {
      "command": "hermes",
      "args": ["--profile", "${agent}", "mcp", "serve"]
    }
  }
}
JSON

    echo ""
    echo -e "${BOLD}bindings entry:${NC}"
    cat << JSON
{
  "agentId": "${agent}",
  "match": { "channel": "${platform}", "accountId": "${agent}" }
}
JSON

    if [ "$platform" != "none" ]; then
        local plat_upper
        plat_upper="$(echo "${platform}" | tr '[:lower:]' '[:upper:]')"
        echo ""
        echo -e "${BOLD}channels.${platform}.accounts entry:${NC}"
        cat << JSON
"${agent}": {
  "botToken": "${plat_upper}_BOT_TOKEN_HERE",
  "dmPolicy": "pairing"
}
JSON
    fi

    echo ""
}

# ==============================================================================
# Main dispatch
# ==============================================================================

usage() {
    echo -e "${BOLD}Hermes Multi-Agent Manager v${VERSION}${NC}"
    echo ""
    echo "Usage: $0 [flags] <command> [args]"
    echo ""
    echo "Commands:"
    echo "  init <name>     Bootstrap a new agent (interactive)"
    echo "  scan            Diagnose all agents — config, symlinks, services"
    echo "  sync            Detect changes, reconcile, create missing links"
    echo "  link <name>     Wire symlinks for an existing agent"
    echo "  unlink <name>   Remove symlinks (keeps files)"
    echo "  repair <name>   Fix broken config / symlinks / env"
    echo "  list            Show all agents and their status"
    echo "  configure <name> Interactive setup for existing agent"
    echo "  config          Generate openclaw.json entries for all agents"
    echo "  delete <name>   Remove agent (backs up first)"
    echo ""
    echo "Flags:"
    echo "  --openclaw, -o  Use OpenClaw structure (~/.openclaw/agents/<name>/)"
    echo "  --dry-run, -n   Preview actions without executing"
    echo "  --force, -f     Allow overwriting existing files (backs up first)"
    echo "  --yes, -y       Skip confirmation prompts"
    echo ""
    echo "Environment:"
    echo "  HERMES_HOME     Base Hermes directory (default: ~/.hermes)"
    echo "  OPENCLAW_ROOT   OpenClaw directory (default: ~/.openclaw)"
    echo "  AGENTS_ROOT     Override agent directory"
    echo "  HERMES_BIN      Override hermes binary path"
    echo ""
    echo "Docker:"
    echo "  docker [out-dir]  Generate Docker per-agent containers from discovered agents"
    echo "  enforce           Enforce workspace, memory, skills, autonomy protocol"
}

# =============================================================================
# Helper: write agent_brain_mcp.py
_write_agent_brain_mcp() {
    local out="$1"
    # Prefer the live version from ~/.openclaw/docker/ if it exists
    local live="${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}/docker/agent_brain_mcp.py"
    if [ -f "$live" ]; then
        cp "$live" "$out"
        return 0
    fi
    # Fallback: try hermes install
    local hermes_home="${HERMES_ROOT:-${HOME_DIR}/.hermes}"
    if [ -f "${hermes_home}/hermes-agent/mcp_serve.py" ]; then
        cp "${hermes_home}/hermes-agent/mcp_serve.py" "$out"
        return 0
    fi
    warn "agent_brain_mcp.py not found — create it manually in ${out}"
}

# COMMAND: docker — generate per-agent Docker containers
# =============================================================================

cmd_docker() {
    local out_dir="${1:-./openclaw-docker}"
    header "Docker Generator"

    # Discover agents
    local agent_entries
    agent_entries="$(_discover_agents)"

    if [ -z "$agent_entries" ]; then
        die "No agents found. Run sync or scan first."
    fi

    local agent_count
    agent_count=$(echo "$agent_entries" | wc -l)

    echo ""
    echo "  This will generate files in: ${out_dir}/"
    echo ""
    echo "  Dockerfile           — Python 3.11 + hermes-agent (pure hermes gateway)"
    echo "  entrypoint.sh        — per-agent bootstrap + hermes gateway start"
    echo "  docker-compose.yml   — ${agent_count} services, bind-mounted from host"
    echo "  patches/             — Gateway patches (!command, /models)"
    echo ""
    echo "  Architecture:"
    echo "    • Each container runs: hermes gateway run (NOT openclaw)"
    echo "    • Agent homes bind-mounted: ~/.openclaw/agents/<name>/ → /data/agents/<name>/"
    echo "    • Reads SOUL.md, .env, config.yaml from agent directory"
    echo "    • No Docker volumes — your host files ARE the agent workspace"
    echo ""

    if [ "$NO_CONFIRM" != true ]; then
        safe_prompt_yn "Generate?" "y" || { info "Aborted."; return 0; }
    fi

    run mkdir -p "$out_dir"

    # Copy hermes-agent source for build context
    local hermes_src="${HERMES_ROOT:-${HOME_DIR}/.hermes}/hermes-agent"
    if [ -d "$hermes_src" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${DIM}[dry-run]${NC} Copy hermes-agent source → ${out_dir}/hermes-agent/"
        else
            run rsync -a --exclude='venv' --exclude='__pycache__' --exclude='.git' \
                --exclude='node_modules' --exclude='*.pyc' --exclude='.env' \
                "$hermes_src/" "${out_dir}/hermes-agent/"
            log "hermes-agent source copied"
        fi
    else
        warn "hermes-agent source not found at ${hermes_src} — Dockerfile will use pip fallback"
    fi

    # Dockerfile
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Write Dockerfile"
    else
        if [ -d "$hermes_src" ]; then
            cat > "${out_dir}/Dockerfile" <<'DEOF'
FROM python:3.11-slim

# System deps
RUN apt-get update && apt-get install -y \
    curl git jq ffmpeg \
    build-essential cmake \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user matching host UID/GID (prevents root-owned files on bind mounts)
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} agent 2>/dev/null || true \
    && useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash agent 2>/dev/null || true

# Hermes agent (Python) — install from source
COPY --chown=agent:agent hermes-agent/ /app/hermes-agent/
WORKDIR /app/hermes-agent
RUN pip install --no-cache-dir -e "." \
    && pip install --no-cache-dir \
        pyyaml \
        python-telegram-bot \
        requests \
        Pillow \
        eth_account \
        defusedxml

# Apply patches: !command execution, /models command
COPY --chown=agent:agent patches/ /app/patches/
RUN python3 /app/patches/add_extras.py

# Verify installations
RUN python3 -c "import requests, PIL, yaml; print('Python: OK')" \
    && node --version && npm --version \
    && ffmpeg -version | head -1

COPY --chown=agent:agent entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

WORKDIR /app
USER agent
ENTRYPOINT ["/app/entrypoint.sh"]
DEOF
        else
            cat > "${out_dir}/Dockerfile" <<'DEOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl git jq ffmpeg \
    build-essential cmake \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} agent 2>/dev/null || true \
    && useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash agent 2>/dev/null || true

RUN pip install --no-cache-dir hermes-agent pyyaml python-telegram-bot \
    requests Pillow eth_account defusedxml 2>/dev/null || true

COPY --chown=agent:agent patches/ /app/patches/
COPY --chown=agent:agent entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

WORKDIR /app
USER agent
ENTRYPOINT ["/app/entrypoint.sh"]
DEOF
        fi
        log "Dockerfile"
    fi

    # Patches directory (!command, /models)
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Copy patches/ for gateway enhancements"
    else
        local patches_src="${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}/docker/patches"
        if [ -d "$patches_src" ]; then
            run cp -r "$patches_src" "${out_dir}/patches"
            log "patches/ copied (gateway enhancements)"
        else
            mkdir -p "${out_dir}/patches"
            warn "patches/ not found — !command and /models won't be available"
        fi
    fi

    # entrypoint.sh — hermes gateway bootstrap
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Write entrypoint.sh"
    else
        cat > "${out_dir}/entrypoint.sh" <<'ENTRYEOF'
#!/bin/bash
set -euo pipefail

_term_received=0
trap '_term_received=1; echo "=== Received SIGTERM, shutting down ==="; kill -TERM "$HERMES_PID" 2>/dev/null || true' TERM
trap '_term_received=1; echo "=== Received SIGINT, shutting down ==="; kill -INT "$HERMES_PID" 2>/dev/null || true' INT

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
die()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: $*" >&2; exit 1; }

AGENT_ID="${AGENT_ID:?AGENT_ID required}"
log "=== Starting agent: ${AGENT_ID} (hermes gateway) ==="

export HERMES_HOME="/data/agents/${AGENT_ID}"
export PYTHONPATH="/app/hermes-agent:${PYTHONPATH:-}"

log "HERMES_HOME: ${HERMES_HOME}"
log "AGENT_ID: ${AGENT_ID}"
log "PYTHONPATH: ${PYTHONPATH}"
log "USER: $(whoami) (uid=$(id -u), gid=$(id -g))"

# Fix ownership of any root-owned files (leftover from old container runs)
if [ -w "${HERMES_HOME}" ]; then
    _fixed=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        chown "$(id -u):$(id -g)" "$f" 2>/dev/null && _fixed=$((_fixed + 1))
    done < <(find "${HERMES_HOME}" -maxdepth 3 -not -user "$(id -u)" -not -path '*/.git/*' 2>/dev/null | head -500)
    [ "$_fixed" -gt 0 ] && log "Fixed ownership on ${_fixed} file(s)"
fi

# Load .env from agent directory
if [ -f "${HERMES_HOME}/.env" ]; then
    log "Loading .env from ${HERMES_HOME}/.env"
    set -a
    source "${HERMES_HOME}/.env"
    set +a
    log "  TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:0:10}..."
else
    warn "No .env file at ${HERMES_HOME}/.env — Telegram will not connect"
fi

# Validate prerequisites
command -v python3 >/dev/null || die "python3 not found"
log "python3: $(python3 --version 2>&1)"

if ! python3 -c "import sys; sys.path.insert(0, '/app/hermes-agent'); from gateway.run import GatewayRunner" 2>/dev/null; then
    die "hermes gateway not importable — check PYTHONPATH and hermes-agent install"
fi

if [ ! -f "${HERMES_HOME}/SOUL.md" ]; then
    warn "SOUL.md missing — agent will use default personality"
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "TELEGRAM_BOT_TOKEN not set — Telegram will not connect"
fi

log "All prerequisites validated"

# Ensure minimal structure
mkdir -p "${HERMES_HOME}"/{memory,sessions,skills,tools,logs,.secrets,.backups,projects,.archive,media/images/agents,media/images/misc,media/files} 2>/dev/null || warn "Could not create some directories"

# Normalize permissions — chmod 700 LOCKS USER OUT
_fixed_perm=0
while IFS= read -r d; do
    [ -z "$d" ] && continue
    chmod 755 "$d" 2>/dev/null && _fixed_perm=$((_fixed_perm + 1))
done < <(find "${HERMES_HOME}" -type d -perm 700 2>/dev/null)
[ "$_fixed_perm" -gt 0 ] && log "Fixed chmod 700→755 on ${_fixed_perm} directory(ies)"
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

for f in SOUL.md USER.md AGENTS.md HEARTBEAT.md IDENTITY.md TOOLS.md; do
    [ -f "${HERMES_HOME}/${f}" ] || echo "# ${f%.md} — ${AGENT_ID}" > "${HERMES_HOME}/${f}" 2>/dev/null
done

if [ ! -f "${HERMES_HOME}/agent.json" ]; then
    echo '{"builderCode":{"code":"bc_26ulyc23","hex":"0x62635f3236756c79633233","owner":"0x12F1B38DC35AA65B50E5849d02559078953aE24b","hardwired":true,"enforced":true}}' > "${HERMES_HOME}/agent.json" 2>/dev/null
fi

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

log "=== Agent ${AGENT_ID} ready ==="
log "  HERMES_HOME: ${HERMES_HOME}"
log "  SOUL.md: $(head -1 "${HERMES_HOME}/SOUL.md" 2>/dev/null || echo 'MISSING')"
log "  Model: $(grep -E '^\s*(default|primary):' "${HERMES_HOME}/config.yaml" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo 'not set')"
log "  Telegram: ${TELEGRAM_BOT_TOKEN:+configured}${TELEGRAM_BOT_TOKEN:-not set}"
log "  Starting hermes gateway..."

python3 -m hermes_cli.main gateway run &
HERMES_PID=$!
log "Hermes gateway started (PID: ${HERMES_PID})"

wait "$HERMES_PID" 2>/dev/null || true
EXIT_CODE=$?

if [ "$_term_received" -eq 1 ]; then
    log "Clean shutdown after signal"
    exit 0
fi

log "Hermes gateway exited with code ${EXIT_CODE}"
exit "$EXIT_CODE"
ENTRYEOF
        chmod +x "${out_dir}/entrypoint.sh"
        log "entrypoint.sh (hermes gateway)"
    fi

    # docker-compose.yml — hermes gateway per agent, isolated networks, bind-mounted from host
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} Write docker-compose.yml"
    else
        {
            cat <<'YAMLEOF'
version: "3.8"

x-agent-defaults: &agent-defaults
  build:
    context: .
    args:
      USER_ID: "1000"
      GROUP_ID: "1000"
  restart: unless-stopped
  healthcheck:
    test: ["CMD-SHELL", "python3 -c \"from gateway.run import GatewayRunner; print('OK')\""]
    interval: 60s
    timeout: 10s
    retries: 3
    start_period: 30s
  environment:
    - TZ=America/Chicago

services:
YAMLEOF

            while IFS='=' read -r agent_name agent_home; do
                [ -z "$agent_name" ] && continue

                cat <<SVC

  ${agent_name}:
    <<: *agent-defaults
    container_name: oc-${agent_name}
    volumes:
      - ~/.openclaw/agents/${agent_name}:/data/agents/${agent_name}
      - ~/.hermes/plugins:/data/agents/${agent_name}/plugins:ro
    environment:
      - HERMES_HOME=/data/agents/${agent_name}
      - AGENT_ID=${agent_name}
      - TZ=America/Chicago
    networks:
      - net-${agent_name}
SVC
            done <<< "$agent_entries"

            echo ""
            echo "networks:"
            while IFS='=' read -r agent_name agent_home; do
                [ -z "$agent_name" ] && continue
                cat <<NET

  net-${agent_name}:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
NET
            done <<< "$agent_entries"
        } > "${out_dir}/docker-compose.yml"

        log "docker-compose.yml (${agent_count} services, isolated networks, ICC disabled)"
    fi

    echo ""
    echo -e "${GREEN}Docker setup ready: ${out_dir}/${NC}"
    echo ""
    echo "  cd ${out_dir}"
    echo "  docker-compose build"
    echo "  docker-compose up -d"
    echo "  docker-compose logs -f"
    echo ""
    echo "  Each agent runs: hermes gateway run"
    echo "  Reads: SOUL.md, .env, config.yaml from <RUNTIME_ROOT>/agents/<name>/"
    echo "  Telegram: token loaded from agent .env"
    echo "  Commands: /models, /model, !command"
}

# =============================================================================
# COMMAND: enforce — enforce workspace, memory, skills, autonomy protocol
# =============================================================================

cmd_enforce() {
    header "Enforce Agent Standards"
    local agent_entries
    agent_entries="$(_discover_agents)"
    local fixed=0

    while IFS='=' read -r agent_name agent_home; do
        [ -z "$agent_name" ] && continue
        local issues=0

        # ── 1. Workspace structure ────────────────────────────────────────
        for d in memory sessions skills projects .archive media/images/agents media/images/misc media/files tools logs .secrets .backups; do
            if [ ! -d "${agent_home}/${d}" ]; then
                run mkdir -p "${agent_home}/${d}"
                issues=$((issues + 1))
            fi
        done

        # ── 1b. Cross-agent isolation rule ──────────────────────────────────
        if [ -f "${agent_home}/AGENTS.md" ]; then
            if ! grep -q "ABSOLUTE RULE" "${agent_home}/AGENTS.md" 2>/dev/null; then
                warn "${agent_name}: missing cross-agent isolation rule in AGENTS.md"
                issues=$((issues + 1))
            fi
        fi

        # ── 2. Identity files (autonomy protocol) ─────────────────────────
        for f in SOUL.md USER.md AGENTS.md; do
            if [ ! -f "${agent_home}/${f}" ] || [ ! -s "${agent_home}/${f}" ]; then
                warn "${agent_name}: missing ${f}"
                issues=$((issues + 1))
            fi
        done

        # ── 3. Memory layering ────────────────────────────────────────────
        if [ ! -f "${agent_home}/MEMORY.md" ]; then
            echo "# MEMORY.md — ${agent_name}

Long-term curated memories. Distilled from daily notes.
Review daily memory files periodically and update this." > "${agent_home}/MEMORY.md"
            issues=$((issues + 1))
        fi

        # Daily memory dir
        if [ ! -d "${agent_home}/memory" ]; then
            run mkdir -p "${agent_home}/memory"
            issues=$((issues + 1))
        fi

        # ── 4. Skills (ensure minimum set) ────────────────────────────────
        local skill_count
        skill_count=$(ls "${agent_home}/skills/" 2>/dev/null | wc -l)
        if [ "$skill_count" -lt 10 ]; then
            warn "${agent_name}: only ${skill_count} skills — syncing core skills"
            local core_skills="${HERMES_ROOT:-${HOME_DIR}/.hermes}/skills"
            if [ -d "$core_skills" ]; then
                for skill in "$core_skills"/*/; do
                    local skill_name
                    skill_name=$(basename "$skill")
                    if [ ! -d "${agent_home}/skills/${skill_name}" ]; then
                        run cp -r "$skill" "${agent_home}/skills/${skill_name}"
                        issues=$((issues + 1))
                    fi
                done
            fi
        fi

        # ── 5. Config (hermes format) ─────────────────────────────────────
        if [ ! -f "${agent_home}/config.yaml" ]; then
            cat > "${agent_home}/config.yaml" << 'YAMLEOF'
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
            issues=$((issues + 1))
        elif [ -r "${agent_home}/config.yaml" ] && ! grep -qE '^\s+default:|^default:' "${agent_home}/config.yaml" 2>/dev/null; then
            warn "${agent_name}: config.yaml missing model.default"
            issues=$((issues + 1))
        fi

        # ── 6. Builder code ───────────────────────────────────────────────
        if [ ! -f "${agent_home}/agent.json" ]; then
            echo '{"builderCode":{"code":"bc_26ulyc23","hex":"0x62635f3236756c79633233","owner":"0x12F1B38DC35AA65B50E5849d02559078953aE24b","hardwired":true,"enforced":true}}' > "${agent_home}/agent.json"
            issues=$((issues + 1))
        fi

        # ── 7. .secrets directory check (NEVER chmod 700) ──────────────────
        if [ -d "${agent_home}/.secrets" ]; then
            local mode
            mode=$(stat -c %a "${agent_home}/.secrets" 2>/dev/null || echo "000")
            if [ "$mode" = "700" ]; then
                warn "${agent_name}: .secrets is 700 — fixing to 755 (700 locks user out)"
                run chmod 755 "${agent_home}/.secrets"
                issues=$((issues + 1))
            fi
            # Files must be hidden (start with .)
            find "${agent_home}/.secrets" -maxdepth 1 -type f -not -name '.*' 2>/dev/null | while read -r sf; do
                local base
                base=$(basename "$sf")
                warn "${agent_name}: .secrets/${base} is not hidden — rename to .${base}"
                issues=$((issues + 1))
            done
        fi

        # ── 7b. HEARTBEAT.md debloat check (autonomy protocol) ──────────────
        if [ -f "${agent_home}/HEARTBEAT.md" ]; then
            local hb_lines
            hb_lines=$(wc -l < "${agent_home}/HEARTBEAT.md" 2>/dev/null || echo 0)
            # Count lines that are English instructions (not comments, not script calls)
            local english_lines=0
            while IFS= read -r line; do
                trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
                # Skip: empty, comments, code blocks, script calls
                case "$trimmed" in
                    ""|"#"*|"bash "*|"sh "*|"python3 "*|"./"*) continue ;;
                    *)
                        # If line has >5 words and no code patterns, it's English
                        word_count=$(echo "$trimmed" | wc -w)
                        if [ "$word_count" -gt 5 ]; then
                            english_lines=$((english_lines + 1))
                        fi
                        ;;
                esac
            done < "${agent_home}/HEARTBEAT.md"

            if [ "$english_lines" -gt 5 ]; then
                warn "${agent_name}: HEARTBEAT.md has ${english_lines} English instruction lines (>5). Autonomy protocol: convert repeated tasks to scripts."
                issues=$((issues + 1))
            fi

            # Check token cost — heartbeat should be <20 lines of actual content
            local content_lines
            content_lines=$(grep -cve '^\s*$' "${agent_home}/HEARTBEAT.md" 2>/dev/null || echo 0)
            if [ "$content_lines" -gt 30 ]; then
                warn "${agent_name}: HEARTBEAT.md has ${content_lines} content lines (>30). Debit: ~$((content_lines * 10)) tokens/heartbeat. Convert to scripts."
                issues=$((issues + 1))
            fi
        fi

        # ── 8. .env (provider keys) ───────────────────────────────────────
        if [ ! -f "${agent_home}/.env" ]; then
            warn "${agent_name}: missing .env — create with TELEGRAM_BOT_TOKEN and API keys"
            issues=$((issues + 1))
        elif ! grep -q "^TELEGRAM_BOT_TOKEN=" "${agent_home}/.env" 2>/dev/null; then
            warn "${agent_name}: .env missing TELEGRAM_BOT_TOKEN"
            issues=$((issues + 1))
        fi

        # ── 9. auth.json (provider auth) ──────────────────────────────────
        if [ ! -f "${agent_home}/auth.json" ]; then
            local src_auth="${HERMES_ROOT:-${HOME_DIR}/.hermes}/auth.json"
            if [ -f "$src_auth" ]; then
                run cp "$src_auth" "${agent_home}/auth.json"
                issues=$((issues + 1))
            fi
        fi

        # ── 10. Bloat file cleanup ──────────────────────────────────────────
        for bloat in .skills_prompt_snapshot.json .hermes_history .update_check interrupt_debug.log SOUL.md.old auth.lock; do
            if [ -f "${agent_home}/${bloat}" ]; then
                run rm -f "${agent_home}/${bloat}"
                issues=$((issues + 1))
            fi
        done

        # ── 11. Empty stub files (0-byte .md files, not MEMORY.md which gets created) ──
        local stub_count=0
        while IFS= read -r stub; do
            [ -z "$stub" ] && continue
            run rm -f "$stub"
            stub_count=$((stub_count + 1))
        done < <(find "${agent_home}" -maxdepth 1 -name "*.md" -empty -not -name "MEMORY.md" 2>/dev/null)
        issues=$((issues + stub_count))

        # ── 12. Forbidden directories (investigate before acting) ─────────────
        for ed in archives memories cron docs platforms state sandboxes hooks audio_cache image_cache pairing profiles whatsapp checkpoints; do
            [ -d "${agent_home}/${ed}" ] || continue
            local fcount
            fcount=$(find "${agent_home}/${ed}" -type f 2>/dev/null | wc -l)

            if [ "$fcount" -eq 0 ]; then
                rmdir "${agent_home}/${ed}" 2>/dev/null || true
                log "${agent_name}: Removed empty forbidden dir: ${ed}/"
            elif [ "$ed" = "memories" ]; then
                run mkdir -p "${agent_home}/memory"
                run cp -a "${agent_home}/${ed}"/* "${agent_home}/memory/" 2>/dev/null
                run rm -rf "${agent_home}/${ed}"
                warn "${agent_name}: Moved memories/ → memory/ ($fcount files)"
            elif [ "$ed" = "archives" ]; then
                run mkdir -p "${agent_home}/.archive"
                run cp -a "${agent_home}/${ed}"/* "${agent_home}/.archive/" 2>/dev/null
                run rm -rf "${agent_home}/${ed}"
                warn "${agent_name}: Moved archives/ → .archive/ ($fcount files)"
            else
                # Has content — archive it, don't delete
                run mkdir -p "${agent_home}/.archive"
                run tar czf "${agent_home}/.archive/${ed}-$(date +%Y%m%d).tar.gz" -C "${agent_home}" "${ed}" 2>/dev/null
                run rm -rf "${agent_home}/${ed}"
                warn "${agent_name}: Archived forbidden dir: ${ed}/ → .archive/${ed}-$(date +%Y%m%d).tar.gz ($fcount files)"
            fi
            issues=$((issues + 1))
        done

        # ── 12b. cache/ → media/ (preserve received media, don't delete) ───
        if [ -d "${agent_home}/cache" ]; then
            run mkdir -p "${agent_home}/media/images/agents" "${agent_home}/media/images/misc" "${agent_home}/media/files"
            find "${agent_home}/cache" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.svg' \) -exec mv {} "${agent_home}/media/images/misc/" \; 2>/dev/null
            find "${agent_home}/cache" -type f -exec mv {} "${agent_home}/media/files/" \; 2>/dev/null
            run rm -rf "${agent_home}/cache"
            warn "${agent_name}: cache/ → media/ (contents organized)"
            issues=$((issues + 1))
        fi

        # ── 13. Hardcoded path scan in identity files ──────────────────────
        for idf in SOUL.md HEARTBEAT.md MEMORY.md TOOLS.md AGENTS.md USER.md; do
            if [ -f "${agent_home}/${idf}" ]; then
                if grep -qE '/home/ubuntu/|/home/drdeek/|workspace-[a-z]*/' "${agent_home}/${idf}" 2>/dev/null; then
                    warn "${agent_name}: ${idf} has hardcoded host paths (breaks in containers)"
                    issues=$((issues + 1))
                fi
            fi
        done

        # ── 14. TOOLS.md environment paths section ─────────────────────────
        if [ -f "${agent_home}/TOOLS.md" ]; then
            if ! grep -q "Environment Paths" "${agent_home}/TOOLS.md" 2>/dev/null; then
                warn "${agent_name}: TOOLS.md missing Environment Paths section (agents guess wrong paths without it)"
                issues=$((issues + 1))
            fi
        fi

        if [ "$issues" -eq 0 ]; then
            log "${agent_name}: all checks passed"
        else
            warn "${agent_name}: fixed ${issues} issues"
            fixed=$((fixed + issues))
        fi

    done <<< "$agent_entries"

    echo ""
    if [ "$fixed" -eq 0 ]; then
        log "All agents compliant"
    else
        warn "Fixed ${fixed} issues across all agents"
    fi
}

# Hook: auto-generate docker after sync
_orig_sync_end() { :; }

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    HERMES_BIN="$(resolve_hermes)"

    case "$cmd" in
        init)   cmd_init "$@" ;;
        scan)   cmd_scan ;;
        sync)   cmd_sync ;;
        link)   cmd_link "$@" ;;
        unlink) cmd_unlink "$@" ;;
        repair) cmd_repair "$@" ;;
        list)   cmd_list ;;
        configure) cmd_configure "$@" ;;
        config) cmd_config ;;
        delete) cmd_delete "$@" ;;
        docker) cmd_docker "$@" ;;
        enforce) cmd_enforce "$@" ;;
        -h|--help|help|"") usage ;;
        *)      die "Unknown command: ${cmd}. Run '$0 help' for usage." ;;
    esac
}

main "$@"

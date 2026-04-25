#!/usr/bin/env bash
# =============================================================================
# switch-model.sh — Quick Model/Provider Switcher
# =============================================================================
#
# Usage:
#   bash switch-model.sh                        # Interactive menu
#   bash switch-model.sh <agent> <provider> <model>
#   bash switch-model.sh all nous xiaomi/mimo-v2-pro
#   bash switch-model.sh --list                  # Show all agents' current models
#   bash switch-model.sh --presets               # Show available presets
# =============================================================================

set -euo pipefail

# Use portable agent directory
AGENTS_DIR="${RUNTIME_ROOT:-$(pwd)}/agents"
# AGENT_NAMES should be dynamically discovered from agents directory
# Default to empty and populate from filesystem
AGENT_NAMES=""

# ── Presets ───────────────────────────────────────────────────────────────────

declare -A PRESETS=(
    ["nous-mimo"]="nous|xiaomi/mimo-v2-pro"
    ["nous-hermes"]="nous|nous-hermes-3-llama-3.1-8b"
    ["openrouter-gemma"]="openrouter|google/gemma-3-27b-it"
    ["openrouter-claude"]="openrouter|anthropic/claude-sonnet-4"
    ["openrouter-flash"]="openrouter|google/gemini-2.5-flash"
    ["mistral-small"]="mistral|mistral-small-latest"
    ["mistral-large"]="mistral|mistral-large-latest"
    ["ollama-qwen"]="ollama|qwen2.5:7b"
    ["ollama-llama"]="ollama|llama3.1:8b"
    ["qwen-portal"]="qwen|qwen-max"
)

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Functions ─────────────────────────────────────────────────────────────────

get_agent_names() {
    # Dynamically discover agent names from filesystem
    if [[ -d "$AGENTS_DIR" ]]; then
        find "$AGENTS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
    else
        echo ""
    fi
}

log()  { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo -e "${CYAN}ℹ${NC} $*"; }
header() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

get_current_model() {
    local name="$1"
    local cfg="$AGENTS_DIR/$name/config.yaml"
    if [ -f "$cfg" ]; then
        local provider=$(grep -E '^\s+default:' "$cfg" 2>/dev/null | head -1 | sed 's/.*default:\s*//' | tr -d '"' | tr -d "'")
        local prov=$(grep -E '^\s+provider:' "$cfg" 2>/dev/null | head -1 | sed 's/.*provider:\s*//' | tr -d '"' | tr -d "'")
        echo "$prov|$provider"
    else
        echo "?|?"
    fi
}

switch_model() {
    local name="$1"
    local provider="$2"
    local model="$3"
    local cfg="$AGENTS_DIR/$name/config.yaml"
    
    if [ ! -f "$cfg" ]; then
        echo "Error: $cfg not found" >&2
        return 1
    fi
    
    # Use sed to update model.default and model.provider
    # Handle root-owned files
    if [ -w "$cfg" ]; then
        sed -i "s|^\(\s*\)default:.*|\1default: $model|" "$cfg"
        sed -i "0,/^\(\s*\)provider:.*/s||\1provider: $provider|" "$cfg"
    else
        # Root-owned — copy, edit, copy back via docker
        local tmp="/tmp/cfg-switch-$name.yaml"
        cp "$cfg" "$tmp"
        sed -i "s|^\(\s*\)default:.*|\1default: $model|" "$tmp"
        sed -i "0,/^\(\s*\)provider:.*/s||\1provider: $provider|" "$tmp"
        sudo cp "$tmp" "$cfg" 2>/dev/null || cp "$tmp" "$cfg"
        rm -f "$tmp"
    fi
    
    log "$name → $provider/$model"
}

show_current() {
    header "Current Models"
    for name in $(get_agent_names); do
        local current=$(get_current_model "$name")
        local provider=$(echo "$current" | cut -d'|' -f1)
        local model=$(echo "$current" | cut -d'|' -f2)
        printf "  %-10s ${CYAN}%s${NC}/${GREEN}%s${NC}\n" "$name" "$provider" "$model"
    done
}

show_presets() {
    header "Available Presets"
    for preset in $(echo "${!PRESETS[@]}" | tr ' ' '\n' | sort); do
        local val="${PRESETS[$preset]}"
        local prov=$(echo "$val" | cut -d'|' -f1)
        local mod=$(echo "$val" | cut -d'|' -f2)
        printf "  ${CYAN}%-25s${NC} → %s/%s\n" "$preset" "$prov" "$mod"
    done
}

interactive() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         Model/Provider Switcher                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    show_current
    
    header "What to do?"
    echo "  1) Switch single agent"
    echo "  2) Switch all agents"
    echo "  3) Apply preset to agent"
    echo "  4) Apply preset to all"
    echo "  5) Show presets"
    echo ""
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"
    
    case "$choice" in
        1)
            echo ""
            echo "  Select agent:"
            local i=1
            local agent_list=($(get_agent_names))
            for name in "${agent_list[@]}"; do
                echo "    $i) $name"
                i=$((i+1))
            done
            read -rp "Agent number: " agent_num
            local name="${agent_list[$((agent_num-1))]}"
            read -rp "Provider (nous/openrouter/mistral/ollama/qwen): " provider
            read -rp "Model name: " model
            switch_model "$name" "$provider" "$model"
            ;;
        2)
            read -rp "Provider (nous/openrouter/mistral/ollama/qwen): " provider
            read -rp "Model name: " model
            for name in $(get_agent_names); do
                switch_model "$name" "$provider" "$model"
            done
            ;;
        3)
            show_presets
            read -rp "Preset name: " preset_name
            echo ""
            echo "  Select agent:"
            local i=1
            local agent_list=($(get_agent_names))
            for name in "${agent_list[@]}"; do
                echo "    $i) $name"
                i=$((i+1))
            done
            read -rp "Agent number: " agent_num
            local name="${agent_list[$((agent_num-1))]}"
            local val="${PRESETS[$preset_name]}"
            if [ -n "$val" ]; then
                switch_model "$name" "$(echo $val|cut -d'|' -f1)" "$(echo $val|cut -d'|' -f2)"
            else
                echo "Unknown preset: $preset_name" >&2
            fi
            ;;
        4)
            show_presets
            read -rp "Preset name: " preset_name
            local val="${PRESETS[$preset_name]}"
            if [ -n "$val" ]; then
                for name in $(get_agent_names); do
                    switch_model "$name" "$(echo $val|cut -d'|' -f1)" "$(echo $val|cut -d'|' -f2)"
                done
            else
                echo "Unknown preset: $preset_name" >&2
            fi
            ;;
        5)
            show_presets
            ;;
    esac
    
    echo ""
    show_current
    echo ""
    echo -e "${YELLOW}Restart containers to apply:${NC}"
    echo "  for name in $AGENT_NAMES; do docker restart oc-\$name; done"
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --list|-l)
        show_current
        ;;
    --presets|-p)
        show_presets
        ;;
    --help|-h)
        echo "Usage: switch-model.sh [OPTIONS] [AGENT] [PROVIDER] [MODEL]"
        echo ""
        echo "Options:"
        echo "  (none)            Interactive menu"
        echo "  --list            Show all agents' current models"
        echo "  --presets         Show available presets"
        echo "  --help            Show this help"
        echo ""
        echo "Direct:"
        echo "  switch-model.sh titan openrouter google/gemma-3-27b-it"
        echo "  switch-model.sh all nous xiaomi/mimo-v2-pro"
        ;;
    all)
        provider="${2:?Provider required}"
        model="${3:?Model required}"
        for name in $(get_agent_names); do
            switch_model "$name" "$provider" "$model"
        done
        echo ""
        echo "Restart containers: for name in \$(get_agent_names | tr '\n' ' '); do docker restart oc-\$name; done"
        ;;
    *)
        if [ $# -ge 3 ]; then
            switch_model "$1" "$2" "$3"
            echo ""
            echo "Restart container: docker restart oc-$1"
        else
            interactive
        fi
        ;;
esac

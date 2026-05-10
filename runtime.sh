#!/bin/bash
# =============================================================================
# 🌿 Hemlock Enterprise Runtime Orchestrator
# The Core Access Point for Agent & Crew Management
# =============================================================================

set -euo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/agents/crews"
CONFIG_DIR="$RUNTIME_ROOT/config"
LOGS_DIR="$RUNTIME_ROOT/logs"

# Source common library
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
else
    echo "ERROR: lib/common.sh not found."
    exit 1
fi

# =============================================================================
# UI HELPERS
# =============================================================================

header() {
    clear
    echo -e "${MAGENTA}================================================================================${NC}"
    echo -e "${MAGENTA}  🌿 HEMLOCK ENTERPRISE RUNTIME${NC}"
    echo -e "${MAGENTA}================================================================================${NC}"
    echo ""
}

pause() {
    echo ""
    read -p "Press [Enter] to continue..."
}

# =============================================================================
# MENU HANDLERS
# =============================================================================

menu_main() {
    while true; do
        header
        echo -e "${CYAN}MAIN MENU${NC}"
        echo "1) Project Manager (Blueprints & Planning)"
        echo "2) Agent Management (Isolated Containers)"
        echo "3) Crew Management (Collaboration)"
        echo "4) System Operations (Health & Diagnostics)"
        echo "5) Cleanup & Hardening"
        echo "6) Exit"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) menu_project_manager ;;
            2) menu_agent_management ;;
            3) menu_crew_management ;;
            4) menu_system_ops ;;
            5) menu_cleanup ;;
            6) exit 0 ;;
            *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
        esac
    done
}

menu_project_manager() {
    while true; do
        header
        echo -e "${CYAN}PROJECT MANAGER WORKFLOW${NC}"
        echo "1) Create Project Blueprint (PLAN)"
        echo "2) Confirm Blueprint (EXECUTE OVERRIDE)"
        echo "3) Hand off to Lead Agent (HANDOFF)"
        echo "4) View Blueprint Status & Audit Logs"
        echo "5) Back to Main Menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) 
                read -p "Project Name: " name
                "$SCRIPTS_DIR/hemlock-blueprint-manager.sh" plan "$name"
                pause ;;
            2) 
                read -p "Blueprint ID: " bid
                "$SCRIPTS_DIR/hemlock-blueprint-manager.sh" confirm "$bid"
                pause ;;
            3) 
                read -p "Blueprint ID: " bid
                "$SCRIPTS_DIR/hemlock-blueprint-manager.sh" handoff "$bid"
                pause ;;
            4) 
                read -p "Blueprint ID: " bid
                "$SCRIPTS_DIR/hemlock-blueprint-manager.sh" status "$bid"
                pause ;;
            5) return ;;
            *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
        esac
    done
}

menu_agent_management() {
    while true; do
        header
        echo -e "${CYAN}AGENT MANAGEMENT (ISOLATED VOLUMES)${NC}"
        echo "1) Create New Isolated Agent"
        echo "2) List Agents"
        echo "3) Start Agent Container"
        echo "4) Stop Agent Container"
        echo "5) Export Agent Bundle"
        echo "6) Import Agent Bundle"
        echo "7) Delete Agent"
        echo "8) Back to Main Menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) 
                read -p "Agent ID: " aid
                read -p "Model (ollama/qwen3:0.6b): " model
                "$SCRIPTS_DIR/agent-create.sh" --id "$aid" --model "${model:-ollama/qwen3:0.6b}"
                pause ;;
            2) 
                ls -1 "$AGENTS_DIR"
                pause ;;
            3) 
                read -p "Agent ID: " aid
                "$SCRIPTS_DIR/agent-control.sh" start "$aid"
                pause ;;
            4) 
                read -p "Agent ID: " aid
                "$SCRIPTS_DIR/agent-control.sh" stop "$aid"
                pause ;;
            5) 
                read -p "Agent ID: " aid
                read -p "Destination: " dest
                "$SCRIPTS_DIR/agent-export.sh" "$aid" "$dest"
                pause ;;
            6) 
                read -p "Source Directory: " src
                read -p "Target ID: " aid
                "$SCRIPTS_DIR/agent-import.sh" "$src" "$aid"
                pause ;;
            7) 
                read -p "Agent ID to DELETE: " aid
                "$SCRIPTS_DIR/agent-delete.sh" --id "$aid"
                pause ;;
            8) return ;;
            *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
        esac
    done
}

menu_system_ops() {
    while true; do
        header
        echo -e "${CYAN}SYSTEM OPERATIONS${NC}"
        echo "1) System Health Status"
        echo "2) Run Hemlock Doctor (Diagnostics)"
        echo "3) Initialize System (First Run)"
        echo "4) Update Framework"
        echo "5) Back to Main Menu"
        echo ""
        read -p "Selection: " choice

        case $choice in
            1) "$SCRIPTS_DIR/system/hemlock-doctor.sh" status; pause ;;
            2) "$SCRIPTS_DIR/system/hemlock-doctor.sh" check; pause ;;
            3) "$SCRIPTS_DIR/system/first-run.sh" full; pause ;;
            4) "$RUNTIME_ROOT/scripts/runtime.sh" update; pause ;;
            5) return ;;
            *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
        esac
    done
}

menu_cleanup() {
    header
    echo -e "${CYAN}CLEANUP & HARDENING${NC}"
    echo "Running workspace enforcement and security hardening..."
    "$SCRIPTS_DIR/enforce.sh" "$AGENTS_DIR"
    "$SCRIPTS_DIR/security-harden.sh"
    pause
}

# Start the menu loop
if [[ $# -eq 0 ]]; then
    menu_main
else
    # Allow CLI-style bypass
    "$SCRIPTS_DIR/runtime.sh" "$@"
fi
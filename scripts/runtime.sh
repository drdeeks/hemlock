#!/bin/bash
# OpenClaw Runtime Management System
# Unified CLI for agent lifecycle management

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(dirname "$SCRIPT_DIR")"
AGENTS_DIR="$RUNTIME_DIR/agents"
CONFIG_DIR="$RUNTIME_DIR/config"
LOG_DIR="$RUNTIME_DIR/logs"
DOCKER_COMPOSE_FILE="$RUNTIME_DIR/docker-compose.yml"

# Ensure directories exist
mkdir -p "$AGENTS_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Source helper functions
source "$SCRIPT_DIR/helpers.sh"

# Main menu
main_menu() {
    clear
    echo "============================================="
    echo " OpenClaw Runtime Management System"
    echo "============================================="
    echo "1. Agent Management"
    echo "2. Crew Management (A2A)"
    echo "3. Runtime Validation"
    echo "4. Security Hardening"
    echo "5. System Monitoring"
    echo "6. Configuration"
    echo "7. Exit"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-7]: " choice
    case $choice in
        1) agent_menu ;; 
        2) crew_menu ;; 
        3) validation_menu ;; 
        4) security_menu ;; 
        5) monitoring_menu ;; 
        6) config_menu ;; 
        7) exit 0 ;; 
        *) echo "Invalid option"; sleep 1; main_menu ;;
    esac
}

# Agent management menu
agent_menu() {
    clear
    echo "============================================="
    echo " Agent Management"
    echo "============================================="
    echo "1. Create New Agent"
    echo "2. Import Existing Agent"
    echo "3. Export Agent"
    echo "4. Start Agent"
    echo "5. Stop Agent"
    echo "6. Monitor Agent"
    echo "7. List Agents"
    echo "8. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-8]: " choice
    case $choice in
        1) create_agent ;; 
        2) import_agent ;; 
        3) export_agent ;; 
        4) start_agent ;; 
        5) stop_agent ;; 
        6) monitor_agent ;; 
        7) list_agents ;; 
        8) main_menu ;; 
        *) echo "Invalid option"; sleep 1; agent_menu ;;
    esac
}

# Validation menu
validation_menu() {
    clear
    echo "============================================="
    echo " Runtime Validation"
    echo "============================================="
    echo "1. Run Full Validation"
    echo "2. Hermes Doctor (Interactive)"
    echo "3. Check Docker Environment"
    echo "4. Validate Configurations"
    echo "5. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-5]: " choice
    case $choice in
        1) run_validation --full ;; 
        2) hermes_doctor ;; 
        3) check_docker ;; 
        4) validate_configs ;; 
        5) main_menu ;; 
        *) echo "Invalid option"; sleep 1; validation_menu ;;
    esac
}

# Security menu
security_menu() {
    clear
    echo "============================================="
    echo " Security Hardening"
    echo "============================================="
    echo "1. Apply Security Hardening"
    echo "2. Check Security Status"
    echo "3. Reset Security Settings"
    echo "4. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-4]: " choice
    case $choice in
        1) apply_security_hardening ;; 
        2) check_security_status ;; 
        3) reset_security ;; 
        4) main_menu ;; 
        *) echo "Invalid option"; sleep 1; security_menu ;;
    esac
}

# Monitoring menu
monitoring_menu() {
    clear
    echo "============================================="
    echo " System Monitoring"
    echo "============================================="
    echo "1. View Runtime Logs"
    echo "2. View Agent Logs"
    echo "3. Check System Health"
    echo "4. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-4]: " choice
    case $choice in
        1) view_runtime_logs ;; 
        2) view_agent_logs ;; 
        3) check_system_health ;; 
        4) main_menu ;; 
        *) echo "Invalid option"; sleep 1; monitoring_menu ;;
    esac
}

# Crew management menu
crew_menu() {
    clear
    echo "============================================="
    echo " Crew Management (A2A Orchestration)"
    echo "============================================="
    echo "1. Create New Crew"
    echo "2. Join Crew"
    echo "3. Leave Crew"
    echo "4. List All Crews"
    echo "5. Start Crew"
    echo "6. Monitor Crew"
    echo "7. Dissolve Crew"
    echo "8. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-8]: " choice
    case $choice in
        1) create_crew ;; 
        2) join_crew ;; 
        3) leave_crew ;; 
        4) list_crews ;; 
        5) start_crew ;; 
        6) monitor_crew ;; 
        7) dissolve_crew ;; 
        8) main_menu ;; 
        *) echo "Invalid option"; sleep 1; crew_menu ;;
    esac
}

# Configuration menu
config_menu() {
    clear
    echo "============================================="
    echo " Configuration Management"
    echo "============================================="
    echo "1. Edit Runtime Configuration"
    echo "2. Edit Agent Configuration"
    echo "3. View Current Configuration"
    echo "4. Back to Main Menu"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-4]: " choice
    case $choice in
        1) edit_runtime_config ;; 
        2) edit_agent_config ;; 
        3) view_config ;; 
        4) main_menu ;; 
        *) echo "Invalid option"; sleep 1; config_menu ;;
    esac
}

# Agent management functions
create_agent() {
    clear
    echo "============================================="
    echo " Create New Agent"
    echo "============================================="
    
    read -rp "Enter agent ID (e.g., mort): " agent_id
    read -rp "Enter model (e.g., ollama/qwen3:0.6b): " model
    read -rp "Enter agent name [default: $agent_id]: " name
    name=${name:-$agent_id}
    
    echo "Creating agent $agent_id..."
    "$SCRIPT_DIR/agent-create.sh" --id "$agent_id" --model "$model" --name "$name"
    
    echo "Agent $agent_id created successfully!"
    press_any_key
    agent_menu
}

import_agent() {
    clear
    echo "============================================="
    echo " Import Existing Agent"
    echo "============================================="
    
    list_existing_agents
    read -rp "Enter source path (e.g., ~/.openclaw/agents/mort): " source
    read -rp "Enter target agent ID: " target_id
    
    echo "Importing agent from $source to $target_id..."
    "$SCRIPT_DIR/agent-import.sh" --source "$source" --target "$target_id"
    
    echo "Agent $target_id imported successfully!"
    press_any_key
    agent_menu
}

export_agent() {
    clear
    echo "============================================="
    echo " Export Agent"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to export: " agent_id
    read -rp "Enter destination path (e.g., ~/backups/mort): " dest
    
    echo "Exporting agent $agent_id to $dest..."
    "$SCRIPT_DIR/agent-export.sh" --id "$agent_id" --dest "$dest"
    
    echo "Agent $agent_id exported successfully!"
    press_any_key
    agent_menu
}

start_agent() {
    clear
    echo "============================================="
    echo " Start Agent"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to start: " agent_id
    
    echo "Starting agent $agent_id..."
    "$SCRIPT_DIR/agent-control.sh" start "$agent_id"
    
    echo "Agent $agent_id started!"
    press_any_key
    agent_menu
}

stop_agent() {
    clear
    echo "============================================="
    echo " Stop Agent"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to stop: " agent_id
    
    echo "Stopping agent $agent_id..."
    "$SCRIPT_DIR/agent-control.sh" stop "$agent_id"
    
    echo "Agent $agent_id stopped!"
    press_any_key
    agent_menu
}

monitor_agent() {
    clear
    echo "============================================="
    echo " Monitor Agent"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to monitor: " agent_id
    
    echo "Monitoring agent $agent_id (Ctrl+C to exit)..."
    "$SCRIPT_DIR/agent-monitor.sh" "$agent_id"
}

list_agents() {
    echo "Available agents:"
    ls -1 "$AGENTS_DIR" 2>/dev/null || echo "No agents found"
    echo "---------------------------------------------"
}

# Validation functions
run_validation() {
    clear
    echo "============================================="
    echo " Running Full Validation"
    echo "============================================="
    
    "$SCRIPT_DIR/runtime-doctor.sh" --full $@
    
    press_any_key
    validation_menu
}

hermes_doctor() {
    clear
    echo "============================================="
    echo " Hermes Doctor - Interactive Validation"
    echo "============================================="
    
    "$SCRIPT_DIR/runtime-doctor.sh" --interactive
    
    press_any_key
    validation_menu
}

check_docker() {
    clear
    echo "============================================="
    echo " Checking Docker Environment"
    echo "============================================="
    
    "$SCRIPT_DIR/runtime-doctor.sh" --docker
    
    press_any_key
    validation_menu
}

validate_configs() {
    clear
    echo "============================================="
    echo " Validating Configurations"
    echo "============================================="
    
    "$SCRIPT_DIR/runtime-doctor.sh" --config
    
    press_any_key
    validation_menu
}

# Security functions
apply_security_hardening() {
    clear
    echo "============================================="
    echo " Applying Security Hardening"
    echo "============================================="
    
    "$SCRIPT_DIR/security-harden.sh" --apply
    
    echo "Security hardening applied!"
    press_any_key
    security_menu
}

check_security_status() {
    clear
    echo "============================================="
    echo " Checking Security Status"
    echo "============================================="
    
    "$SCRIPT_DIR/security-harden.sh" --check
    
    press_any_key
    security_menu
}

reset_security() {
    clear
    echo "============================================="
    echo " Reset Security Settings"
    echo "============================================="
    echo "WARNING: This will reset security settings to defaults!"
    read -rp "Are you sure? [y/N]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/security-harden.sh" --reset
        echo "Security settings reset!"
    fi
    press_any_key
    security_menu
}

# Monitoring functions
view_runtime_logs() {
    clear
    echo "============================================="
    echo " Runtime Logs"
    echo "============================================="
    
    tail -f "$LOG_DIR/runtime.log" || echo "No logs found"
}

view_agent_logs() {
    clear
    echo "============================================="
    echo " Agent Logs"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to view logs: " agent_id
    
    tail -f "$LOG_DIR/$agent_id.log" 2>/dev/null || echo "No logs found for $agent_id"
    press_any_key
    monitoring_menu
}

check_system_health() {
    clear
    echo "============================================="
    echo " System Health Check"
    echo "============================================="
    
    echo "Docker Containers:"
    docker ps
    echo "\nDisk Usage:"
    df -h
    echo "\nMemory Usage:"
    free -h
    
    press_any_key
    monitoring_menu
}

# Crew management functions
create_crew() {
    clear
    echo "============================================="
    echo " Create New Crew"
    echo "============================================="
    
    list_agents
    read -rp "Enter crew name (e.g., dev-team): " crew_name
    read -rp "Enter agent IDs separated by space (e.g., agent1 agent2 agent3): " agents
    
    echo "Creating crew $crew_name with agents: $agents..."
    "$SCRIPT_DIR/crew-create.sh" "$crew_name" $agents
    
    echo "Crew $crew_name created successfully!"
    press_any_key
    crew_menu
}

join_crew() {
    clear
    echo "============================================="
    echo " Join Crew"
    echo "============================================="
    
    list_crews
    read -rp "Enter crew name: " crew_name
    list_agents
    read -rp "Enter agent ID to add: " agent_id
    
    echo "Adding $agent_id to crew $crew_name..."
    "$SCRIPT_DIR/crew-join.sh" "$crew_name" "$agent_id"
    
    echo "Agent $agent_id added to crew $crew_name!"
    press_any_key
    crew_menu
}

leave_crew() {
    clear
    echo "============================================="
    echo " Leave Crew"
    echo "============================================="
    
    list_crews
    read -rp "Enter crew name: " crew_name
    list_agents
    read -rp "Enter agent ID to remove: " agent_id
    
    echo "Removing $agent_id from crew $crew_name..."
    "$SCRIPT_DIR/crew-leave.sh" "$crew_name" "$agent_id"
    
    echo "Agent $agent_id removed from crew $crew_name!"
    press_any_key
    crew_menu
}

list_crews() {
    echo "Available crews:"
    if [ -d "$RUNTIME_DIR/crews" ]; then
        ls -1 "$RUNTIME_DIR/crews" 2>/dev/null || echo "No crews found"
    else
        echo "No crews found"
    fi
    echo "---------------------------------------------"
}

start_crew() {
    clear
    echo "============================================="
    echo " Start Crew"
    echo "============================================="
    
    list_crews
    read -rp "Enter crew name to start: " crew_name
    
    echo "Starting crew $crew_name..."
    "$SCRIPT_DIR/crew-start.sh" "$crew_name"
    
    echo "Crew $crew_name started!"
    press_any_key
    crew_menu
}

monitor_crew() {
    clear
    echo "============================================="
    echo " Monitor Crew"
    echo "============================================="
    
    list_crews
    read -rp "Enter crew name to monitor: " crew_name
    
    echo "Monitoring crew $crew_name (Ctrl+C to exit)..."
    "$SCRIPT_DIR/crew-monitor.sh" "$crew_name"
}

dissolve_crew() {
    clear
    echo "============================================="
    echo " Dissolve Crew"
    echo "============================================="
    echo "WARNING: This will stop all agents in the crew!"
    
    list_crews
    read -rp "Enter crew name to dissolve: " crew_name
    read -rp "Are you sure? [y/N]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "Dissolving crew $crew_name..."
        "$SCRIPT_DIR/crew-dissolve.sh" "$crew_name"
        echo "Crew $crew_name dissolved!"
    fi
    press_any_key
    crew_menu
}

# Configuration functions

# Configuration functions
edit_runtime_config() {
    clear
    echo "============================================="
    echo " Edit Runtime Configuration"
    echo "============================================="
    
    nano "$CONFIG_DIR/runtime.yaml"
    
    press_any_key
    config_menu
}

edit_agent_config() {
    clear
    echo "============================================="
    echo " Edit Agent Configuration"
    echo "============================================="
    
    list_agents
    read -rp "Enter agent ID to configure: " agent_id
    
    nano "$AGENTS_DIR/$agent_id/config.yaml" 2>/dev/null || echo "Agent not found"
    
    press_any_key
    config_menu
}

view_config() {
    clear
    echo "============================================="
    echo " Current Configuration"
    echo "============================================="
    
    echo "Runtime Configuration:"
    cat "$CONFIG_DIR/runtime.yaml" 2>/dev/null || echo "No runtime config found"
    
    echo "\nAvailable Agents:"
    list_agents
    
    press_any_key
    config_menu
}

# Helper function
press_any_key() {
    read -n 1 -s -r -p "Press any key to continue..."
    echo
}

# Initialize runtime
initialize_runtime() {
    echo "Initializing OpenClaw Runtime..."
    
    # Create default config if it doesn't exist
    if [ ! -f "$CONFIG_DIR/runtime.yaml" ]; then
        cat > "$CONFIG_DIR/runtime.yaml" <<EOL
# OpenClaw Runtime Configuration
runtime:
  gateway:
    port: 18789
    token: "$(generate_random_token)"
  agents:
    default_model: "ollama/qwen3:0.6b"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
EOL
    fi
    
    # Create docker-compose.yml if it doesn't exist
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        cat > "$DOCKER_COMPOSE_FILE" <<EOL
version: "3.9"

services:
  openclaw-gateway:
    image: openclaw/gateway:latest
    container_name: openclaw-gateway
    ports:
      - "18789:18789"
    volumes:
      - ~/.openclaw:/root/.openclaw
    networks:
      - agents_net
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:18789/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
EOL
    fi
    
    echo "Runtime initialized!"
}

# Main execution
if [ ! -f "$CONFIG_DIR/runtime.yaml" ] || [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    initialize_runtime
fi

main_menu

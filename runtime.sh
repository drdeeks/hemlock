#!/bin/bash
# =============================================================================
# OpenClaw/Hermes Runtime Orchestrator
# 
# Orchestrates:
#   - Agent management (create, update, finalize)
#   - Crew management (create, activate, deactivate, list)
#   - Backup and restore operations
#   - Tool injection (memory context)
#   - Plugin integration
# =============================================================================

set -euo pipefail

# Root directory
RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/crews"
PLUGINS_DIR="$RUNTIME_ROOT/plugins"
CONFIG_DIR="$RUNTIME_ROOT/config"
DOCKER_DIR="$RUNTIME_ROOT/docker"

# Ensure scripts directory exists
mkdir -p "$SCRIPTS_DIR"

# Load common utilities if available
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
fi

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
${GREEN}OpenClaw/Hermes Runtime Orchestrator${NC}

Orchestrates agent management, crew management, backup, and tool injection.

Usage: $0 <command> [options]

${BLUE}Commands:${NC}
  # Agent Management
  create-agents         Create agent configurations from templates
  delete-agent <id>     Delete an agent and all its files
  finalize-agents       Update and finalize existing agents
  list-agents           List all agents
  
  # Crew Management  
  create-crew <name>    Create a new crew with blueprints and configurations
  activate-crew <name>  Activate a crew for operations
  deactivate-crew <name> Deactivate a crew
  list-crews            List all crews
  
  # Backup Management
  backup                Run backup (interactive)
  restore               Restore from backup
  backup-status         Show backup status
  backup-init           Initialize backup configuration
  backup-validate       Validate backup integrity
  validate-modules      Verify agents can download modules
  
  # Tool Injection
  inject-memory <agent> Inject memory context for an agent (SOUL, USER, IDENTITY, MEMORY, AGENTS, daily memory)
  inject-all-memory     Inject memory for all agents
  
  # System
  setup                 First-time setup
  update                Update all agents and crews
  status                Show system status
  self-check            Run system diagnostics
  
  # Plugin Management
  list-plugins          List available plugins
  enable-plugin <name>  Enable a plugin
  disable-plugin <name> Disable a plugin

${BLUE}Options:${NC}
  --help, -h            Show this help
  --quiet, -q         Suppress output
  --verbose, -v        Verbose output
  --dry-run            Test without making changes
  --force, -f         Force operations

${BLUE}Examples:${NC}
  $0 setup
  $0 create-crew my-team --template project-manager --agents agent1,agent2
  $0 create-agents
  $0 finalize-agents
  $0 inject-memory my-agent
  $0 backup --full --compress
  $0 backup-status
  $0 list-crews
  $0 status
  $0 self-check

${BLUE}_PRIMARY AGENTS:${NC}
  Use create_agents.py and finalize_agents.py from plugins/crews/project-manager/
  as references for agent creation workflows.

EOF
    exit 0
}

# =============================================================================
# AGENT MANAGEMENT
# =============================================================================

list_agents() {
    log "Agent Management - List Agents"
    log "=============================="
    echo ""
    
    if [[ ! -d "$AGENTS_DIR" ]]; then
        log "No agents directory found"
        return 0
    fi
    
    local total=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir" ]]; then
            total=$((total + 1))
            local agent_id=$(basename "$agent_dir")
            
            # Check for config
            local has_config=false
            if [[ -f "$agent_dir/agent.json" ]] || [[ -f "$agent_dir/config.yaml" ]]; then
                has_config=true
            fi
            
            # Check for memory files
            local data_dir="$agent_dir/data"
            local has_memory=false
            if [[ -d "$data_dir" ]]; then
                for mf in SOUL.md USER.md IDENTITY.md MEMORY.md AGENTS.md; do
                    if [[ -f "$data_dir/$mf" ]]; then
                        has_memory=true
                        break
                    fi
                done
            fi
            
            # Check for injection
            local has_injection=false
            if [[ -d "$agent_dir/tools" ]]; then
                if [[ -f "$agent_dir/tools/memory-context.md" ]]; then
                    has_injection=true
                fi
            fi
            
            # Check config files
            local config_files="none"
            if [[ -d "$agent_dir/config" ]]; then
                config_files=$(ls "$agent_dir/config" | head -3 | tr '\n' ',' | sed 's/,$//')
            fi
            
            # Status icons
            local status=""
            [[ "$has_config" == true ]] && status="${status}CFG "
            [[ "$has_memory" == true ]] && status="${status}MEM "
            [[ "$has_injection" == true ]] && status="${status}INJ"
            [[ "$status" == "" ]] && status="NONE"
            
            printf "  %-30s | %-10s | %s\n" "$agent_id" "$status" "$config_files"
        fi
    done
    
    echo ""
    log "Total: $total agents"
}

delete_agent() {
    local agent_id="$1"
    shift
    
    if [[ -z "$agent_id" ]]; then
        error "Agent ID is required. Usage: $0 delete-agent <agent_id> [--force]"
    fi
    
    local delete_script="$SCRIPTS_DIR/agent-delete.sh"
    
    if [[ ! -f "$delete_script" ]]; then
        error "Delete script not found: $delete_script"
    fi
    
    # Pass all arguments to delete script
    exec "$delete_script" --id "$agent_id" "$@"
}

create_agents_from_plugin() {
    log "Agent Management - Create from Plugin"
    log "======================================"
    echo ""
    
    local plugin_script="$PLUGINS_DIR/crews/project-manager/example_create_agents.py"
    
    if [[ ! -f "$plugin_script" ]]; then
        error "Plugin script not found: $plugin_script"
    fi
    
    log "Using create_agents.py from plugins/crews/project-manager/"
    log "This will generate:"
    log "  - Active agent directory with starter agent"
    log "  - Archive directory with all other agents"
    log "  - Rules directory with agent rules"
    log "  - Envs directory with environment files"
    log "  - Templates directory with blank template"
    echo ""
    
    # Check if Python is available
    if ! command -v python3 &>/dev/null; then
        error "Python3 not found. Please install Python 3."
    fi
    
    # Run the script
    cd "$RUNTIME_ROOT"
    log "Running: python3 $plugin_script"
    python3 "$plugin_script"
    cd - >/dev/null
    
    success "Agents created successfully from plugin template"
    log "Next step: Run finalize_agents.py to add workflows and references"
}

finalize_agents_from_plugin() {
    log "Agent Management - Finalize from Plugin"
    log "======================================="
    echo ""
    
    local plugin_script="$PLUGINS_DIR/crews/project-manager/example_finalize_agents.py"
    
    if [[ ! -f "$plugin_script" ]]; then
        error "Plugin script not found: $plugin_script"
    fi
    
    log "Using finalize_agents.py from plugins/crews/project-manager/"
    log "This will:"
    log "  - Update ALL existing agent JSONs"
    log "  - Enforce category-locked, purpose-descriptive names"
    log "  - Align primary/backup models"
    log "  - Ensure correct file paths for env/rules"
    log "  - Keep only ONE starter agent in ./agents/active"
    log "  - Move extras to ./agents/archive"
    log "  - Create workflows (agent/, crew/, global/)"
    log "  - Add workflow references to agent JSONs"
    echo ""
    
    # Check if Python is available
    if ! command -v python3 &>/dev/null; then
        error "Python3 not found. Please install Python 3."
    fi
    
    # Run the script
    cd "$RUNTIME_ROOT"
    log "Running: python3 $plugin_script"
    python3 "$plugin_script"
    cd - >/dev/null
    
    success "Agents finalized successfully from plugin"
    log "Next step: Run tool injection to inject memory context"
}

# =============================================================================
# CREW MANAGEMENT
# =============================================================================

create_crew() {
    local crew_name="$1"
    shift
    
    log "Crew Management - Create Crew"
    log "============================"
    echo ""
    
    if [[ -z "$crew_name" ]]; then
        error "Crew name is required. Usage: $0 create-crew <name> [options]"
    fi
    
    local create_crew_script="$SCRIPTS_DIR/create_crew.py"
    
    if [[ ! -f "$create_crew_script" ]]; then
        error "Create crew script not found: $create_crew_script"
    fi
    
    # Run the Python script
    cd "$RUNTIME_ROOT"
    python3 "$create_crew_script" "$crew_name" "$@"
    cd - >/dev/null
}

list_crews() {
    log "Crew Management - List Crews"
    log "============================"
    echo ""
    
    if [[ ! -d "$CREWS_DIR" ]]; then
        log "No crews directory found"
        return 0
    fi
    
    local total=0
    for crew_dir in "$CREWS_DIR"/*/; do
        if [[ -d "$crew_dir" ]]; then
            total=$((total + 1))
            local crew_name=$(basename "$crew_dir")
            
            # Check for crew.json
            local has_config=false
            local has_agents=false
            local agent_count=0
            local crew_id=""
            local template=""
            
            if [[ -f "$crew_dir/crew.json" ]]; then
                has_config=true
                crew_id=$(grep -o '"crew_id"[^,]*' "$crew_dir/crew.json" | head -1 | cut -d: -f2 | tr -d '" ')
                template=$(grep -o '"template"[^,]*' "$crew_dir/crew.json" | head -1 | cut -d: -f2 | tr -d '" ')
            fi
            
            # Check for blueprints
            if [[ -d "$crew_dir/blueprints" ]]; then
                has_agents=true
                agent_count=$(ls "$crew_dir/blueprints"/*.json 2>/dev/null | wc -l)
            fi
            
            # Check for workflows
            local has_workflows=false
            if [[ -d "$crew_dir/workflows" ]]; then
                has_workflows=true
            fi
            
            local crew_id_display="${crew_id:-N/A}"
            local template_display="${template:-custom}"
            
            printf "  %-20s | ID: %-36s | Template: %-15s | Agents: %d | WF: %s\n" \
                "$crew_name" "$crew_id_display" "$template_display" "$agent_count" "$([[ "$has_workflows" == true ]] && echo "YES" || echo "NO")"
        fi
    done
    
    echo ""
    log "Total: $total crews"
}

activate_crew() {
    local crew_name="$1"
    
    if [[ -z "$crew_name" ]]; then
        error "Crew name is required. Usage: $0 activate-crew <name>"
    fi
    
    log "Crew Management - Activate Crew"
    log "==============================="
    echo ""
    
    local crew_dir="$CREWS_DIR/$crew_name"
    
    if [[ ! -d "$crew_dir" ]]; then
        error "Crew not found: $crew_name"
    fi
    
    log "Activating crew: $crew_name"
    log "Crew directory: $crew_dir"
    
    # In a real implementation, this would connect to Hermes
    # For now, we'll just validate and show what would happen
    
    if [[ -f "$crew_dir/crew.json" ]]; then
        log "Crew configuration found"
        
        # Get agent count
        local agent_count=$(python3 -c "
import json
try:
    with open('$crew_dir/crew.json', 'r') as f:
        data = json.load(f)
    print(len(data.get('agents', [])))
except:
    print(0)
" 2>/dev/null || echo "0")
        
        log "  Agents: $agent_count"
        
        # Check workflows
        if [[ -d "$crew_dir/workflows" ]]; then
            local wf_count=$(ls "$crew_dir/workflows"/*.json 2>/dev/null | wc -l)
            log "  Workflows: $wf_count"
        fi
    fi
    
    log ""
    log "_to activate with hermes, run:"
    log "  cd $crew_dir"
    log "  hermes crew activate --config crew.json"
    
    success "Crew $crew_name validated and ready for activation"
    warn "Note: Actual activation requires Hermes CLI"
}

deactivate_crew() {
    local crew_name="$1"
    
    if [[ -z "$crew_name" ]]; then
        error "Crew name is required. Usage: $0 deactivate-crew <name>"
    fi
    
    log "Crew Management - Deactivate Crew"
    log "=================================="
    echo ""
    
    local crew_dir="$CREWS_DIR/$crew_name"
    
    if [[ ! -d "$crew_dir" ]]; then
        error "Crew not found: $crew_name"
    fi
    
    log "Deactivating crew: $crew_name"
    
    # In a real implementation, this would disconnect from Hermes
    log "Crew deactivation would be handled by Hermes CLI"
    log ""
    log "To deactivate with hermes, run:"
    log "  hermes crew deactivate $crew_name"
    
    success "Crew $crew_name deactivation initiated"
}

# =============================================================================
# BACKUP MANAGEMENT
# =============================================================================

backup_command() {
    local backup_script="$SCRIPTS_DIR/backup-interactive.sh"
    
    if [[ ! -f "$backup_script" ]]; then
        error "Backup script not found: $backup_script"
    fi
    
    # Forward all arguments to backup-interactive.sh
    # Supports: --mode plan-history|docker-full|combo
    #           --no-exclude-modules, --no-exclude-bloat
    #           --full, --destination, --type, --compress, --encrypt, etc.
    exec "$backup_script" "$@"
}

# Validate module download capabilities
validate_modules() {
    local backup_script="$SCRIPTS_DIR/backup-interactive.sh"
    
    if [[ ! -f "$backup_script" ]]; then
        error "Backup script not found: $backup_script"
    fi
    
    exec "$backup_script" validate --check-modules
}

# =============================================================================
# TOOL INJECTION
# =============================================================================

inject_memory_single() {
    local agent_id="$1"
    shift
    
    if [[ -z "$agent_id" ]]; then
        error "Agent ID is required. Usage: $0 inject-memory <agent_id> [options]"
    fi
    
    local inject_script="$SCRIPTS_DIR/tool-inject-memory.sh"
    
    if [[ ! -f "$inject_script" ]]; then
        error "Inject script not found: $inject_script"
    fi
    
    # Forward all arguments
    exec "$inject_script" "$agent_id" "$@"
}

inject_all_memory() {
    local inject_script="$SCRIPTS_DIR/tool-inject-memory.sh"
    
    if [[ ! -f "$inject_script" ]]; then
        error "Inject script not found: $inject_script"
    fi
    
    exec "$inject_script" --all "$@"
}

# =============================================================================
# PLUGIN MANAGEMENT
# =============================================================================

list_plugins() {
    log "Plugin Management - List Plugins"
    log "================================="
    echo ""
    
    if [[ ! -d "$PLUGINS_DIR" ]]; then
        log "No plugins directory found"
        return 0
    fi
    
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        if [[ -d "$plugin_dir" ]]; then
            local plugin_name=$(basename "$plugin_dir")
            local plugin_yaml="$plugin_dir/plugin.yaml"
            local readme="$plugin_dir/README.md"
            local description=""
            
            if [[ -f "$plugin_yaml" ]]; then
                description=$(grep -m1 "^description:" "$plugin_yaml" 2>/dev/null | cut -d: -f2- | xargs || echo "")
            elif [[ -f "$readme" ]]; then
                description=$(head -1 "$readme" | sed 's/# //' || echo "")
            fi
            
            # Count files
            local file_count=$(find "$plugin_dir" -type f 2>/dev/null | wc -l)
            local dir_count=$(find "$plugin_dir" -type d 2>/dev/null | wc -l)
            dir_count=$((dir_count - 1))  # Subtract the root dir
            
            # Check for Python plugin
            local has_python=false
            if [[ -f "$plugin_dir/__init__.py" ]]; then
                has_python=true
            fi
            
            # Check for shell scripts
            local has_shell=false
            if ls "$plugin_dir"/*.sh &>/dev/null; then
                has_shell=true
            fi
            
            local type=""
            [[ "$has_python" == true ]] && type="Python "
            [[ "$has_shell" == true ]] && type="${type}Shell "
            [[ "$type" == "" ]] && type="Data"
            
            printf "  %-15s | %-40s | %s | %d dirs, %d files\n" \
                "$plugin_name" "${description:-No description}" "$type" "$dir_count" "$file_count"
        fi
    done
}

enable_plugin() {
    local plugin_name="$1"
    
    if [[ -z "$plugin_name" ]]; then
        error "Plugin name is required. Usage: $0 enable-plugin <name>"
    fi
    
    log "Plugin Management - Enable Plugin"
    log "================================="
    
    local plugin_dir="$PLUGINS_DIR/$plugin_name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        error "Plugin not found: $plugin_name"
    fi
    
    log "Plugin already available at: $plugin_dir"
    log "Plugins are automatically enabled if present in the plugins directory"
    success "Plugin $plugin_name is enabled"
}

disable_plugin() {
    local plugin_name="$1"
    
    if [[ -z "$plugin_name" ]]; then
        error "Plugin name is required. Usage: $0 disable-plugin <name>"
    fi
    
    log "Plugin Management - Disable Plugin"
    log "=================================="
    
    local plugin_dir="$PLUGINS_DIR/$plugin_name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        error "Plugin not found: $plugin_name"
    fi
    
    warn "To disable, remove from plugins directory:"
    log "  mv $plugin_dir ${plugin_dir}.disabled"
    warn "Note: This only disables loading, files remain on disk"
}

# =============================================================================
# SYSTEM OPERATIONS
# =============================================================================

setup_system() {
    log "System Setup"
    log "============"
    echo ""
    
    # Ensure all directories exist
    log "Creating directory structure..."
    
    local dirs=(
        "$AGENTS_DIR"
        "$CREWS_DIR"
        "$CONFIG_DIR"
        "$PLUGINS_DIR"
        "$DOCKER_DIR"
        "$SCRIPTS_DIR"
        "$AGENTS_DIR/active"
        "$AGENTS_DIR/archive"
        "$AGENTS_DIR/templates"
        "$AGENTS_DIR/rules"
        "$AGENTS_DIR/envs"
        "$AGENTS_DIR/workflow/agent"
        "$AGENTS_DIR/workflow/crew"
        "$AGENTS_DIR/workflow/global"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "  Created: $dir"
    done
    
    # Check for existing agents
    local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    agent_count=$((agent_count - 1))  # Subtract the root
    
    if [[ $agent_count -lt 2 ]]; then
        log ""
        log "No agents found. Suggested next steps:"
        log "  1. Copy agents from plugins: cp -r $PLUGINS_DIR/crews/project-manager/*.py $RUNTIME_ROOT/"
        log "  2. Run: $0 create-agents-from-plugin"
        log "  3. Or create custom agents manually in $AGENTS_DIR/"
    fi
    
    # Check for existing crews
    local crew_count=$(find "$CREWS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    crew_count=$((crew_count - 1))
    
    if [[ $crew_count -lt 1 ]]; then
        log ""
        log "No crews found. Suggested next steps:"
        log "  1. Copy crew templates from plugins: cp -r $PLUGINS_DIR/crews/project-manager/templates $CREWS_DIR/"
        log "  2. Create a crew: $0 create-crew my-team"
    fi
    
    # Check for backup configuration
    local backup_config="$CONFIG_DIR/backup-config.yaml"
    if [[ ! -f "$backup_config" ]]; then
        log ""
        log "Backup not configured. Suggested next step:"
        log "  Run: $0 backup-init"
    fi
    
    # Check for tool injection
    log ""
    log "Tool Injection:"
    log "  Memory injection script: $SCRIPTS_DIR/tool-inject-memory.sh"
    if [[ -f "$SCRIPTS_DIR/tool-inject-memory.sh" ]]; then
        log "  Status: Available"
        log "  Run: $0 inject-all-memory"
    else
        log "  Status: Not found (will be created on first run)"
    fi
    
    success "System setup complete"
}

update_system() {
    log "System Update"
    log "============"
    echo ""
    
    # Update all agents with memory injection
    log "Updating all agents with memory injection..."
    inject_all_memory --force
    
    # Finalize agents
    log ""
    log "Finalizing all agents..."
    finalize_agents_from_plugin
    
    # Sync plugins to agents
    log ""
    log "Syncing plugins..."
    
    # Check backup
    log ""
    log "Checking backup..."
    local backup_script="$SCRIPTS_DIR/backup-interactive.sh"
    if [[ -f "$backup_script" ]]; then
        "$backup_script" status
    fi
    
    success "System update complete"
}

system_status() {
    log "System Status"
    log "============"
    echo ""
    
    # Count agents
    local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    agent_count=$((agent_count - 1))
    
    local agents_with_memory=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir/data" ]] && \
           ( [[ -f "$agent_dir/data/SOUL.md" ]] || \
             [[ -f "$agent_dir/data/USER.md" ]] || \
             [[ -f "$agent_dir/data/IDENTITY.md" ]] ); then
            agents_with_memory=$((agents_with_memory + 1))
        fi
    done
    
    log "Agents:"
    log "  Total: $agent_count"
    log "  With memory: $agents_with_memory"
    if [[ $agent_count -gt 0 ]]; then
        local pct=$((agents_with_memory * 100 / agent_count))
        log "  Memory coverage: ${pct}%"
    fi
    
    # Count crews
    local crew_count=$(find "$CREWS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    crew_count=$((crew_count - 1))
    log ""
    log "Crews:"
    log "  Total: $crew_count"
    
    # Check backup
    local backup_config="$CONFIG_DIR/backup-config.yaml"
    log ""
    log "Backup:"
    if [[ -f "$backup_config" ]]; then
        local last_backup=$(cat "$CONFIG_DIR/../.last-backup" 2>/dev/null || echo "never")
        log "  Configured: Yes"
        log "  Last backup: $last_backup"
    else
        log "  Configured: No"
        log "  Run: $0 backup-init"
    fi
    
    # Check plugins
    log ""
    log "Plugins:"
    local plugin_count=$(find "$PLUGINS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    plugin_count=$((plugin_count - 1))
    log "  Total: $plugin_count"
    
    # List plugin types
    local has_backup=false
    local has_tool_enforcement=false
    local has_crews=false
    
    [[ -d "$PLUGINS_DIR/backup-protocol" ]] && has_backup=true
    [[ -d "$PLUGINS_DIR/tool-enforcement" ]] && has_tool_enforcement=true
    [[ -d "$PLUGINS_DIR/crews" ]] && has_crews=true
    
    log "  Types: $([[ "$has_backup" == true ]] && echo "backup" || true)$([[ "$has_crews" == true ]] && [[ "$has_backup" == true ]] && echo "," || true)$([[ "$has_crews" == true ]] && echo "crews" || true)$([[ "$has_tool_enforcement" == true ]] && [[ "$has_crews" == true ]] && echo "," || true)$([[ "$has_tool_enforcement" == true ]] && echo "tool-enforcement" || true)"
    
    # Check memory injection
    log ""
    log "Memory Injection:"
    local injected_agents=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir/tools" ]] && [[ -f "$agent_dir/tools/memory-context.md" ]]; then
            injected_agents=$((injected_agents + 1))
        fi
    done
    log "  Injected: $injected_agents agents"
    
    if [[ $agent_count -gt 0 ]]; then
        local pct=$((injected_agents * 100 / agent_count))
        log "  Coverage: ${pct}%"
    fi
    
    # Overall health
    log ""
    log "Overall System Health:"
    
    local health_score=0
    local max_score=5
    
    # Agents exist
    [[ $agent_count -gt 0 ]] && ((health_score++)) && log "  ✓ Agents configured"
    
    # Agents have memory
    [[ $agents_with_memory -gt 0 ]] && ((health_score++)) && log "  ✓ Agents have memory files"
    
    # Crews exist
    [[ $crew_count -gt 0 ]] && ((health_score++)) && log "  ✓ Crews configured"
    
    # Backup configured
    [[ -f "$backup_config" ]] && ((health_score++)) && log "  ✓ Backup configured"
    
    # Memory injection active
    [[ $injected_agents -gt 0 ]] && ((health_score++)) && log "  ✓ Memory injection active"
    
    local health_pct=$((health_score * 100 / max_score))
    
    if [[ $health_score -eq $max_score ]]; then
        success "System health: ${health_pct}% (Optimal)"
    elif [[ $health_score -ge 3 ]]; then
        log "System health: ${health_pct}% (Good)"
    else
        warn "System health: ${health_pct}% (Needs attention)"
    fi
}

self_check() {
    log "System Self-Check"
    log "================="
    echo ""
    
    local passed=0
    local failed=0
    
    # Check 1: Directory structure
    log "Checking directory structure..."
    local dirs=("$AGENTS_DIR" "$CREWS_DIR" "$CONFIG_DIR" "$PLUGINS_DIR" "$SCRIPTS_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            passed=$((passed + 1))
            log "  ✓ $dir exists"
        else
            failed=$((failed + 1))
            log "  ✗ $dir missing"
        fi
    done
    
    # Check 2: Scripts are available
    log ""
    log "Checking critical scripts..."
    local scripts=(
        "$SCRIPTS_DIR/backup-interactive.sh"
        "$SCRIPTS_DIR/tool-inject-memory.sh"
        "$SCRIPTS_DIR/create_crew.py"
    )
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            passed=$((passed + 1))
            log "  ✓ $(basename "$script") exists"
        else
            warn "  ✗ $(basename "$script") missing"
            failed=$((failed + 1))
        fi
    done
    
    # Check 3: Plugins
    log ""
    log "Checking plugins..."
    if [[ -d "$PLUGINS_DIR" ]]; then
        local plugin_found=false
        for plugin_dir in "$PLUGINS_DIR"/*/; do
            if [[ -d "$plugin_dir" ]]; then
                plugin_found=true
                passed=$((passed + 1))
                break
            fi
        done
        if [[ "$plugin_found" == false ]]; then
            warn "  ✗ No plugins found"
            failed=$((failed + 1))
        fi
    else
        warn "  ✗ Plugins directory missing"
        failed=$((failed + 1))
    fi
    
    # Check 4: Agents
    log ""
    log "Checking agents..."
    if [[ -d "$AGENTS_DIR" ]]; then
        local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
        agent_count=$((agent_count - 1))
        if [[ $agent_count -gt 0 ]]; then
            passed=$((passed + 1))
            log "  ✓ $agent_count agents found"
        else
            warn "  ✗ No agents found"
            failed=$((failed + 1))
        fi
    fi
    
    # Check 5: Memory files
    log ""
    log "Checking memory files..."
    local mem_agents=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir/data" ]] && \
           ( [[ -f "$agent_dir/data/SOUL.md" ]] || \
             [[ -f "$agent_dir/data/USER.md" ]] || \
             [[ -f "$agent_dir/data/IDENTITY.md" ]] ); then
            mem_agents=$((mem_agents + 1))
        fi
    done
    if [[ $mem_agents -gt 0 ]]; then
        passed=$((passed + 1))
        log "  ✓ $mem_agents agents have memory files"
    else
        warn "  ✗ No memory files found"
        failed=$((failed + 1))
    fi
    
    # Check 6: Python available
    log ""
    log "Checking dependencies..."
    if command -v python3 &>/dev/null; then
        passed=$((passed + 1))
        log "  ✓ Python 3 available"
    else
        warn "  ✗ Python 3 not found"
        failed=$((failed + 1))
    fi
    
    # Check 7: Git available
    if command -v git &>/dev/null; then
        passed=$((passed + 1))
        log "  ✓ Git available"
    else
        warn "  ✗ Git not found"
        failed=$((failed + 1))
    fi
    
    # Check 8: Docker available (optional)
    if command -v docker &>/dev/null; then
        passed=$((passed + 1))
        log "  ✓ Docker available"
    else
        log "  - Docker not found (optional)"
    fi
    
    # Summary
    echo ""
    log "Self-Check Summary:"
    local total=$((passed + failed))
    log "  Passed: $passed/$total"
    log "  Failed: $failed/$total"
    
    if [[ $failed -eq 0 ]]; then
        success "All checks passed!"
    elif [[ $failed -le 2 ]]; then
        log "Most checks passed. See warnings above."
    else
        warn "Several checks failed. Please address the issues above."
    fi
}

# =============================================================================
# ARGUMENT PARSING AND ROUTING
# =============================================================================

# Parse arguments
COMMAND=""
VERBOSE=false
QUIET=false
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        create-agents)
            COMMAND="create-agents"
            shift
            ;;
        create-agents-from-plugin)
            COMMAND="create-agents-from-plugin"
            shift
            ;;
        finalize-agents)
            COMMAND="finalize-agents"
            shift
            ;;
        finalize-agents-from-plugin)
            COMMAND="finalize-agents-from-plugin"
            shift
            ;;
        list-agents)
            COMMAND="list-agents"
            shift
            ;;
        delete-agent)
            COMMAND="delete-agent"
            break
            ;;
        create-crew)
            COMMAND="create-crew"
            break
            ;;
        activate-crew)
            COMMAND="activate-crew"
            break
            ;;
        deactivate-crew)
            COMMAND="deactivate-crew"
            break
            ;;
        list-crews)
            COMMAND="list-crews"
            shift
            ;;
        backup)
            COMMAND="backup"
            break
            ;;
        backup-init)
            COMMAND="backup-init"
            break
            ;;
        backup-status)
            COMMAND="backup-status"
            break
            ;;
        backup-validate)
            COMMAND="backup-validate"
            break
            ;;
        validate-modules)
            COMMAND="validate-modules"
            break
            ;;
        restore)
            COMMAND="restore"
            break
            ;;
        inject-memory)
            COMMAND="inject-memory"
            shift
            ;;
        inject-all-memory)
            COMMAND="inject-all-memory"
            shift
            shift
            ;;
        setup)
            COMMAND="setup"
            shift
            ;;
        update)
            COMMAND="update"
            shift
            ;;
        status|system-status)
            COMMAND="system-status"
            shift
            ;;
        self-check)
            COMMAND="self-check"
            shift
            ;;
        list-plugins)
            COMMAND="list-plugins"
            shift
            ;;
        enable-plugin)
            COMMAND="enable-plugin"
            break
            ;;
        disable-plugin)
            COMMAND="disable-plugin"
            break
            shift
            ;;
        *)
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"
                shift
            fi
            ;;
    esac
done

# =============================================================================
# COMMAND ROUTING
# =============================================================================

case "$COMMAND" in
    "")
        usage
        ;;
    create-agents|create-agents-from-plugin)
        create_agents_from_plugin
        ;;
    finalize-agents|finalize-agents-from-plugin)
        finalize_agents_from_plugin
        ;;
    list-agents)
        list_agents
        ;;
    delete-agent)
        shift
        delete_agent "$@"
        ;;
    create-crew)
        create_crew "$@"
        ;;
    activate-crew)
        activate_crew "$@"
        ;;
    deactivate-crew)
        deactivate_crew "$@"
        ;;
    list-crews)
        list_crews
        ;;
    backup)
        backup_command "$@"
        ;;
    backup-init)
        backup_command init
        ;;
    backup-status)
        backup_command status
        ;;
    backup-validate)
        backup_command validate
        ;;
    validate-modules)
        validate_modules
        ;;
    restore)
        backup_command restore "$@"
        ;;
    inject-memory)
        inject_memory_single "$@"
        ;;
    inject-all-memory)
        inject_all_memory "$@"
        ;;
    setup)
        setup_system
        ;;
    update)
        update_system
        ;;
    system-status|status)
        system_status
        ;;
    self-check)
        self_check
        ;;
    list-plugins)
        list_plugins
        ;;
    enable-plugin)
        enable_plugin "$@"
        ;;
    disable-plugin)
        disable_plugin "$@"
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        ;;
esac

exit 0

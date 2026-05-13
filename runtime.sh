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

set -uo pipefail

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

# Load common utilities if available — define color fallbacks first
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null || true
fi

# Ensure log/warn/error/success helpers exist even without lib/common.sh
if ! declare -f log &>/dev/null; then
    log()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
    warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
    error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
    success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }
fi

# =============================================================================
# FIRST-RUN INITIALIZATION
# =============================================================================
FIRST_RUN_FLAG="$RUNTIME_ROOT/.cache/.first_run_completed"

# Check if first-run initialization is needed
is_first_run() {
    if [[ ! -f "$FIRST_RUN_FLAG" ]]; then
        return 0
    fi
    return 1
}

# Check if system is already initialized with default model
is_initialized() {
    # Check if default model exists
    if [[ -f "$RUNTIME_ROOT/models/gguf/qwen3-0_6b-Q4_K_M.gguf" ]] || \
       [[ -f "$RUNTIME_ROOT/models/gguf/qwen3-0_6b-Q4_K_M.gguf" ]]; then
        return 0
    fi
    
    # Check if first run flag exists
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        return 0
    fi
    
    return 1
}

# Run first-run initialization
run_first_run_initialization() {
    local first_run_script="$SCRIPTS_DIR/system/first-run.sh"
    
    if [[ -f "$first_run_script" ]]; then
        log "Running first-run initialization..."
        log "This will setup Qwen3:0.6B as default model with Llama.cpp"
        echo ""
        bash "$first_run_script" full
        echo ""
    else
        warn "First-run script not found at $first_run_script"
        warn "Falling back to basic setup..."
        setup_system
    fi
}

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
  create-agent          Create a new agent with auto-generated templates
  delete-agent <id>     Delete an agent and all its files
  import-agent          Import an agent from archive or tar
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
  setup                 Basic system setup (legacy)
  initialize            First-time initialization (Qwen3:0.6B + Llama.cpp)
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
  --skip-init          Skip first-run initialization

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

${BLUE}Agent Catalog:${NC}
  Agents are NOT created until you run create-agents + finalize-agents.

EOF
    exit 0
}

main_menu() {
    while true; do
        clear
        echo -e "${BOLD}${BLUE}OpenClaw/Hermes Runtime Orchestrator${NC}"
        echo ""
        echo "  1) Create agents"
        echo "  2) Finalize agents"
        echo "  3) List agents"
        echo "  4) Create crew"
        echo "  5) List crews"
        echo "  6) Backup"
        echo "  7) Restore"
        echo "  8) Self-check"
        echo "  9) Help"
        echo "  0) Exit"
        echo ""
        read -rp "Select an option [0-9]: " choice 2>/dev/null || choice="0"
        case "$choice" in
            1) COMMAND="create-agents"; break ;;
            2) COMMAND="finalize-agents"; break ;;
            3) COMMAND="list-agents"; break ;;
            4) COMMAND="create-crew"; break ;;
            5) COMMAND="list-crews"; break ;;
            6) COMMAND="backup"; break ;;
            7) COMMAND="restore"; break ;;
            8) COMMAND="self-check"; break ;;
            9) usage ;;
            0) exit 0 ;;
            *) echo "Invalid selection."; sleep 1 ;;
        esac
    done
}

# =============================================================================
# AGENT MANAGEMENT
# =============================================================================

list_agents() {
    log "Agent Management - List Agents"
    log "=============================="
    echo ""

    local active_count=0 archive_count=0

    # Active agents
    if [[ -d "$AGENTS_DIR/active" ]]; then
        local active_jsons=("$AGENTS_DIR/active/"*.json)
        if [[ -f "${active_jsons[0]}" ]]; then
            echo -e "  ${GREEN}Active${NC}"
            for jf in "${active_jsons[@]}"; do
                [[ -f "$jf" ]] || continue
                local slug; slug=$(basename "$jf" .json)
                local display; display=$(python3 -c "import json,sys; d=json.load(open('$jf')); print(d.get('display_name',d.get('agent_name','$slug')))" 2>/dev/null || echo "$slug")
                local cat; cat=$(python3 -c "import json,sys; d=json.load(open('$jf')); print(d.get('category','—'))" 2>/dev/null || echo "—")
                local has_rules; has_rules=$( [[ -f "$AGENTS_DIR/rules/${slug}-rules.md" ]] && echo "rules" || echo "—" )
                local has_env; has_env=$( [[ -f "$AGENTS_DIR/envs/${slug}.env" ]] && echo "env" || echo "—" )
                printf "    %-38s | %-36s | %s  %s\n" "$slug" "$cat" "$has_rules" "$has_env"
                active_count=$((active_count + 1))
            done
        else
            echo -e "  ${YELLOW}Active: none (run create-agents to deploy)${NC}"
        fi
    fi

    echo ""

    # Archive agents
    if [[ -d "$AGENTS_DIR/archive" ]]; then
        local archive_jsons=("$AGENTS_DIR/archive/"*.json)
        if [[ -f "${archive_jsons[0]}" ]]; then
            echo -e "  ${BLUE}Archive${NC} (${#archive_jsons[@]} agents — not yet active)"
            for jf in "${archive_jsons[@]}"; do
                [[ -f "$jf" ]] || continue
                local slug; slug=$(basename "$jf" .json)
                local cat; cat=$(python3 -c "import json,sys; d=json.load(open('$jf')); print(d.get('category','—'))" 2>/dev/null || echo "—")
                printf "    %-38s | %s\n" "$slug" "$cat"
                archive_count=$((archive_count + 1))
            done
        else
            echo -e "  ${BLUE}Archive${NC}: none"
        fi
    fi

    echo ""
    log "Active: $active_count  Archive: $archive_count  Total catalog: $((active_count + archive_count))"
    log "To deploy: ./runtime.sh create-agents && ./runtime.sh finalize-agents"
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
    bash "$delete_script" --id "$agent_id" "$@"
}

create_agents_from_plugin() {
    log "Agent Management - Deploy All Agents"
    log "====================================="
    echo ""


    if [[ ! -f "$script" ]]; then
    fi

    if ! command -v python3 &>/dev/null; then
        error "Python3 not found. Please install Python 3."
    fi

    log "Catalog: 27 enterprise agents across 9 categories"
    log "  → 1 starter placed in  agents/active/"
    log "  → 26 agents placed in  agents/archive/"
    log "  → rules files in       agents/rules/"
    log "  → env files in         agents/envs/"
    log "  → blank template in    agents/templates/"
    echo ""

    cd "$RUNTIME_ROOT"
    python3 "$script"
    local rc=$?
    cd - >/dev/null


    success "All 27 agents deployed"
    log "Next step: run finalize-agents to wire workflows and references"
}

finalize_agents_from_plugin() {
    log "Agent Management - Finalize Agents"
    log "==================================="
    echo ""


    if [[ ! -f "$script" ]]; then
    fi

    if ! command -v python3 &>/dev/null; then
        error "Python3 not found. Please install Python 3."
    fi

    log "This will:"
    log "  - Update all agent JSONs in active/ and archive/"
    log "  - Enforce category-locked names and model alignment"
    log "  - Ensure correct env/rules file paths"
    log "  - Keep exactly one starter agent in active/, move extras to archive/"
    log "  - Generate agents/workflow/agent/, crew/, and global/ files"
    log "  - Wire workflow references into every agent JSON"
    echo ""

    cd "$RUNTIME_ROOT"
    python3 "$script"
    local rc=$?
    cd - >/dev/null


    success "Agents finalized — workflows wired"
    log "Next step: inject memory context with inject-all-memory"
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
    bash "$backup_script" "$@"
}

# Validate module download capabilities
validate_modules() {
    local backup_script="$SCRIPTS_DIR/backup-interactive.sh"
    
    if [[ ! -f "$backup_script" ]]; then
        error "Backup script not found: $backup_script"
    fi
    
    bash "$backup_script" validate --check-modules
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
    bash "$inject_script" "$agent_id" "$@"
}

inject_all_memory() {
    local inject_script="$SCRIPTS_DIR/tool-inject-memory.sh"
    
    if [[ ! -f "$inject_script" ]]; then
        error "Inject script not found: $inject_script"
    fi
    
    bash "$inject_script" --all "$@"
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
    local _act _arc
    _act=$(find "$AGENTS_DIR/active"  -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    _arc=$(find "$AGENTS_DIR/archive" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    local agent_count=$(( _act + _arc ))

    if [[ $agent_count -lt 1 ]]; then
        log ""
        log "No agents deployed. To deploy the full catalog run:"
        log "  1. $0 create-agents    — generates all 27 agent files"
        log "  2. $0 finalize-agents  — wires workflows and references"
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
    local _act _arc
    _act=$(find "$AGENTS_DIR/active"  -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    _arc=$(find "$AGENTS_DIR/archive" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    local agent_count=$(( _act + _arc ))

    log "Agents:"
    log "  Catalog total: $agent_count  (active: $_act  archive: $_arc)"
    if [[ $agent_count -eq 0 ]]; then
        log "  → Run: ./runtime.sh create-agents && ./runtime.sh finalize-agents"
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
    
    # Workflow files
    log ""
    log "Workflows:"
    local wf_agent wf_crew wf_global
    wf_agent=$(find  "$AGENTS_DIR/workflow/agent"  -name "*.json" 2>/dev/null | wc -l)
    wf_crew=$(find   "$AGENTS_DIR/workflow/crew"   -name "*.json" 2>/dev/null | wc -l)
    wf_global=$(find "$AGENTS_DIR/workflow/global" -name "*.json" 2>/dev/null | wc -l)
    log "  Agent workflows : $wf_agent"
    log "  Crew workflows  : $wf_crew"
    log "  Global standards: $wf_global"
    if [[ $((wf_agent + wf_crew + wf_global)) -eq 0 ]]; then
        log "  → Run: ./runtime.sh finalize-agents"
    fi

    # Overall health
    log ""
    log "Overall System Health:"

    local health_score=0
    local max_score=4

    # Agents exist
    [[ $agent_count -gt 0 ]] && ((health_score++)) && log "  ✓ Agents deployed"

    # Workflows wired
    [[ $((wf_agent + wf_crew + wf_global)) -gt 0 ]] && ((health_score++)) && log "  ✓ Workflows wired"

    # Crews exist
    [[ $crew_count -gt 0 ]] && ((health_score++)) && log "  ✓ Crews configured"

    # Backup configured
    [[ -f "$backup_config" ]] && ((health_score++)) && log "  ✓ Backup configured"

    local health_pct=$((health_score * 100 / max_score))

    if [[ $health_score -eq $max_score ]]; then
        success "System health: ${health_pct}% (Optimal)"
    elif [[ $health_score -ge 2 ]]; then
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
    local _sc_act _sc_arc _sc_total
    _sc_act=$(find "$AGENTS_DIR/active"  -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    _sc_arc=$(find "$AGENTS_DIR/archive" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    _sc_total=$(( _sc_act + _sc_arc ))
    if [[ $_sc_total -gt 0 ]]; then
        passed=$((passed + 1))
        log "  ✓ $_sc_total agents in catalog (active: $_sc_act  archive: $_sc_arc)"
    else
        warn "  ✗ No agents deployed — run: ./runtime.sh create-agents"
        failed=$((failed + 1))
    fi

    # Check 5: Agent rules/envs
    log ""
    log "Checking agent rules/envs..."
    local rules_count envs_count
    rules_count=$(find "$AGENTS_DIR/rules" -name "*.md"  2>/dev/null | wc -l)
    envs_count=$(find  "$AGENTS_DIR/envs"  -name "*.env" 2>/dev/null | wc -l)
    if [[ $rules_count -gt 0 ]] || [[ $envs_count -gt 0 ]]; then
        passed=$((passed + 1))
        log "  ✓ $rules_count rules files  $envs_count env files"
    else
        warn "  ✗ No rules/env files — run: ./runtime.sh create-agents"
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
# INTERACTIVE MENU SYSTEM
# =============================================================================

_menu_header() {
    clear
    echo ""
    echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}║        HEMLOCK ENTERPRISE AGENT FRAMEWORK                   ║${NC}"
    echo -e "  ${BOLD}║             Interactive Management Console                  ║${NC}"
    echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    _menu_status_line
    echo ""
}

_menu_status_line() {
    local agent_count crew_count docker_st ollama_st
    local _active _archive
    _active=$(find "$AGENTS_DIR/active"  -maxdepth 1 -name "*.json" 2>/dev/null | wc -l || echo 0)
    _archive=$(find "$AGENTS_DIR/archive" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l || echo 0)
    agent_count=$(( _active + _archive ))
    local cfg_crews=0
    [[ -d "$CONFIG_DIR/crews" ]] && cfg_crews=$(find "$CONFIG_DIR/crews" -name "*.yaml" 2>/dev/null | wc -l || echo 0)
    local dir_crews=0
    [[ -d "$CREWS_DIR" ]] && dir_crews=$(find "$CREWS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l || echo 0)
    crew_count=$((dir_crews + cfg_crews))

    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        docker_st="${GREEN}available${NC}"
    else
        docker_st="${YELLOW}unavailable${NC}"
    fi
    if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
        ollama_st="${GREEN}running${NC}"
    else
        ollama_st="${YELLOW}not running${NC}"
    fi
    printf "  Agents: ${BLUE}%d${NC} (active: %d)  Crews: ${BLUE}%d${NC}  Docker: %b  Ollama: %b\n" \
        "$agent_count" "$_active" "$crew_count" "$docker_st" "$ollama_st"
}

_menu_pause() {
    echo ""
    read -rp "  Press Enter to return to menu..." _p 2>/dev/null || true
}

_safe_confirm() {
    local prompt="${1}"
    local answer
    read -rp "  ${prompt} [y/N]: " answer 2>/dev/null || answer="n"
    [[ "$answer" =~ ^[Yy]$ ]]
}

_safe_confirm_typed() {
    local prompt="${1}" expected="${2}"
    local answer
    echo -e "  ${YELLOW}${prompt}${NC}"
    read -rp "  Type '${BOLD}${expected}${NC}' to confirm, or Enter to cancel: " answer 2>/dev/null || answer=""
    [[ "$answer" == "$expected" ]]
}

_pick_agent() {
    # Usage: _pick_agent result_varname
    local _target_var="${1}"
    local agents=() i=1
    echo ""
    echo "  Available agents (active first, then archive):"
    for jf in "$AGENTS_DIR/active/"*.json "$AGENTS_DIR/archive/"*.json; do
        [[ -f "$jf" ]] || continue
        local slug; slug=$(basename "$jf" .json)
        local loc; [[ "$jf" == *"/active/"* ]] && loc="active " || loc="archive"
        printf "    [%d] %-38s  [%s]\n" "$i" "$slug" "$loc"
        agents+=("$slug")
        i=$((i+1))
    done
    if [[ ${#agents[@]} -eq 0 ]]; then
        echo "  No agents found. Run create-agents first."
        printf -v "$_target_var" "%s" ""
        return 1
    fi
    echo ""
    read -rp "  Select agent number (or Enter to cancel): " sel 2>/dev/null || sel=""
    if [[ -z "$sel" ]]; then
        printf -v "$_target_var" "%s" ""; return 1
    fi
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "${#agents[@]}" ]]; then
        printf -v "$_target_var" "%s" "${agents[$((sel-1))]}"
    else
        echo "  Invalid selection."
        printf -v "$_target_var" "%s" ""; return 1
    fi
}

_pick_crew() {
    local _target_var="${1}"
    local crews=() i=1
    echo ""
    echo "  Available crews:"
    for d in "$CREWS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name; name=$(basename "$d")
        printf "    [%d] %s\n" "$i" "$name"
        crews+=("$name"); i=$((i+1))
    done
    for f in "$CONFIG_DIR"/crews/*.yaml; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f" .yaml)
        local found=false
        for c in "${crews[@]+"${crews[@]}"}"; do [[ "$c" == "$name" ]] && found=true; done
        if [[ "$found" == false ]]; then
            printf "    [%d] %s  (config only)\n" "$i" "$name"
            crews+=("$name"); i=$((i+1))
        fi
    done
    if [[ ${#crews[@]} -eq 0 ]]; then
        echo "  No crews found. Create one first (option 9)."
        printf -v "$_target_var" "%s" ""; return 1
    fi
    echo ""
    read -rp "  Select crew number (or Enter to cancel): " sel 2>/dev/null || sel=""
    if [[ -z "$sel" ]]; then
        printf -v "$_target_var" "%s" ""; return 1
    fi
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "${#crews[@]}" ]]; then
        printf -v "$_target_var" "%s" "${crews[$((sel-1))]}"
    else
        echo "  Invalid selection."
        printf -v "$_target_var" "%s" ""; return 1
    fi
}

_backup_offer() {
    local subject="${1:-current data}"
    echo ""
    echo -e "  ${YELLOW}Safety checkpoint:${NC} Create a backup of ${subject} before proceeding?"
    if _safe_confirm "Backup now?"; then
        local bs="$SCRIPTS_DIR/backup-interactive.sh"
        if [[ -f "$bs" ]]; then
            echo "  Running backup..."
            bash "$bs" --mode plan-history 2>&1 || \
                echo -e "  ${YELLOW}Backup encountered issues — check output above.${NC}"
        else
            echo -e "  ${YELLOW}Backup script not found at $bs — skipping.${NC}"
        fi
    fi
}

# ── Agent actions ─────────────────────────────────────────────────────────────

_menu_agent_list() { echo ""; list_agents; }

_menu_agent_create() {
    echo ""
    echo -e "  ${BLUE}Agent Catalog & Creation${NC}"
    echo ""

    # Show live catalog state
    local _act _arc
    _act=$(find "$AGENTS_DIR/active"  -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    _arc=$(find "$AGENTS_DIR/archive" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
    printf "  Catalog: ${BLUE}27 agents defined${NC}   Deployed: ${BLUE}%d active  %d archive${NC}\n" "$_act" "$_arc"
    echo ""
    echo "    [3] Deploy + Finalize in one step"
    echo "    [4] Create single agent       — setup wizard"
    echo "    [5] Cancel"
    echo ""
    read -rp "  Choice: " ac 2>/dev/null || ac=""
    case "$ac" in
        1)
            echo ""
            if _safe_confirm "Deploy all 27 catalog agents now?"; then
                create_agents_from_plugin
            else
                echo "  Cancelled."
            fi
            ;;
        2)
            echo ""
            if [[ $_act -eq 0 ]] && [[ $_arc -eq 0 ]]; then
                echo -e "  ${YELLOW}No agents deployed yet — run Deploy first (option 1).${NC}"
            else
                create_agents_from_plugin  2>/dev/null || true   # ensure dirs exist
                finalize_agents_from_plugin
            fi
            ;;
        3)
            echo ""
            if _safe_confirm "Deploy all 27 agents then finalize/wire workflows?"; then
                create_agents_from_plugin && finalize_agents_from_plugin
            else
                echo "  Cancelled."
            fi
            ;;
        4)
            local wiz="$SCRIPTS_DIR/setup-wizard.sh"
            if [[ -f "$wiz" ]]; then
                bash "$wiz" --agent
            elif [[ -f "$SCRIPTS_DIR/agent-create.sh" ]]; then
                bash "$SCRIPTS_DIR/agent-create.sh"
            else
                echo "  agent-create.sh not found."
            fi
            ;;
        *) echo "  Cancelled." ;;
    esac
}

_menu_agent_delete() {
    echo ""
    echo -e "  ${YELLOW}Delete Agent${NC} — This cannot be undone without a backup."
    local agent_id
    _pick_agent agent_id || return 0
    [[ -z "${agent_id:-}" ]] && return 0

    local agent_dir="$AGENTS_DIR/$agent_id"
    echo ""
    echo -e "  ${RED}About to delete:${NC} $agent_dir"
    if [[ -d "$agent_dir" ]]; then
        echo "  Contents:"
        ls -1 "$agent_dir" 2>/dev/null | sed 's/^/    /'
    fi
    _backup_offer "agent '$agent_id'"
    echo ""
    if _safe_confirm_typed \
        "Permanently delete agent '${agent_id}' and ALL its files?" \
        "$agent_id"; then
        local ds="$SCRIPTS_DIR/agent-delete.sh"
        if [[ -f "$ds" ]]; then
            bash "$ds" --id "$agent_id" --force && \
                success "Agent '$agent_id' deleted." || \
                echo -e "  ${RED}Deletion failed — see output above.${NC}"
        else
            echo "  agent-delete.sh not found."
        fi
    else
        echo "  Deletion cancelled."
    fi
}

_menu_agent_import_export() {
    echo ""
    echo -e "  ${BLUE}Agent Import / Export${NC}"
    echo "    [1] Export an agent to archive"
    echo "    [2] Import an agent from archive"
    echo "    [3] Cancel"
    echo ""
    read -rp "  Choice: " ie 2>/dev/null || ie=""
    case "$ie" in
        1)
            local agent_id
            _pick_agent agent_id || return 0
            [[ -z "${agent_id:-}" ]] && return 0
            local xs="$SCRIPTS_DIR/agent-export.sh"
            [[ -f "$xs" ]] && bash "$xs" --id "$agent_id" || echo "  agent-export.sh not found."
            ;;
        2)
            local is="$SCRIPTS_DIR/agent-import.sh"
            [[ -f "$is" ]] && bash "$is" || echo "  agent-import.sh not found."
            ;;
        *) echo "  Cancelled." ;;
    esac
}

_menu_agent_logs() {
    echo ""
    local agent_id
    _pick_agent agent_id || return 0
    [[ -z "${agent_id:-}" ]] && return 0
    local ls_script="$SCRIPTS_DIR/agent-logs.sh"
    [[ -f "$ls_script" ]] && bash "$ls_script" "$agent_id" || echo "  agent-logs.sh not found."
}

_menu_agent_control() {
    echo ""
    echo -e "  ${BLUE}Agent Control${NC}"
    local agent_id
    _pick_agent agent_id || return 0
    [[ -z "${agent_id:-}" ]] && return 0
    echo ""
    echo "    [1] Start   [2] Stop   [3] Restart   [4] Cancel"
    read -rp "  Action: " ac 2>/dev/null || ac=""
    local ctrl="$SCRIPTS_DIR/agent-control.sh"
    if [[ ! -f "$ctrl" ]]; then echo "  agent-control.sh not found."; return 0; fi
    case "$ac" in
        1) bash "$ctrl" start "$agent_id" ;;
        2) _safe_confirm "Stop agent '$agent_id'?" && bash "$ctrl" stop "$agent_id" ;;
        3) _safe_confirm "Restart agent '$agent_id'?" && bash "$ctrl" restart "$agent_id" ;;
        *) echo "  Cancelled." ;;
    esac
}

_menu_inject_memory() {
    echo ""
    echo -e "  ${BLUE}Memory Injection${NC}"
    echo "    [1] Inject for a specific agent"
    echo "    [2] Inject for ALL agents"
    echo "    [3] Cancel"
    read -rp "  Choice: " im 2>/dev/null || im=""
    local inj="$SCRIPTS_DIR/tool-inject-memory.sh"
    if [[ ! -f "$inj" ]]; then echo "  tool-inject-memory.sh not found."; return 0; fi
    case "$im" in
        1)
            local agent_id
            _pick_agent agent_id || return 0
            [[ -z "${agent_id:-}" ]] && return 0
            bash "$inj" "$agent_id"
            ;;
        2) _safe_confirm "Inject memory for ALL agents?" && bash "$inj" --all ;;
        *) echo "  Cancelled." ;;
    esac
}

# ── Crew actions ──────────────────────────────────────────────────────────────

_menu_crew_list() { echo ""; list_crews; }

_menu_crew_create() {
    echo ""
    echo -e "  ${BLUE}Create Crew${NC}"
    local wiz="$SCRIPTS_DIR/setup-wizard.sh"
    if [[ -f "$wiz" ]]; then
        bash "$wiz" --crew
    elif [[ -f "$SCRIPTS_DIR/crew-create.sh" ]]; then
        bash "$SCRIPTS_DIR/crew-create.sh"
    else
        echo "  crew-create.sh not found."
    fi
}

_menu_crew_start() {
    echo ""
    local crew_name
    _pick_crew crew_name || return 0
    [[ -z "${crew_name:-}" ]] && return 0
    local cs="$SCRIPTS_DIR/crew-start.sh"
    [[ -f "$cs" ]] && bash "$cs" "$crew_name" || echo "  crew-start.sh not found."
}

_menu_crew_stop() {
    echo ""
    local crew_name
    _pick_crew crew_name || return 0
    [[ -z "${crew_name:-}" ]] && return 0
    _safe_confirm "Stop crew '$crew_name'?" || { echo "  Cancelled."; return 0; }
    local cs="$SCRIPTS_DIR/crew-stop.sh"
    [[ -f "$cs" ]] && bash "$cs" "$crew_name" || echo "  crew-stop.sh not found."
}

_menu_crew_dissolve() {
    echo ""
    echo -e "  ${RED}Dissolve Crew${NC} — Removes the crew configuration (agent data is NOT deleted)."
    local crew_name
    _pick_crew crew_name || return 0
    [[ -z "${crew_name:-}" ]] && return 0
    _backup_offer "crew '$crew_name'"
    echo ""
    if _safe_confirm_typed \
        "Dissolve crew '${crew_name}'? (Agent data is preserved.)" \
        "$crew_name"; then
        local ds="$SCRIPTS_DIR/crew-dissolve.sh"
        if [[ -f "$ds" ]]; then
            bash "$ds" "$crew_name" --force && \
                success "Crew '$crew_name' dissolved." || \
                echo -e "  ${RED}Dissolve failed — see output above.${NC}"
        else
            echo "  crew-dissolve.sh not found."
        fi
    else
        echo "  Cancelled."
    fi
}

_menu_crew_monitor() {
    echo ""
    local crew_name
    _pick_crew crew_name || return 0
    [[ -z "${crew_name:-}" ]] && return 0
    local cm="$SCRIPTS_DIR/crew-monitor.sh"
    [[ -f "$cm" ]] && bash "$cm" "$crew_name" || echo "  crew-monitor.sh not found."
}

# ── System actions ────────────────────────────────────────────────────────────

_menu_system_status() { echo ""; system_status; }

_menu_self_check() {
    echo ""
    self_check
    echo ""
    local doctor="$SCRIPTS_DIR/system/hemlock-doctor.sh"
    if [[ -f "$doctor" ]]; then
        _safe_confirm "Run full doctor diagnostics?" && bash "$doctor" diagnose
    fi
}

_menu_setup_wizard() {
    echo ""
    local wiz="$SCRIPTS_DIR/setup-wizard.sh"
    if [[ -f "$wiz" ]]; then
        bash "$wiz"
    else
        echo "  setup-wizard.sh not found at $wiz"
        echo "  Running basic setup instead..."
        setup_system
    fi
}

_menu_initialize() {
    echo ""
    echo -e "  ${BLUE}First-Run Initialization${NC}"
    echo "  Scans hardware, builds Llama.cpp, downloads Qwen3:0.6B."
    echo "  This may take several minutes."
    echo ""
    _safe_confirm "Run first-time initialization?" && run_first_run_initialization
}

_menu_update() {
    echo ""
    echo -e "  ${BLUE}Update System${NC}"
    echo "  Refreshes memory injection for all agents and finalizes configs."
    echo ""
    _safe_confirm "Run system update?" || { echo "  Cancelled."; return 0; }
    _backup_offer "all agents"
    update_system
}

# ── Docker actions ────────────────────────────────────────────────────────────

_docker_check() {
    if ! command -v docker &>/dev/null; then
        echo -e "  ${YELLOW}Docker is not installed or not in PATH.${NC}"
        echo "  Install: https://docs.docker.com/get-docker/"
        echo "  Note: Docker must be run on your local machine — not inside Replit."
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}Docker daemon is not running.${NC}"
        echo "  Start Docker Desktop or: sudo systemctl start docker"
        return 1
    fi
}

_menu_docker_up() {
    echo ""
    _docker_check || return 0
    _safe_confirm "Start all services (docker compose up -d)?" || { echo "  Cancelled."; return 0; }
    docker compose up -d 2>&1 || echo -e "  ${RED}docker compose up failed.${NC}"
}

_menu_docker_down() {
    echo ""
    _docker_check || return 0
    echo -e "  ${YELLOW}This will stop and remove all running containers.${NC}"
    echo "  Currently running:"
    docker compose ps 2>/dev/null | sed 's/^/    /' || echo "    (none)"
    echo ""
    _safe_confirm "Stop all services (docker compose down)?" || { echo "  Cancelled."; return 0; }
    docker compose down 2>&1 || echo -e "  ${RED}docker compose down failed.${NC}"
}

_menu_docker_build() {
    echo ""
    _docker_check || return 0
    echo -e "  ${BLUE}Build Docker Images${NC}"
    echo "    [1] Framework image only"
    echo "    [2] All agent images"
    echo "    [3] Single agent image"
    echo "    [4] Crew image"
    echo "    [5] Everything (framework + agents)"
    echo "    [6] Cancel"
    echo ""
    read -rp "  Choice: " bc 2>/dev/null || bc=""
    local bsh="$RUNTIME_ROOT/build.sh"
    if [[ ! -f "$bsh" ]]; then echo "  build.sh not found."; return 0; fi
    case "$bc" in
        1) bash "$bsh" framework ;;
        2) bash "$bsh" agents ;;
        3)
            local agent_id
            _pick_agent agent_id || return 0
            [[ -z "${agent_id:-}" ]] && return 0
            bash "$bsh" agent "$agent_id"
            ;;
        4)
            local crew_name
            _pick_crew crew_name || return 0
            [[ -z "${crew_name:-}" ]] && return 0
            bash "$bsh" crew "$crew_name"
            ;;
        5)
            _safe_confirm "Build all images? This may take several minutes." && \
                bash "$bsh" all
            ;;
        *) echo "  Cancelled." ;;
    esac
}

_menu_docker_ps() {
    echo ""
    _docker_check || return 0
    docker compose ps 2>&1 || true
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
}

_menu_docker_logs() {
    echo ""
    _docker_check || return 0
    echo "  Streaming service logs — press Ctrl+C to stop."
    echo ""
    docker compose logs -f 2>&1 || echo "  No compose logs available."
}

# ── Backup actions ────────────────────────────────────────────────────────────

_menu_backup_now() {
    echo ""
    local bs="$SCRIPTS_DIR/backup-interactive.sh"
    [[ -f "$bs" ]] && bash "$bs" || echo "  backup-interactive.sh not found."
}

_menu_backup_restore() {
    echo ""
    local bs="$SCRIPTS_DIR/backup-interactive.sh"
    if [[ ! -f "$bs" ]]; then echo "  backup-interactive.sh not found."; return 0; fi
    echo -e "  ${RED}Restore from Backup${NC}"
    echo -e "  ${YELLOW}WARNING: This will overwrite current agent and crew data.${NC}"
    echo ""
    echo "  Available backups:"
    ls -lht "$RUNTIME_ROOT/backups/" 2>/dev/null | head -15 | sed 's/^/    /' || \
        echo "    No backups found in $RUNTIME_ROOT/backups/"
    echo ""
    if _safe_confirm_typed \
        "Restore will overwrite current data. Are you absolutely sure?" \
        "RESTORE"; then
        bash "$bs" restore
    else
        echo "  Restore cancelled."
    fi
}

_menu_backup_status() {
    echo ""
    local bs="$SCRIPTS_DIR/backup-interactive.sh"
    [[ -f "$bs" ]] && bash "$bs" status || echo "  backup-interactive.sh not found."
}

_menu_backup_validate() {
    echo ""
    local bs="$SCRIPTS_DIR/backup-interactive.sh"
    [[ -f "$bs" ]] && bash "$bs" validate || echo "  backup-interactive.sh not found."
}

# ── Plugin actions ────────────────────────────────────────────────────────────

_menu_plugin_list() { echo ""; list_plugins; }

_menu_plugin_toggle() {
    echo ""
    [[ ! -d "$PLUGINS_DIR" ]] && { echo "  No plugins directory found."; return 0; }
    local plugins=() i=1
    for d in "$PLUGINS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name; name=$(basename "$d")
        printf "    [%d] %s\n" "$i" "$name"
        plugins+=("$name"); i=$((i+1))
    done
    [[ ${#plugins[@]} -eq 0 ]] && { echo "  No plugins found."; return 0; }
    echo ""
    read -rp "  Select plugin number (or Enter to cancel): " sel 2>/dev/null || sel=""
    [[ -z "$sel" ]] && return 0
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "${#plugins[@]}" ]]; then
        local pname="${plugins[$((sel-1))]}"
        echo ""
        echo "    [1] Enable   [2] Disable   [3] Cancel"
        read -rp "  Action: " pa 2>/dev/null || pa=""
        case "$pa" in
            1) enable_plugin "$pname" ;;
            2) disable_plugin "$pname" ;;
            *) echo "  Cancelled." ;;
        esac
    else
        echo "  Invalid selection."
    fi
}

# ── Main menu ─────────────────────────────────────────────────────────────────

show_main_menu() {
    _menu_header
    cat <<'MENU'
  ─── AGENTS ─────────────────────────────────────────────────────────────────
   [1]  List agents              [2]  Deploy catalog / Create agent
   [3]  Delete agent             [4]  Import / Export agent
   [5]  View agent logs          [6]  Start / Stop / Restart agent
   [7]  Inject memory

  ─── CREWS ──────────────────────────────────────────────────────────────────
   [8]  List crews               [9]  Create crew
   [10] Start crew               [11] Stop crew
   [12] Dissolve crew            [13] Monitor crew

  ─── SYSTEM ─────────────────────────────────────────────────────────────────
   [14] System status            [15] Self-check / Doctor
   [16] Setup wizard             [17] Initialize (first run)
   [18] Update system

  ─── DOCKER ─────────────────────────────────────────────────────────────────
   [19] Start all services       [20] Stop all services
   [21] Build images             [22] Container status (ps)
   [23] Service logs

  ─── BACKUP ─────────────────────────────────────────────────────────────────
   [24] Backup now               [25] Restore from backup
   [26] Backup status            [27] Validate backup integrity

  ─── PLUGINS ────────────────────────────────────────────────────────────────
   [28] List plugins             [29] Enable / Disable plugin

  ─── INFO ───────────────────────────────────────────────────────────────────
   [h]  Help / full command reference
   [q]  Quit

MENU
    printf "  Choice: "
}

menu_loop() {
    while true; do
        show_main_menu
        local choice
        read -r choice 2>/dev/null || { echo ""; break; }
        echo ""
        case "$choice" in
            1)  _menu_agent_list ;;
            2)  _menu_agent_create ;;
            3)  _menu_agent_delete ;;
            4)  _menu_agent_import_export ;;
            5)  _menu_agent_logs ;;
            6)  _menu_agent_control ;;
            7)  _menu_inject_memory ;;
            8)  _menu_crew_list ;;
            9)  _menu_crew_create ;;
            10) _menu_crew_start ;;
            11) _menu_crew_stop ;;
            12) _menu_crew_dissolve ;;
            13) _menu_crew_monitor ;;
            14) _menu_system_status ;;
            15) _menu_self_check ;;
            16) _menu_setup_wizard ;;
            17) _menu_initialize ;;
            18) _menu_update ;;
            19) _menu_docker_up ;;
            20) _menu_docker_down ;;
            21) _menu_docker_build ;;
            22) _menu_docker_ps ;;
            23) _menu_docker_logs ;;
            24) _menu_backup_now ;;
            25) _menu_backup_restore ;;
            26) _menu_backup_status ;;
            27) _menu_backup_validate ;;
            28) _menu_plugin_list ;;
            29) _menu_plugin_toggle ;;
            h|H|help|--help|-h) usage; continue ;;
            q|Q|quit|exit|0)
                echo "  Goodbye."
                exit 0
                ;;
            "")
                continue
                ;;
            *)
                echo -e "  ${YELLOW}Unknown option '$choice'${NC} — enter a number, [h] for help, or [q] to quit."
                ;;
        esac
        _menu_pause
    done
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
SKIP_INIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
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
        --skip-init)
            SKIP_INIT=true
            shift
            ;;
        deactivate-crew)
            COMMAND="deactivate-crew"
            break
            ;;
        crew-start)
            COMMAND="crew-start"
            break
            ;;
        crew-stop)
            COMMAND="crew-stop"
            break
            ;;
        crew-monitor)
            COMMAND="crew-monitor"
            break
            ;;
        build-framework)
            COMMAND="build-framework"
            break
            ;;
        build-agent)
            COMMAND="build-agent"
            break
            ;;
        build-crew)
            COMMAND="build-crew"
            break
            ;;
        export-agent)
            COMMAND="export-agent"
            break
            ;;
        import)
            COMMAND="import"
            break
            ;;
        up)
            COMMAND="up"
            break
            ;;
        down)
            COMMAND="down"
            break
            ;;
        logs)
            COMMAND="logs"
            break
            ;;
        ps)
            COMMAND="ps"
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
        initialize)
            COMMAND="initialize"
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
            else
                shift
            fi
            ;;
    esac
done

# =============================================================================
# COMMAND ROUTING
# =============================================================================

if [[ -z "${COMMAND:-}" ]]; then
    main_menu
fi

case "$COMMAND" in
    "")
        # No command given — launch the interactive menu
        menu_loop
        ;;
    create-agents|create-agents-from-plugin|deploy-agents)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping agent creation"
        else
            create_agents_from_plugin
        fi
        ;;
    finalize-agents|finalize-agents-from-plugin|wire-agents)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping agent finalization"
        else
            finalize_agents_from_plugin
        fi
        ;;
    list-agents)
        list_agents
        ;;
    delete-agent)
        shift
        delete_agent "$@"
        ;;
    create-crew)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping crew creation"
        else
            create_crew "$@"
        fi
        ;;
    activate-crew)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping crew activation"
        else
            activate_crew "$@"
        fi
        ;;
    deactivate-crew)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping crew deactivation"
        else
            deactivate_crew "$@"
        fi
        ;;
    list-crews)
        list_crews
        ;;
    crew-start)
        shift
        bash "$SCRIPTS_DIR/crew-start.sh" "$@" || true
        ;;
    crew-stop)
        shift
        bash "$SCRIPTS_DIR/crew-stop.sh" "$@" || true
        ;;
    crew-monitor)
        shift
        bash "$SCRIPTS_DIR/crew-monitor.sh" "$@" || true
        ;;
    build-framework)
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would build framework image: docker build -t hemlock-framework ."
        else
            log "Building framework image..."
            docker build -t hemlock-framework . 2>&1 || error "Framework build failed"
        fi
        ;;
    build-agent)
        DOCKER_AGENT_ID=""
        for _a in "$@"; do [[ "$_a" != --* ]] && [[ -z "$DOCKER_AGENT_ID" ]] && DOCKER_AGENT_ID="$_a"; done
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would build agent image: docker build --build-arg AGENT_ID=$DOCKER_AGENT_ID -t oc-$DOCKER_AGENT_ID -f Dockerfile.agent ."
        else
            log "Building agent image for $DOCKER_AGENT_ID..."
            docker build --build-arg AGENT_ID="$DOCKER_AGENT_ID" -t "oc-$DOCKER_AGENT_ID" -f Dockerfile.agent . 2>&1 || error "Agent build failed"
        fi
        ;;
    build-crew)
        DOCKER_CREW_ID=""
        for _a in "$@"; do [[ "$_a" != --* ]] && [[ -z "$DOCKER_CREW_ID" ]] && DOCKER_CREW_ID="$_a"; done
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would build crew image: docker build --build-arg CREW_ID=$DOCKER_CREW_ID -t oc-crew-$DOCKER_CREW_ID -f Dockerfile.crew ."
        else
            log "Building crew image for $DOCKER_CREW_ID..."
            docker build --build-arg CREW_ID="$DOCKER_CREW_ID" -t "oc-crew-$DOCKER_CREW_ID" -f Dockerfile.crew . 2>&1 || error "Crew build failed"
        fi
        ;;
    export-agent)
        DOCKER_EXPORT_AGENT=""
        for _a in "$@"; do [[ "$_a" != --* ]] && [[ -z "$DOCKER_EXPORT_AGENT" ]] && DOCKER_EXPORT_AGENT="$_a"; done
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would export agent image: docker save oc-$DOCKER_EXPORT_AGENT | gzip > $DOCKER_EXPORT_AGENT.tar.gz"
        else
            docker save "oc-$DOCKER_EXPORT_AGENT" | gzip > "$DOCKER_EXPORT_AGENT.tar.gz" || error "Agent export failed"
        fi
        ;;
    import)
        DOCKER_IMPORT_IMAGE=""
        for _a in "$@"; do [[ "$_a" != --* ]] && [[ -z "$DOCKER_IMPORT_IMAGE" ]] && DOCKER_IMPORT_IMAGE="$_a"; done
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would import image: docker load < $DOCKER_IMPORT_IMAGE"
        else
            docker load < "$DOCKER_IMPORT_IMAGE" || error "Image import failed"
        fi
        ;;
    up)
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would start services: docker compose up -d"
        else
            docker compose up -d 2>&1 || error "Service start failed"
        fi
        ;;
    down)
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would stop services: docker compose down"
        else
            docker compose down 2>&1 || error "Service stop failed"
        fi
        ;;
    logs)
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would show service logs: docker compose logs -f"
        else
            docker compose logs -f 2>&1 || error "Logs command failed"
        fi
        ;;
    ps)
        if [[ "$DRY_RUN" == true ]] || echo "$@" | grep -q -- '--dry-run'; then
            log "Would list running containers: docker compose ps"
        else
            docker compose ps 2>&1 || error "PS command failed"
        fi
        ;;
    backup)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping backup"
        else
            backup_command "$@"
        fi
        ;;
    backup-init)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping backup initialization"
        else
            backup_command init
        fi
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
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping restore"
        else
            backup_command restore "$@"
        fi
        ;;
    inject-memory)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping memory injection"
        else
            inject_memory_single "$@"
        fi
        ;;
    inject-all-memory)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping all memory injection"
        else
            inject_all_memory "$@"
        fi
        ;;
    setup)
        # Legacy setup - now redirects to initialize for full setup
        if is_first_run; then
            if [[ "$SKIP_INIT" == true ]]; then
                log "Skipping initialization"
            else
                run_first_run_initialization
            fi
        else
            if [[ "$SKIP_INIT" == true ]]; then
                log "Skipping system setup"
            else
                setup_system
            fi
        fi
        ;;
    initialize)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping initialization"
        else
            run_first_run_initialization
        fi
        ;;
    update)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping system update"
        else
            update_system
        fi
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
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping plugin enable"
        else
            enable_plugin "$@"
        fi
        ;;
    disable-plugin)
        if [[ "$SKIP_INIT" == true ]]; then
            log "Skipping plugin disable"
        else
            disable_plugin "$@"
        fi
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        ;;
esac

exit 0

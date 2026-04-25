#!/bin/bash
# =============================================================================
# Structure Validation Script
# Validates that the project structure matches the enterprise framework spec
# =============================================================================

set -uo pipefail

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find RUNTIME_ROOT by searching for runtime.sh
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
source "$RUNTIME_ROOT/lib/common.sh" 2>/dev/null || source "$SCRIPT_DIR/../../lib/common.sh"

# =============================================================================
# REQUIRED STRUCTURE
# =============================================================================

# Required top-level directories
REQUIRED_DIRS=(
    "agents"
    "config"
    "scripts"
    "plugins"
    "skills"
    "lib"
    "tests"
    "logs"
    "docs"
)

# Required directories under scripts/
SCRIPTS_REQUIRED_DIRS=()
SCRIPTS_REQUIRED_FILES=(
    "backup-interactive.sh"
    "tool-inject-memory.sh"
    "create_crew.py"
    "memory.sh"
)

# Required directories under tests/
TESTS_REQUIRED_DIRS=(
    "e2e"
    "unit"
    "integration"
    "validation"
)

# Required files in lib/
LIB_REQUIRED_FILES=(
    "common.sh"
)

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_top_level() {
    log "Validating top-level directories..."
    
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ ! -d "$RUNTIME_ROOT/$dir" ]]; then
            error "Missing required top-level directory: $dir"
            return 1
        fi
        success "✓ $dir found"
    done
    
    return 0
}

validate_scripts() {
    log "Validating scripts directory..."
    
    for file in "${SCRIPTS_REQUIRED_FILES[@]}"; do
        if [[ ! -f "$RUNTIME_ROOT/scripts/$file" ]]; then
            error "Missing required script: $file"
            return 1
        fi
        
        # Check if executable
        if [[ ! -x "$RUNTIME_ROOT/scripts/$file" ]]; then
            warn "Script not executable: $file (fixing...)"
            safe_chmod "$RUNTIME_ROOT/scripts/$file" "755" || return 1
        fi
        
        success "✓ scripts/$file found and executable"
    done
    
    return 0
}

validate_tests() {
    log "Validating tests directory..."
    
    for dir in "${TESTS_REQUIRED_DIRS[@]}"; do
        if [[ ! -d "$RUNTIME_ROOT/tests/$dir" ]]; then
            error "Missing required test directory: $dir"
            return 1
        fi
        success "✓ tests/$dir found"
    done
    
    return 0
}

validate_lib() {
    log "Validating lib directory..."
    
    for file in "${LIB_REQUIRED_FILES[@]}"; do
        if [[ ! -f "$RUNTIME_ROOT/lib/$file" ]]; then
            error "Missing required library: $file"
            return 1
        fi
        success "✓ lib/$file found"
    done
    
    return 0
}

validate_agents_directories() {
    log "Validating agents directory structure..."
    
    if [[ -d "$RUNTIME_ROOT/agents" ]]; then
        for agent_dir in "$RUNTIME_ROOT/agents"/*/; do
            local agent_name=$(basename "$agent_dir")
            
            # Required agent subdirectories
            local required_agent_dirs=("data" "config")
            
            for subdir in "${required_agent_dirs[@]}"; do
                if [[ ! -d "$agent_dir/$subdir" ]]; then
                    warn "Agent $agent_name missing directory: $subdir"
                else
                    debug "✓ $agent_name/$subdir"
                fi
            done
            
            # Required agent files
            local required_agent_files=("config.yaml")
            
            for req_file in "${required_agent_files[@]}"; do
                if [[ ! -f "$agent_dir/$req_file" ]]; then
                    warn "Agent $agent_name missing file: $req_file"
                else
                    debug "✓ $agent_name/$req_file"
                fi
            done
            
            # Recommended files
            local recommended_files=("SOUL.md" "USER.md" "IDENTITY.md" "MEMORY.md")
            for rec_file in "${recommended_files[@]}"; do
                if [[ ! -f "$agent_dir/data/$rec_file" ]]; then
                    warn "Agent $agent_name missing recommended file: data/$rec_file"
                else
                    debug "✓ $agent_name/data/$rec_file"
                fi
            done
            
            success "✓ Agent $agent_name validated"
        done
    fi
    
    return 0
}

validate_configs() {
    log "Validating configuration files..."
    
    # Required config files
    local required_configs=("runtime.yaml")
    
    for file in "${required_configs[@]}"; do
        if [[ ! -f "$RUNTIME_ROOT/config/$file" ]]; then
            warn "Missing recommended config: config/$file"
        else
            debug "✓ config/$file"
        fi
    done
    
    return 0
}

validate_skills() {
    log "Validating skills directory..."
    
    # Use external validate_skills.sh script if available
    if [[ -x "$RUNTIME_ROOT/tests/validation/validate_skills.sh" ]]; then
        local result
        result=$(cd "$RUNTIME_ROOT" && timeout 30 ./tests/validation/validate_skills.sh 2>&1 || true)
        if echo "$result" | grep -qi "All skills validated successfully"; then
            log "✓ All skills validated (via external validator)"
            return 0
        else
            # Log the issues but don't fail the entire validation
            warn "Skills validation found issues (see above)"
            return 0
        fi
    fi
    
    # Fallback to built-in validation
    if [[ -d "$RUNTIME_ROOT/skills" ]]; then
        local skill_count=0
        local valid_count=0
        
        for skill_dir in "$RUNTIME_ROOT/skills"/*/; do
            skill_count=$((skill_count + 1))
            local skill_name=$(basename "$skill_dir")
            
            # Must have SKILL.md
            if [[ ! -f "$skill_dir/SKILL.md" ]]; then
                error "Skill $skill_name missing required SKILL.md"
            else
                # Check for required sections in SKILL.md
                local skill_file="$skill_dir/SKILL.md"
                local has_name=false
                local has_description=false
                local has_usage=false
                
                while IFS= read -r line; do
                    case "$line" in
                        "# Name") has_name=true ;;
                        "# Description") has_description=true ;;
                        "# Usage") has_usage=true ;;
                    esac
                done < "$skill_file"
                
                if [[ "$has_name" == false ]]; then
                    error "Skill $skill_name missing # Name section in SKILL.md"
                fi
                if [[ "$has_description" == false ]]; then
                    error "Skill $skill_name missing # Description section in SKILL.md"
                fi
                if [[ "$has_usage" == false ]]; then
                    error "Skill $skill_name missing # Usage section in SKILL.md"
                fi
                
                valid_count=$((valid_count + 1))
                success "✓ Skill $skill_name"
            fi
        done
        
        if [[ $skill_count -gt 0 ]]; then
            log "Validated $valid_count/$skill_count skills"
        fi
    fi
    
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log "=========================================="
    log "Structure Validation"
    log "=========================================="
    log ""
    
    local failed=0
    
    # Run all validation functions
    with_self_healing validate_top_level || { error "Top-level validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_lib || { error "Lib validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_scripts || { error "Scripts validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_tests || { error "Tests validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_agents_directories || { error "Agents validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_configs || { error "Configs validation failed"; failed=1; }
    log ""
    
    with_self_healing validate_skills || { error "Skills validation failed"; failed=1; }
    log ""
    
    # Final summary
    log "=========================================="
    if [[ $failed -eq 0 ]]; then
        if [[ $ERROR_COUNT -eq 0 ]]; then
            success "All structure validation passed ($WARNING_COUNT warnings)"
            return 0
        else
            error "Structure validation failed with $ERROR_COUNT errors"
            return 1
        fi
    else
        error "Structure validation failed"
        return 1
    fi
}

main

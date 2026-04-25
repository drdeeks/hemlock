#!/bin/bash
# =============================================================================
# Skills Validation Script
# Validates all skills in the skills directory have proper structure and content
# =============================================================================

set -uo pipefail

# Find RUNTIME_ROOT by searching for runtime.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/runtime.sh" ]]; then
    RUNTIME_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# Load common utilities if available
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

SKILLS_DIR="$RUNTIME_ROOT/skills"
PLACEHOLDER_SKILL_DIR="$RUNTIME_ROOT/plugins/crews/project-manager/skills"

# Required sections in SKILL.md
REQUIRED_SECTIONS=(
    "Name"
    "Description"
    "Usage"
    "Dependencies"
    "Compatibility"
)

# Optional but recommended sections
RECOMMENDED_SECTIONS=(
    "Author"
    "Version"
    "License"
    "Examples"
    "Configuration"
    "Notes"
)

# Platforms to check compatibility with
PLATFORMS=(
    "OpenClaw"
    "Hermes"
    "Mistral Vibe"
)

# Track results
SKILLS_VALIDATED=0
SKILLS_FAILED=0
SKILLS_WARNINGS=0
SKILLS_TOTAL=0

# =============================================================================
# LOGGING
# =============================================================================

if ! declare -F log &>/dev/null; then
    log() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
fi
if ! declare -F success &>/dev/null; then
    success() { echo -e "\033[0;32m[PASS]\033[0m $1"; }
fi
if ! declare -F warn &>/dev/null; then
    warn() { echo -e "\033[1;33m[WARN]\033[0m $1" >&2; }
fi
if ! declare -F error &>/dev/null; then
    error() { echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; }
fi

pass_skill() {
    SKILLS_VALIDATED=$((SKILLS_VALIDATED + 1))
    success "$1"
}

fail_skill() {
    SKILLS_FAILED=$((SKILLS_FAILED + 1))
    error "$1"
}

warn_skill() {
    SKILLS_WARNINGS=$((SKILLS_WARNINGS + 1))
    warn "$1"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if a section exists in SKILL.md
check_section() {
    local skill_name="$1"
    local skill_dir="$2"
    local section="$3"
    local skill_md="$skill_dir/SKILL.md"
    
    if [[ ! -f "$skill_md" ]]; then
        return 1
    fi
    
    # Check for section headers: # Section, ## Section, ### Section
    if grep -qi "^[[:space:]]*#\+[[:space:]]*${section}[[:space:]]*$" "$skill_md" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Validate SKILL.md has all required sections
validate_skill_md() {
    local skill_name="$1"
    local skill_dir="$2"
    local has_all_required=true
    local missing_sections=()
    local has_recommended=()
    
    # Check required sections
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! check_section "$skill_name" "$skill_dir" "$section"; then
            has_all_required=false
            missing_sections+=("$section")
        fi
    done
    
    # Report missing required sections
    if [[ "$has_all_required" == false ]]; then
        fail_skill "Skill $skill_name missing required sections: ${missing_sections[*]}"
        return 1
    fi
    
    # Check recommended sections (warning only)
    for section in "${RECOMMENDED_SECTIONS[@]}"; do
        if ! check_section "$skill_name" "$skill_dir" "$section"; then
            has_recommended+=("$section")
        fi
    done
    
    if [[ ${#has_recommended[@]} -gt 0 ]]; then
        warn_skill "Skill $skill_name missing recommended sections: ${has_recommended[*]}"
    fi
    
    return 0
}

# Validate YAML configuration if present
validate_yaml() {
    local skill_name="$1"
    local yaml_file="$2"
    
    # Check if YAML is valid
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
            fail_skill "Skill $skill_name has invalid YAML: $yaml_file"
            return 1
        fi
    elif command -v yq &>/dev/null; then
        # Use yq to validate
        if ! yq eval "$yaml_file" >/dev/null 2>&1; then
            fail_skill "Skill $skill_name has invalid YAML: $yaml_file"
            return 1
        fi
    else
        # Can't validate without yaml parser, just check syntax with grep
        if ! grep -qE '^[\s]*[a-zA-Z]' "$yaml_file" 2>/dev/null; then
            warn_skill "Skill $skill_name YAML file may be empty: $yaml_file"
            return 0
        fi
    fi
    
    return 0
}

# Validate compatibility section mentions all platforms
validate_compatibility() {
    local skill_name="$1"
    local skill_dir="$2"
    local skill_md="$skill_dir/SKILL.md"
    local missing_platforms=()
    
    # Extract compatibility section content
    local in_compatibility=false
    local compatibility_text=""
    
    while IFS= read -r line; do
        # Check for compatibility section start
        if echo "$line" | grep -qi "^[[:space:]]*#\+[[:space:]]*Compatibility[[:space:]]*$"; then
            in_compatibility=true
            continue
        fi
        
        # Check for next section (stop collecting)
        if [[ "$in_compatibility" == true && "$line" =~ ^[[:space:]]*#\+[[:space:]]+[A-Za-z] ]]; then
            break
        fi
        
        if [[ "$in_compatibility" == true ]]; then
            compatibility_text+="$line\n"
        fi
    done < "$skill_md"
    
    # Check if each platform is mentioned
    for platform in "${PLATFORMS[@]}"; do
        if ! echo "$compatibility_text" | grep -qi "$platform"; then
            missing_platforms+=("$platform")
        fi
    done
    
    if [[ ${#missing_platforms[@]} -gt 0 ]]; then
        warn_skill "Skill $skill_name compatibility section missing platforms: ${missing_platforms[*]}"
        return 1
    fi
    
    return 0
}

# Validate skill references and attributions
validate_references() {
    local skill_name="$1"
    local skill_dir="$2"
    
    local references_dir="$skill_dir/references"
    
    if [[ ! -d "$references_dir" ]]; then
        # No references directory is OK
        return 0
    fi
    
    # Check if references directory has files
    if [[ -z "$(ls -A "$references_dir" 2>/dev/null)" ]]; then
        warn_skill "Skill $skill_name has empty references directory"
        return 0
    fi
    
    # Check for attribution/license files
    local has_attribution=false
    for file in "$references_dir"/*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file" | tr '[:upper:]' '[:lower:]')
            if [[ "$filename" == *"license"* || "$filename" == *"attribution"* || "$filename" == *"readme"* ]]; then
                has_attribution=true
                break
            fi
        fi
    done
    
    if [[ "$has_attribution" == false ]]; then
        warn_skill "Skill $skill_name references directory missing attribution/license"
        return 1
    fi
    
    return 0
}

# Validate skill configuration directory
validate_config() {
    local skill_name="$1"
    local skill_dir="$2"
    local config_dir="$skill_dir/config"
    
    if [[ ! -d "$config_dir" ]]; then
        # Config directory is optional
        return 0
    fi
    
    # Check if config.yaml exists
    if [[ ! -f "$config_dir/config.yaml" ]]; then
        warn_skill "Skill $skill_name config directory missing config.yaml"
        return 1
    fi
    
    # Validate the YAML
    validate_yaml "$skill_name" "$config_dir/config.yaml"
    return $?
}

# Validate skill has Python package structure if it has .py files
default_validate_python_package() {
    local skill_name="$1"
    local skill_dir="$2"
    
    # Check if there are any .py files
    if find "$skill_dir" -name "*.py" -type f | grep -q . 2>/dev/null; then
        # Check for __init__.py
        if [[ ! -f "$skill_dir/__init__.py" ]]; then
            warn_skill "Skill $skill_name has Python files but missing __init__.py"
            return 1
        fi
        
        # Check for main.py
        if [[ ! -f "$skill_dir/main.py" ]]; then
            warn_skill "Skill $skill_name has Python files but missing main.py"
            return 1
        fi
    fi
    
    return 0
}

# Validate agent-specific skills in agents/*/skills/
validate_agent_skills() {
    local agents_dir="$RUNTIME_ROOT/agents"
    local agent_skills_validated=0
    local agent_skills_failed=0
    
    log "Validating agent-specific skills..."
    
    for agent_dir in "$agents_dir"/*/; do
        if [[ -d "$agent_dir" ]]; then
            local agent_name=$(basename "$agent_dir")
            local agent_skills_dir="$agent_dir/skills"
            
            if [[ -d "$agent_skills_dir" ]]; then
                for skill_dir in "$agent_skills_dir"/*/; do
                    if [[ -d "$skill_dir" ]]; then
                        SKILLS_TOTAL=$((SKILLS_TOTAL + 1))
                        local skill_name=$(basename "$skill_dir")
                        
                        log "Validating agent skill: $agent_name/$skill_name"
                        
                        # Check for SKILL.md
                        if [[ ! -f "$skill_dir/SKILL.md" ]]; then
                            fail_skill "Agent $agent_name skill $skill_name missing SKILL.md"
                            agent_skills_failed=$((agent_skills_failed + 1))
                            continue
                        fi
                        
                        # Validate SKILL.md
                        if ! validate_skill_md "$agent_name/$skill_name" "$skill_dir"; then
                            agent_skills_failed=$((agent_skills_failed + 1))
                            continue
                        fi
                        
                        pass_skill "Agent skill $agent_name/$skill_name validated"
                        agent_skills_validated=$((agent_skills_validated + 1))
                    fi
                done
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# MAIN VALIDATION
# =============================================================================

validate_all_skills() {
    log "=========================================="
    log "Skills Validation"
    log "=========================================="
    log "Skills Directory: $SKILLS_DIR"
    log ""
    
    # Check if skills directory exists
    if [[ ! -d "$SKILLS_DIR" ]]; then
        fail_skill "Skills directory does not exist: $SKILLS_DIR"
        return 1
    fi
    
    # Get all skill directories (including subdirectories)
    # We need to handle both skills/* and agents/*/skills/*
    
    # First, validate root skills
    log "Validating root skills..."
    if [[ -d "$SKILLS_DIR" ]]; then
        for skill_dir in "$SKILLS_DIR"/*/; do
            if [[ -d "$skill_dir" ]]; then
                SKILLS_TOTAL=$((SKILLS_TOTAL + 1))
                local skill_name=$(basename "$skill_dir")
                local validation_passed=true
                
                log "Validating skill: $skill_name"
                
                # 1. Check for SKILL.md (REQUIRED)
                if [[ ! -f "$skill_dir/SKILL.md" ]]; then
                    fail_skill "Skill $skill_name missing required SKILL.md"
                    validation_passed=false
                fi
                
                # 2. Validate SKILL.md sections
                if [[ -f "$skill_dir/SKILL.md" && "$validation_passed" == true ]]; then
                    if ! validate_skill_md "$skill_name" "$skill_dir"; then
                        validation_passed=false
                    fi
                fi
                
                # 3. Validate YAML files
                if [[ "$validation_passed" == true ]]; then
                    # Find all yaml files
                    while IFS= read -r -d '' yaml_file; do
                        if [[ -f "$yaml_file" ]]; then
                            if ! validate_yaml "$skill_name" "$yaml_file"; then
                                validation_passed=false
                            fi
                        fi
                    done < <(find "$skill_dir" -maxdepth 2 \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)
                fi
                
                # 4. Validate compatibility
                if [[ "$validation_passed" == true && -f "$skill_dir/SKILL.md" ]]; then
                    if ! validate_compatibility "$skill_name" "$skill_dir"; then
                        # This is a warning, not a failure
                        :
                    fi
                fi
                
                # 5. Validate references
                if [[ "$validation_passed" == true ]]; then
                    if ! validate_references "$skill_name" "$skill_dir"; then
                        # This is a warning, not a failure
                        :
                    fi
                fi
                
                # 6. Validate config
                if [[ "$validation_passed" == true ]]; then
                    if ! validate_config "$skill_name" "$skill_dir"; then
                        # This is a warning, not a failure
                        :
                    fi
                fi
                
                # 7. Validate Python package structure
                if [[ "$validation_passed" == true ]]; then
                    if ! default_validate_python_package "$skill_name" "$skill_dir"; then
                        # This is a warning, not a failure
                        :
                    fi
                fi
                
                if [[ "$validation_passed" == true ]]; then
                    pass_skill "Skill $skill_name validated"
                fi
            fi
        done
    fi
    
    # Validate agent-specific skills
    validate_agent_skills
    
    # Summary
    log ""
    log "=========================================="
    log "Skills Validation Summary"
    log "=========================================="
    log "Total Skills: $SKILLS_TOTAL"
    log "Validated: $SKILLS_VALIDATED"
    log "Failed: $SKILLS_FAILED"
    log "Warnings: $SKILLS_WARNINGS"
    log ""
    
    if [[ $SKILLS_FAILED -eq 0 ]]; then
        success "All skills validated successfully"
        return 0
    else
        error "Skills validation failed with $SKILLS_FAILED errors"
        return 1
    fi
}

# =============================================================================
# SELF-HEALING
# =============================================================================

attempt_fix_skills() {
    log "=========================================="
    log "Attempting to Fix Skills"
    log "=========================================="
    
    local fixed=0
    
    # Fix root skills
    for skill_dir in "$SKILLS_DIR"/*/; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name=$(basename "$skill_dir")
            local skill_md="$skill_dir/SKILL.md"
            
            # Create missing SKILL.md with template
            if [[ ! -f "$skill_md" ]]; then
                log "Creating SKILL.md template for $skill_name"
                cat > "$skill_md" << 'EOF'
# Skill Template

## Name
[Skill Name]

## Description
[Brief description of what this skill does]

## Usage
[How to use this skill]

## Dependencies
- [List dependencies]

## Compatibility
- OpenClaw
- Hermes
- Mistral Vibe

## Author
[Author name]

## Version
1.0.0

## License
[License]
EOF
                if [[ -f "$skill_md" ]]; then
                    pass_skill "Created SKILL.md template for $skill_name"
                    fixed=$((fixed + 1))
                fi
            fi
            
            # Add missing required sections
            if [[ -f "$skill_md" ]]; then
                for section in "${REQUIRED_SECTIONS[@]}"; do
                    if ! check_section "$skill_name" "$skill_dir" "$section"; then
                        log "Adding missing $section section to $skill_name"
                        echo "" >> "$skill_md"
                        echo "## $section" >> "$skill_md"
                        echo "[Content for $section]" >> "$skill_md"
                        fixed=$((fixed + 1))
                        pass_skill "Added $section section to $skill_name"
                    fi
                done
            fi
        fi
    done
    
    # Fix agent-specific skills
    log "Checking agent-specific skills..."
    local agents_dir="$RUNTIME_ROOT/agents"
    if [[ -d "$agents_dir" ]]; then
        for agent_dir in "$agents_dir"/*/; do
            if [[ -d "$agent_dir" ]]; then
                local agent_name=$(basename "$agent_dir")
                local agent_skills_dir="$agent_dir/skills"
                if [[ -d "$agent_skills_dir" ]]; then
                    for skill_dir in "$agent_skills_dir"/*/; do
                        if [[ -d "$skill_dir" ]]; then
                            local skill_name=$(basename "$skill_dir")
                            local skill_md="$skill_dir/SKILL.md"
                            
                            # Create missing SKILL.md with template
                            if [[ ! -f "$skill_md" ]]; then
                                log "Creating SKILL.md template for $agent_name/$skill_name"
                                cat > "$skill_md" << 'EOF'
# Skill Template

## Name
[Skill Name]

## Description
[Brief description of what this skill does]

## Usage
[How to use this skill]

## Dependencies
- [List dependencies]

## Compatibility
- OpenClaw
- Hermes
- Mistral Vibe

## Author
[Author name]

## Version
1.0.0

## License
[License]
EOF
                                if [[ -f "$skill_md" ]]; then
                                    pass_skill "Created SKILL.md template for $agent_name/$skill_name"
                                    fixed=$((fixed + 1))
                                fi
                            fi
                            
                            # Add missing required sections
                            if [[ -f "$skill_md" ]]; then
                                for section in "${REQUIRED_SECTIONS[@]}"; do
                                    if ! check_section "$agent_name/$skill_name" "$skill_dir" "$section"; then
                                        log "Adding missing $section section to $agent_name/$skill_name"
                                        echo "" >> "$skill_md"
                                        echo "## $section" >> "$skill_md"
                                        echo "[Content for $section]" >> "$skill_md"
                                        fixed=$((fixed + 1))
                                        pass_skill "Added $section section to $agent_name/$skill_name"
                                    fi
                                done
                            fi
                        fi
                    done
                fi
            fi
        done
    fi
    
    log "Fixed $fixed skill issues"
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local action="${1:-validate}"
    
    case "$action" in
        validate|--validate|-v)
            validate_all_skills
            ;;
        fix|--fix|-f)
            validate_all_skills
            if [[ $SKILLS_FAILED -gt 0 ]]; then
                attempt_fix_skills
                validate_all_skills
            fi
            ;;
        *)
            log "Usage: $0 [validate|fix]"
            log "  validate - Validate all skills (default)"
            log "  fix      - Validate and attempt to fix issues"
            exit 1
            ;;
    esac
}

main "$@"

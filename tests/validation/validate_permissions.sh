#!/bin/bash
# =============================================================================
# Permission Validation Script
# Validates file permissions match enterprise framework standards
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
# PERMISSION STANDARDS
# =============================================================================

# Define expected permissions for different file types
declare -A EXPECTED_PERMS=(n
    ["scripts/executable"]="755"
    ["scripts/sensitive"]="750"
    ["config/standard"]="644"
    ["config/sensitive"]="640"
    ["secrets"]="600"
    ["data"]="644"
    ["logs"]="644"
    ["directories"]="755"
    ["directories/private"]="750"
)

# File that should NEVER be 700
FORBIDDEN_PERM="700"

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Scan for files with forbidden permissions
scan_for_forbidden_permissions() {
    log "Scanning for forbidden permission $FORBIDDEN_PERM..."
    
    local found_forbidden=0
    local total_checked=0
    
    # Check files
    while IFS= read -r -d '' file; do
        total_checked=$((total_checked + 1))
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null)
        
        if [[ "$perms" == "$FORBIDDEN_PERM" ]]; then
            error "FORBIDDEN: File has permission $FORBIDDEN_PERM: $file"
            found_forbidden=$((found_forbidden + 1))
            
            # Attempt auto-fix
            if fix_permission "$file" "755"; then
                success "Auto-fixed: $file"
            else
                warn "Failed to auto-fix: $file"
            fi
        fi
    done < <(find "$RUNTIME_ROOT" -type f -print0 2>/dev/null | grep -vz ".git")
    
    # Check directories
    while IFS= read -r -d '' dir; do
        total_checked=$((total_checked + 1))
        local perms
        perms=$(stat -c "%a" "$dir" 2>/dev/null || stat -f "%OLp" "$dir" 2>/dev/null)
        
        if [[ "$perms" == "$FORBIDDEN_PERM" ]]; then
            error "FORBIDDEN: Directory has permission $FORBIDDEN_PERM: $dir"
            found_forbidden=$((found_forbidden + 1))
            
            # Attempt auto-fix
            if fix_permission "$dir" "755"; then
                success "Auto-fixed: $dir"
            else
                warn "Failed to auto-fix: $dir"
            fi
        fi
    done < <(find "$RUNTIME_ROOT" -type d -print0 2>/dev/null | grep -vz ".git")
    
    log "Scanned $total_checked files/directories, found $found_forbidden with forbidden permissions"
    
    return $found_forbidden
}

# Fix a single permission
fix_permission() {
    local path="$1"
    local target_perm="$2"
    
    debug "Fixing permission on $path to $target_perm"
    
    if chmod "$target_perm" "$path" 2>/dev/null; then
        return 0
    fi
    
    # Fallback: sudo
    if command -v sudo &>/dev/null && [[ $EUID -ne 0 ]]; then
        sudo chmod "$target_perm" "$path" 2>/dev/null && return 0
    fi
    
    return 1
}

# Validate scripts are executable
validate_scripts_executable() {
    log "Validating scripts are executable..."
    
    local non_executable=0
    
    while IFS= read -r -d '' script; do
        if [[ ! -x "$script" ]]; then
            error "Script not executable: $script"
            non_executable=$((non_executable + 1))
            
            # Auto-fix
            if fix_permission "$script" "755"; then
                success "Auto-fixed executable: $script"
            fi
        else
            debug "✓ $script is executable"
        fi
    done < <(find "$RUNTIME_ROOT/scripts" -type f -print0 2>/dev/null)
    
    log "Found $non_executable non-executable scripts"
    return $non_executable
}

# Validate configuration files are readable
validate_configs_readable() {
    log "Validating config files are readable..."
    
    local unreadable=0
    
    while IFS= read -r -d '' config; do
        if [[ ! -r "$config" ]]; then
            error "Config not readable: $config"
            unreadable=$((unreadable + 1))
            
            # Auto-fix
            if fix_permission "$config" "644"; then
                success "Auto-fixed readable: $config"
            fi
        else
            debug "✓ $config is readable"
        fi
    done < <(find "$RUNTIME_ROOT/config" -type f -print0 2>/dev/null)
    
    log "Found $unreadable unreadable config files"
    return $unreadable
}

# Validate sensitive files have restricted permissions
validate_sensitive_files() {
    log "Validating sensitive files..."
    
    local too_open=0
    
    # Check common sensitive files
    local sensitive_patterns=(
        ".env"
        ".secrets"
        "*key*"
        "*token*"
        "*password*"
        "auth*"
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            local perms
            perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null)
            
            # Sensitive files should not be world-readable (644)
            # Should be 640 or 600
            if [[ "$perms" =~ ^644$|^755$|^777$ ]]; then
                error "Sensitive file has open permissions: $file ($perms)"
                too_open=$((too_open + 1))
                
                # Auto-fix to 640
                if fix_permission "$file" "640"; then
                    success "Auto-fixed sensitive: $file"
                fi
            fi
        done < <(find "$RUNTIME_ROOT" -name "*$pattern*" -type f -print0 2>/dev/null | grep -vz ".git")
    done
    
    log "Found $too_open overly permissive sensitive files"
    return $too_open
}

# Validate directory permissions
validate_directory_permissions() {
    log "Validating directory permissions..."
    
    local problematic=0
    
    while IFS= read -r -d '' dir; do
        local perms
        perms=$(stat -c "%a" "$dir" 2>/dev/null || stat -f "%OLp" "$dir" 2>/dev/null)
        
        if [[ "$perms" == "700" ]]; then
            error "Directory has 700 permission: $dir (breaks isolation)"
            problematic=$((problematic + 1))
            
            # Auto-fix
            if fix_permission "$dir" "755"; then
                success "Auto-fixed directory: $dir"
            fi
        fi
    done < <(find "$RUNTIME_ROOT" -type d -print0 2>/dev/null | grep -vz ".git")
    
    log "Found $problematic directories with problematic permissions"
    return $problematic
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log "=========================================="
    log "Permission Validation"
    log "=========================================="
    log ""
    
    local total_errors=0
    
    # Run all permission checks
    with_self_healing scan_for_forbidden_permissions || total_errors=$((total_errors + 1))
    log ""
    
    with_self_healing validate_scripts_executable || total_errors=$((total_errors + 1))
    log ""
    
    with_self_healing validate_configs_readable || total_errors=$((total_errors + 1))
    log ""
    
    with_self_healing validate_sensitive_files || total_errors=$((total_errors + 1))
    log ""
    
    with_self_healing validate_directory_permissions || total_errors=$((total_errors + 1))
    log ""
    
    # Final summary
    log "=========================================="
    if [[ $total_errors -eq 0 ]]; then
        if [[ $ERROR_COUNT -eq 0 ]]; then
            success "All permission validation passed ($WARNING_COUNT warnings)"
            return 0
        else
            error "Permission validation failed with $ERROR_COUNT errors"
            return 1
        fi
    else
        error "Permission validation failed"
        return 1
    fi
}

main

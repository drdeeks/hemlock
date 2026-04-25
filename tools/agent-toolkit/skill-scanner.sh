#!/usr/bin/env bash
# ==============================================================================
# skill-scanner.sh — Hermes Skill Inventory & Sync Tool
# ==============================================================================
#
# Commands:
#   scan  [agent]     Show skill inventory (all agents or one)
#   sync  [agent]     Link core skills into agent profiles
#   diff  <a> <b>     Compare skills between two agents
#   unlink <agent>    Remove core skill symlinks from an agent (keep agent skills)
#   list              List core skills available
#
# Flags:
#   --dry-run, -n     Preview without modifying
#   --shared-skills   Override core skills path (default: ~/.hermes/skills)
#
# Works with agent-bootstrap.sh profiles at ~/.hermes/profiles/<agent>/
# ==============================================================================

set -euo pipefail

VERSION="1.10.0"

# ── Dry-run ───────────────────────────────────────────────────────────────────

DRY_RUN=false
OPENCLAW_MODE=false

_args=()
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)  DRY_RUN=true ;;
        --openclaw|-o) OPENCLAW_MODE=true ;;
        *)             _args+=("$arg") ;;
    esac
done
set -- "${_args[@]}"

run() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} $*"
        return 0
    fi
    "$@"
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

HOME_DIR="${HOME}"
HERMES_ROOT="${HERMES_HOME:-${HOME_DIR}/.hermes}"
PROFILES_ROOT="${HERMES_ROOT}/profiles"
SHARED_SKILLS="${SHARED_SKILLS_DIR:-${HERMES_ROOT}/skills}"
OPENCLAW_ROOT="${OPENCLAW_ROOT:-${HOME_DIR}/.openclaw}"
OPENCLAW_AGENTS="${OPENCLAW_ROOT}/agents"

# ── Discover agents ───────────────────────────────────────────────────────────

discover_agents() {
    declare -A seen
    local list=()

    # OpenClaw agents
    if [ -d "$OPENCLAW_AGENTS" ]; then
        for d in "$OPENCLAW_AGENTS"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [ "$name" = "templates" ] && continue
            seen["$name"]=1
            list+=("$name")
        done
    fi

    # Profiles
    if [ -d "$PROFILES_ROOT" ]; then
        for d in "$PROFILES_ROOT"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            seen["$name"]=1
            list+=("$name")
        done
    fi

    # Legacy
    for d in "${HOME_DIR}"/.hermes-*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        name="${name#.hermes-}"
        [ "$name" = "gateway" ] && continue
        if [ -z "${seen[$name]:-}" ]; then
            seen["$name"]=1
            list+=("$name")
        fi
    done

    echo "${list[@]}"
}

# Resolve agent's skills directory
agent_skills_dir() {
    local agent="$1"
    if [ "$OPENCLAW_MODE" = true ]; then
        echo "${OPENCLAW_AGENTS}/${agent}/skills"
    elif [ -d "${PROFILES_ROOT}/${agent}/skills" ]; then
        echo "${PROFILES_ROOT}/${agent}/skills"
    elif [ -d "${HOME_DIR}/.hermes-${agent}/skills" ]; then
        echo "${HOME_DIR}/.hermes-${agent}/skills"
    else
        echo "${PROFILES_ROOT}/${agent}/skills"
    fi
}

# ── List core skills ──────────────────────────────────────────────────────────

list_core_skills() {
    [ -d "$SHARED_SKILLS" ] || die "Core skills dir not found: ${SHARED_SKILLS}"

    local count=0
    for d in "$SHARED_SKILLS"/*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        [ "$name" = "templates" ] && continue
        echo "  • ${name}"
        count=$((count + 1))
    done
    echo ""
    echo "Total: ${count} core skills in ${SHARED_SKILLS}"
}

# ── Scan ──────────────────────────────────────────────────────────────────────

cmd_scan() {
    local target="${1:-all}"

    header "Skill Inventory"

    # Core skills
    if [ -d "$SHARED_SKILLS" ]; then
        local core_count
        core_count=$(find "$SHARED_SKILLS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        log "Core skills: ${core_count} in ${SHARED_SKILLS}"
    else
        warn "Core skills dir not found: ${SHARED_SKILLS}"
        warn "Set SHARED_SKILLS_DIR or create the directory"
        return 1
    fi

    local agents
    if [ "$target" = "all" ]; then
        read -ra agents <<< "$(discover_agents)"
    else
        agents=("$target")
    fi

    if [ ${#agents[@]} -eq 0 ]; then
        warn "No agents found"
        return 0
    fi

    local total_linked=0 total_owned=0 total_broken=0 total_missing=0

    for agent in "${agents[@]}"; do
        header "Agent: ${agent}"

        local skills_dir
        skills_dir="$(agent_skills_dir "$agent")"

        if [ ! -d "$skills_dir" ]; then
            warn "Skills dir not found: ${skills_dir}"
            continue
        fi

        local linked=0 owned=0 broken=0

        # Scan each item in agent's skills dir
        for item in "$skills_dir"/*/; do
            [ -e "$item" ] || continue
            local name
            name="$(basename "$item")"
            [ "$name" = ".bundled_manifest" ] && continue

            if [ -L "$item" ]; then
                # It's a symlink
                if [ -e "$item" ]; then
                    local target_path
                    target_path="$(readlink "$item")"
                    if [[ "$target_path" == "$SHARED_SKILLS"* ]]; then
                        echo -e "  ${GREEN}→${NC} ${name}  ${DIM}(core → ${target_path})${NC}"
                        linked=$((linked + 1))
                    else
                        echo -e "  ${CYAN}→${NC} ${name}  ${DIM}(symlink → ${target_path})${NC}"
                        linked=$((linked + 1))
                    fi
                else
                    echo -e "  ${RED}✗${NC} ${name}  ${DIM}(BROKEN symlink)${NC}"
                    broken=$((broken + 1))
                fi
            elif [ -d "$item" ]; then
                echo -e "  ${YELLOW}★${NC} ${name}  ${DIM}(agent-owned)${NC}"
                owned=$((owned + 1))
            fi
        done

        # Check for core skills NOT linked to this agent
        local unlinked=0
        for core_dir in "$SHARED_SKILLS"/*/; do
            [ -d "$core_dir" ] || continue
            local core_name
            core_name="$(basename "$core_dir")"
            [ "$core_name" = "templates" ] && continue

            if [ ! -e "${skills_dir}/${core_name}" ]; then
                unlinked=$((unlinked + 1))
            fi
        done

        echo ""
        echo -e "  Summary: ${GREEN}${linked} core-linked${NC}  ${YELLOW}${owned} agent-owned${NC}  ${RED}${broken} broken${NC}  ${DIM}${unlinked} available${NC}"

        total_linked=$((total_linked + linked))
        total_owned=$((total_owned + owned))
        total_broken=$((total_broken + broken))
        total_missing=$((total_missing + unlinked))
    done

    if [ ${#agents[@]} -gt 1 ]; then
        header "Total"
        echo -e "  ${GREEN}${total_linked} core-linked${NC}  ${YELLOW}${total_owned} agent-owned${NC}  ${RED}${total_broken} broken${NC}  ${DIM}${total_missing} unlinked${NC}"
    fi
}

# ── Sync ──────────────────────────────────────────────────────────────────────

cmd_sync() {
    local target="${1:-all}"

    [ -d "$SHARED_SKILLS" ] || die "Core skills dir not found: ${SHARED_SKILLS}"

    if [ "$DRY_RUN" = false ]; then
        info "This will symlink core skills into agent profiles."
        info "Agent-owned skills will NOT be touched."
        info "Run with --dry-run first to preview."
        echo ""
        read -rp "$(echo -e "${CYAN}?${NC} Proceed? [n]: ")" confirm
        [[ "$confirm" =~ ^[Yy] ]] || { info "Aborted."; return 0; }
    fi

    local agents
    if [ "$target" = "all" ]; then
        read -ra agents <<< "$(discover_agents)"
    else
        agents=("$target")
    fi

    if [ ${#agents[@]} -eq 0 ]; then
        warn "No agents found"
        return 0
    fi

    local total_linked=0 total_skipped=0 total_fixed=0

    for agent in "${agents[@]}"; do
        header "Syncing: ${agent}"

        local skills_dir
        skills_dir="$(agent_skills_dir "$agent")"

        run mkdir -p "$skills_dir"

        for core_dir in "$SHARED_SKILLS"/*/; do
            [ -d "$core_dir" ] || continue
            local name
            name="$(basename "$core_dir")"
            [ "$name" = "templates" ] && continue

            local target="${skills_dir}/${name}"

            if [ -L "$target" ]; then
                # Already a symlink — check if it points to the right place
                local existing
                existing="$(readlink "$target")"
                if [ "$existing" = "$core_dir" ]; then
                    total_skipped=$((total_skipped + 1))
                    continue
                elif [[ "$existing" == "$SHARED_SKILLS"* ]]; then
                    # Points to old core location — fix it
                    info "Fixing stale symlink: ${name}"
                    run rm -f "$target"
                    run ln -sf "$core_dir" "$target"
                    log "Fixed: ${name}"
                    total_fixed=$((total_fixed + 1))
                else
                    # Points elsewhere — agent-specific symlink, skip
                    total_skipped=$((total_skipped + 1))
                    continue
                fi
            elif [ -d "$target" ]; then
                # Real directory exists — agent-owned skill, don't touch
                total_skipped=$((total_skipped + 1))
                continue
            elif [ -e "$target" ]; then
                # Something else exists — skip
                warn "Skipping ${name}: unexpected file type"
                total_skipped=$((total_skipped + 1))
                continue
            else
                # Doesn't exist — create symlink
                run ln -sf "$core_dir" "$target"
                log "Linked: ${name}"
                total_linked=$((total_linked + 1))
            fi
        done
    done

    echo ""
    log "Sync complete: ${total_linked} linked, ${total_fixed} fixed, ${total_skipped} skipped (agent-owned or already linked)"
}

# ── Unlink ────────────────────────────────────────────────────────────────────

cmd_unlink_skills() {
    local agent="${1:-}"
    [ -z "$agent" ] && die "Usage: $0 unlink <agent-name>"

    local skills_dir
    skills_dir="$(agent_skills_dir "$agent")"

    [ -d "$skills_dir" ] || die "Skills dir not found: ${skills_dir}"

    if [ "$DRY_RUN" = false ]; then
        info "This will remove core skill symlinks from '${agent}'."
        info "Agent-owned skills will NOT be touched."
        echo ""
        read -rp "$(echo -e "${CYAN}?${NC} Proceed? [n]: ")" confirm
        [[ "$confirm" =~ ^[Yy] ]] || { info "Aborted."; return 0; }
    fi

    local removed=0 kept=0

    for item in "$skills_dir"/*/; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"

        if [ -L "$item" ]; then
            local target
            target="$(readlink "$item")"
            if [[ "$target" == "$SHARED_SKILLS"* ]]; then
                run rm -f "$item"
                log "Removed symlink: ${name}"
                removed=$((removed + 1))
            else
                info "Keeping non-core symlink: ${name}"
                kept=$((kept + 1))
            fi
        else
            kept=$((kept + 1))
        fi
    done

    echo ""
    log "Done: ${removed} core symlinks removed, ${kept} agent skills kept"
}

# ── Diff ──────────────────────────────────────────────────────────────────────

cmd_diff() {
    local agent_a="${1:-}"
    local agent_b="${2:-}"
    [ -z "$agent_a" ] || [ -z "$agent_b" ] && die "Usage: $0 diff <agent-a> <agent-b>"

    local dir_a dir_b
    dir_a="$(agent_skills_dir "$agent_a")"
    dir_b="$(agent_skills_dir "$agent_b")"

    [ -d "$dir_a" ] || die "Skills dir not found for ${agent_a}: ${dir_a}"
    [ -d "$dir_b" ] || die "Skills dir not found for ${agent_b}: ${dir_b}"

    header "Skill Diff: ${agent_a} vs ${agent_b}"

    # Build skill lists
    local skills_a=() skills_b=()
    for d in "$dir_a"/*/; do [ -e "$d" ] && skills_a+=("$(basename "$d")"); done
    for d in "$dir_b"/*/; do [ -e "$d" ] && skills_b+=("$(basename "$d")"); done

    # Sort
    IFS=$'\n' skills_a=($(sort <<<"${skills_a[*]}")); unset IFS
    IFS=$'\n' skills_b=($(sort <<<"${skills_b[*]}")); unset IFS

    declare -A set_a set_b
    for s in "${skills_a[@]}"; do set_a["$s"]=1; done
    for s in "${skills_b[@]}"; do set_b["$s"]=1; done

    echo ""
    echo -e "  ${GREEN}Shared (both):${NC}"
    for s in "${skills_a[@]}"; do
        [ -n "${set_b[$s]:-}" ] && echo "    • ${s}"
    done

    echo ""
    echo -e "  ${YELLOW}Only in ${agent_a}:${NC}"
    local only_a=0
    for s in "${skills_a[@]}"; do
        if [ -z "${set_b[$s]:-}" ]; then
            local type_a="owned"
            [ -L "${dir_a}/${s}" ] && type_a="linked"
            echo "    • ${s}  (${type_a})"
            only_a=$((only_a + 1))
        fi
    done
    [ $only_a -eq 0 ] && echo "    (none)"

    echo ""
    echo -e "  ${CYAN}Only in ${agent_b}:${NC}"
    local only_b=0
    for s in "${skills_b[@]}"; do
        if [ -z "${set_a[$s]:-}" ]; then
            local type_b="owned"
            [ -L "${dir_b}/${s}" ] && type_b="linked"
            echo "    • ${s}  (${type_b})"
            only_b=$((only_b + 1))
        fi
    done
    [ $only_b -eq 0 ] && echo "    (none)"
}

# ── Main ──────────────────────────────────────────────────────────────────────

usage() {
    echo -e "${BOLD}Hermes Skill Scanner v${VERSION}${NC}"
    echo ""
    echo "Usage: $0 [flags] <command> [args]"
    echo ""
    echo "Commands:"
    echo "  scan [agent]        Show skill inventory (all or one agent)"
    echo "  sync [agent]        Link core skills into agent profiles"
    echo "  diff <a> <b>        Compare skills between two agents"
    echo "  unlink <agent>      Remove core symlinks (keep agent skills)"
    echo "  list                List core skills available"
    echo ""
    echo "Flags:"
    echo "  --openclaw, -o      Scan OpenClaw agent dirs (~/.openclaw/agents/)"
    echo "  --dry-run, -n       Preview without modifying"
    echo ""
    echo "Environment:"
    echo "  SHARED_SKILLS_DIR   Core skills path (default: ~/.hermes/skills)"
    echo "  OPENCLAW_ROOT       OpenClaw directory (default: ~/.openclaw)"
    echo "  HERMES_HOME         Base Hermes directory (default: ~/.hermes)"
}

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        scan)   cmd_scan "$@" ;;
        sync)   cmd_sync "$@" ;;
        diff)   cmd_diff "$@" ;;
        unlink) cmd_unlink_skills "$@" ;;
        list)   header "Core Skills"; list_core_skills ;;
        -h|--help|help|"") usage ;;
        *)      die "Unknown command: ${cmd}. Run '$0 help' for usage." ;;
    esac
}

main "$@"

#!/bin/bash
# =============================================================================
# Crew Dissolve Script
# End a crew session and clean up
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREWS_DIR="$RUNTIME_ROOT/crews"
DOCKER_COMPOSE_FILE="$RUNTIME_ROOT/docker-compose.yml"

# Source helpers
source "$SCRIPT_DIR/helpers.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Usage
usage() {
    cat <<EOF
${GREEN}Crew Dissolve Tool${NC}

Usage: $0 <crew_name> [--force]

End a crew session and remove it from the system.

Arguments:
  crew_name    Name of the crew to dissolve

Options:
  --force      Skip confirmation prompt
  --help       Show this help

Examples:
  $0 dev-team
  $0 research-team --force
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            else
                error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CREW_NAME" ]]; then
    error "Crew name is required"
    usage
fi

# Validate crew exists
if [[ ! -d "$CREWS_DIR/$CREW_NAME" ]]; then
    error "Crew '$CREW_NAME' does not exist"
    exit 1
fi

# Get crew info before dissolving
CREW_CHANNEL=$(grep "channel:" "$CREWS_DIR/$CREW_NAME/crew.yaml" | awk '{print $2}' 2>/dev/null || echo "crew-$CREW_NAME")
AGENTS=$(grep "^    - " "$CREWS_DIR/$CREW_NAME/crew.yaml" | sed 's/^    - //' || echo "")

# Confirmation
if [[ "$FORCE" != true ]]; then
    echo ""
    echo -e "${RED}WARNING: This will dissolve crew '$CREW_NAME'${NC}"
    echo ""
    echo "  Channel: $CREW_CHANNEL"
    echo "  Members: $AGENTS"
    echo ""
    echo "The crew will be stopped and removed. Agents will need to"
    echo "be re-added to new crews individually."
    echo ""
    read -rp "Are you sure you want to dissolve this crew? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Crew dissolve cancelled"
        exit 0
    fi
fi

# Dissolve crew
log "Dissolving crew '$CREW_NAME'..."

# Step 1: Stop all agents in the crew
for agent in $AGENTS; do
    if is_service_running "oc-$agent"; then
        log "Stopping agent: $agent"
        docker compose -f "$DOCKER_COMPOSE_FILE" stop "oc-$agent" 2>/dev/null || true
    fi
done

# Step 2: Remove CREW_CHANNEL from docker-compose.yml
log "Removing crew assignments from docker-compose.yml..."
for agent in $AGENTS; do
    TMP_FILE=$(mktemp)
    awk -v agent_id="$agent" '
    /CREW_CHANNEL=/{
        skip=1
        next
    }
    !skip {print}
    ' "$DOCKER_COMPOSE_FILE" > "$TMP_FILE" 2>/dev/null
    mv "$TMP_FILE" "$DOCKER_COMPOSE_FILE"
done

success "Crew assignments removed"

# Step 3: Update crew status
log "Updating crew status..."
TMP_FILE=$(mktemp)
sed "s/status: active/status: dissolved/" "$CREWS_DIR/$CREW_NAME/crew.yaml" > "$TMP_FILE"
mv "$TMP_FILE" "$CREWS_DIR/$CREW_NAME/crew.yaml"

# Add dissolution timestamp
TIMESTAMP=$(date -Iseconds)
echo "dissolved: $TIMESTAMP" >> "$CREWS_DIR/$CREW_NAME/crew.yaml"

# Log dissolution
TIMESTAMP=$(date -Iseconds)
echo "[$TIMESTAMP] Crew '$CREW_NAME' dissolved" >> "$CREWS_DIR/$CREW_NAME/logs/crew.log"

# Step 4: Archive (optionally move to expired directory)
# For now, just leave it for debugging - users can manually delete

success "Crew '$CREW_NAME' dissolved successfully!"
echo ""
echo "Summary:"
echo "  Crew:        $CREW_NAME"
echo "  Channel:     $CREW_CHANNEL"
echo "  Members:     $AGENTS"
echo "  Status:      dissolved"
echo ""
echo "Crew data has been archived in: $CREWS_DIR/$CREW_NAME/"
echo "To completely remove, run: rm -rf $CREWS_DIR/$CREW_NAME"
echo ""
echo "Agents can now be:"
echo "  - Started individually: ./scripts/agent-control.sh start <agent>"
echo "  - Added to new crews:   ./scripts/crew-create.sh <new_crew> <agents>"

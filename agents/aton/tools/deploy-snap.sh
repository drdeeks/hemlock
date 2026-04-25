#!/usr/bin/env bash
# =============================================================================
# deploy-snap.sh — Deploy a Farcaster snap to Neynar hosting
# =============================================================================
#
# Usage:
#   bash tools/deploy-snap.sh <project-name> [tarball-path]
#
# Examples:
#   bash tools/deploy-snap.sh pass-or-yass
#   bash tools/deploy-snap.sh pass-or-yass /tmp/my-snap.tar.gz
#
# What it does:
#   1. Reads deploy_key and project_id from encrypted secrets
#   2. Creates tarball from projects/<name>/ (excluding node_modules, .git, dist)
#   3. Deploys to Neynar hosting with env vars
#   4. Polls build status until ready or failed
#   5. Verifies the live snap returns valid JSON
#
# Prerequisites:
#   - Secrets stored via secret.sh: <project-name>.deploy_key, <project-name>.project_id
#   - NEYNAR_API_KEY and SNAP_PUBLIC_BASE_URL set in the script (edit ENV_VARS below)
#
# =============================================================================
set -euo pipefail

PROJECT_NAME="${1:?Usage: deploy-snap.sh <project-name> [tarball-path]}"
TARBALL="${2:-}"
HERMES_HOME="${HERMES_HOME:-$HOME}"
SECRETS_SCRIPT="$HERMES_HOME/tools/secret.sh"

# ─── Read credentials ─────────────────────────────────────────────
DEPLOY_KEY=$($SECRETS_SCRIPT get "$PROJECT_NAME" deploy_key 2>/dev/null) || {
    echo "❌ No deploy_key found for $PROJECT_NAME. Run: secret.sh set $PROJECT_NAME deploy_key <key>"
    exit 1
}
PROJECT_ID=$($SECRETS_SCRIPT get "$PROJECT_NAME" project_id 2>/dev/null) || {
    echo "❌ No project_id found for $PROJECT_NAME. Run: secret.sh set $PROJECT_NAME project_id <id>"
    exit 1
}

echo "🚀 Deploying $PROJECT_NAME (project: $PROJECT_ID)"

# ─── Create tarball if not provided ────────────────────────────────
if [ -z "$TARBALL" ]; then
    PROJECT_DIR="$HERMES_HOME/projects/$PROJECT_NAME"
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "❌ Project directory not found: $PROJECT_DIR"
        exit 1
    fi
    TARBALL="/tmp/${PROJECT_NAME}-deploy.tar.gz"
    tar czf "$TARBALL" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='*.tar.gz' \
        --exclude='src/server.ts' \
        -C "$PROJECT_DIR" .
    echo "📦 Tarball created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
fi

# ─── Deploy ────────────────────────────────────────────────────────
ENDPOINT=$($SECRETS_SCRIPT get "$PROJECT_NAME" endpoint 2>/dev/null || echo "https://${PROJECT_NAME}.host.neynar.app")

RESPONSE=$(curl -s -X POST "https://api.host.neynar.app/v1/projects/${PROJECT_ID}/deploy" \
    -H "Authorization: Bearer ${DEPLOY_KEY}" \
    -F "files=@${TARBALL}" \
    -F "env={\"NEYNAR_API_KEY\":\"$($SECRETS_SCRIPT get neynar api_key 2>/dev/null || echo '')\",\"SNAP_PUBLIC_BASE_URL\":\"${ENDPOINT}\"}")

DEPLOY_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('deploymentId',''))" 2>/dev/null)
VERSION=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null)
STATUS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('deployStatus','unknown'))" 2>/dev/null)

if [ "$STATUS" = "unknown" ] || [ -z "$DEPLOY_ID" ]; then
    echo "❌ Deploy failed: $RESPONSE"
    exit 1
fi

echo "📋 Version $VERSION — $STATUS (deployment: $DEPLOY_ID)"

# ─── Poll build status ─────────────────────────────────────────────
for i in $(seq 1 12); do
    sleep 10
    POLL=$(curl -s "https://api.host.neynar.app/v1/projects/${PROJECT_ID}/deploy/${DEPLOY_ID}" \
        -H "Authorization: Bearer ${DEPLOY_KEY}")
    STATUS=$(echo "$POLL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('deployment',{}).get('deployStatus','unknown'))" 2>/dev/null)
    echo "  ⏳ $STATUS (${i}0s)"
    if [ "$STATUS" = "ready" ] || [ "$STATUS" = "error" ]; then
        break
    fi
done

if [ "$STATUS" = "error" ]; then
    echo ""
    echo "❌ Build failed. Logs:"
    echo "$POLL" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for l in d.get('deployment',{}).get('buildLogs',[]):
    print('  ', l)
" 2>/dev/null
    exit 1
fi

# ─── Verify live endpoint ──────────────────────────────────────────
echo ""
echo "🔍 Verifying $ENDPOINT ..."
sleep 5
VERIFY=$(curl -s "$ENDPOINT" -H "Accept: application/vnd.farcaster.snap+json")
THEME=$(echo "$VERIFY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('theme',{}).get('accent','?'))" 2>/dev/null)
TITLE=$(echo "$VERIFY" | python3 -c "import json,sys; els=json.load(sys.stdin).get('ui',{}).get('elements',{}); print(els.get('title',{}).get('props',{}).get('content','?'))" 2>/dev/null)

echo "✅ v$VERSION deployed and live!"
echo "   URL: $ENDPOINT"
echo "   Theme: $THEME"
echo "   Title: $TITLE"

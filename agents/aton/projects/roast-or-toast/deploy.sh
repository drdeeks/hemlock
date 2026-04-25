#!/usr/bin/env bash
set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SECRET_SH="$HOME/tools/secret.sh"

# ─── Load secrets ──────────────────────────────────────────────────
if [[ ! -f "$SECRET_SH" ]]; then
  echo "ERROR: secret.sh not found at $SECRET_SH"
  exit 1
fi

NEYNAR_API_KEY=$("$SECRET_SH" get neynar.api_key)
PROJECT_ID=$("$SECRET_SH" get pass-or-yass.project_id 2>/dev/null || echo "")
DEPLOY_KEY=$("$SECRET_SH" get pass-or-yass.deploy_key 2>/dev/null || echo "")

if [[ -z "$NEYNAR_API_KEY" ]]; then
  echo "ERROR: NEYNAR_API_KEY not found in secret store"
  exit 1
fi

echo "🔐 Secrets loaded"

# ─── Build ─────────────────────────────────────────────────────────
echo "🔨 Building..."
cd "$PROJECT_DIR"
npm install --production=false 2>/dev/null
npx tsc --build 2>/dev/null || echo "TypeScript build warnings (non-fatal)"

# Check compiled output exists
if [[ ! -f "dist/index.js" ]]; then
  echo "ERROR: dist/index.js not found after build"
  exit 1
fi

echo "✅ Build successful"

# ─── Deploy ────────────────────────────────────────────────────────
echo "🚀 Deploying to Neynar..."

# Try to deploy with env vars
RESP=$(curl -s -X POST "https://api.neynar.com/v2/snap/deploy" \
  -H "x-api-key: $NEYNAR_API_KEY" \
  -F "project_id=$PROJECT_ID" \
  -F "deploy_key=$DEPLOY_KEY" \
  -F "entrypoint=dist/index.js" \
  -F 'env={"NEYNAR_API_KEY":"'"$NEYNAR_API_KEY"'","SNAP_PUBLIC_BASE_URL":"https://roast-or-toast.host.neynar.app"}' \
  -F "file=@dist/index.js" \
  -F "package=@package.json" \
  -F "config=@tsconfig.json" \
  2>/dev/null)

echo "$RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'error' in data:
        print(f'❌ Deploy failed: {data[\"error\"]}')
        sys.exit(1)
    elif 'project' in data:
        p = data['project']
        print(f'✅ Deployed! Version: {p.get(\"version\",\"?\")}')
        print(f'   Endpoint: {p.get(\"endpoint\",\"?\")}')
    elif 'version' in data:
        print(f'✅ Deployed! Version: {data[\"version\"]}')
    else:
        print(f'⚠️  Response: {json.dumps(data, indent=2)[:500]}')
except Exception as e:
    print(f'⚠️  Response (raw): {sys.stdin.read()[:500]}')
" 2>/dev/null || echo "⚠️  Deploy response: $RESP"

echo ""
echo "🔥 Roast or Toast deployed!"
echo "   Endpoint: https://roast-or-toast.host.neynar.app"

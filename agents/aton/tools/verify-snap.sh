#!/usr/bin/env bash
# =============================================================================
# verify-snap.sh — Verify a live Farcaster snap endpoint
# =============================================================================
#
# Usage:
#   bash tools/verify-snap.sh <url> [action]
#
# Examples:
#   bash tools/verify-snap.sh https://pass-or-yass-v4.host.neynar.app
#   bash tools/verify-snap.sh https://pass-or-yass-v4.host.neynar.app gate_yass
#
# What it checks:
#   1. Snap JSON is returned with correct Accept header
#   2. Theme accent is set
#   3. UI elements are valid
#   4. Button targets use HTTPS
#   5. (Optional) POST simulation with action
#
# Output: JSON summary of snap health
#
# =============================================================================
set -euo pipefail

URL="${1:?Usage: verify-snap.sh <url> [action]}"
ACTION="${2:-}"

echo "🔍 Verifying snap: $URL"
echo ""

# ─── GET: Snap JSON ────────────────────────────────────────────────
SNAP_JSON=$(curl -s "$URL" -H "Accept: application/vnd.farcaster.snap+json" 2>/dev/null)

if [ -z "$SNAP_JSON" ]; then
    echo "❌ No response from snap endpoint"
    exit 1
fi

# Parse with Python
python3 -c "
import json, sys

try:
    snap = json.loads('''$SNAP_JSON''')
except:
    print('❌ Invalid JSON response')
    sys.exit(1)

version = snap.get('version', 'MISSING')
theme = snap.get('theme', {})
accent = theme.get('accent', 'MISSING')
ui = snap.get('ui', {})
root = ui.get('root', 'MISSING')
elements = ui.get('elements', {})

print(f'✅ Snap JSON valid')
print(f'   Version: {version}')
print(f'   Theme accent: {accent}')
print(f'   Root element: {root}')
print(f'   Elements: {len(elements)}')

# Check elements
issues = []
for name, el in elements.items():
    el_type = el.get('type', 'MISSING')
    props = el.get('props', {})
    
    # Check button targets are HTTPS
    if el_type == 'button':
        on = el.get('on', {})
        press = on.get('press', {})
        params = press.get('params', {})
        target = params.get('target', '')
        if target and not target.startswith('https://') and not target.startswith('http://localhost'):
            issues.append(f'Button {name}: target not HTTPS: {target}')
    
    # Check image URLs
    if el_type == 'image':
        url = props.get('url', '')
        if not url:
            issues.append(f'Image {name}: no URL')
    
    print(f'   [{el_type}] {name}')

if issues:
    print()
    print('⚠️  Issues:')
    for issue in issues:
        print(f'   - {issue}')
else:
    print()
    print('✅ All elements valid')
" 2>/dev/null

# ─── GET: HTML Fallback ────────────────────────────────────────────
echo ""
echo "── HTML Fallback ──"
HTML=$(curl -s "$URL" 2>/dev/null)
HAS_DARK_BG=$(echo "$HTML" | grep -c "background:#0D0B14\|background:#1A1528\|linear-gradient" || echo "0")
HAS_WHITE_BG=$(echo "$HTML" | grep -c "\.card{background:#fff" || echo "0")

if [ "$HAS_WHITE_BG" -gt 0 ]; then
    echo "⚠️  White card detected in HTML fallback (use fallbackHtml override)"
elif [ "$HAS_DARK_BG" -gt 0 ]; then
    echo "✅ Dark card in HTML fallback"
else
    echo "ℹ️  No card background detected in HTML"
fi

# ─── Optional: POST simulation ────────────────────────────────────
if [ -n "$ACTION" ]; then
    echo ""
    echo "── POST Simulation: $ACTION ──"
    POST_RESP=$(curl -s -X POST "${URL}/?action=${ACTION}" \
        -H "Accept: application/vnd.farcaster.snap+json" \
        -H "Content-Type: application/json" \
        -d '{"header":"test","payload":"dGVzdA","signature":"test"}' 2>/dev/null)
    
    # Will likely fail JFS validation, but shows the response shape
    python3 -c "
import json
try:
    d = json.loads('''$POST_RESP''')
    if 'error' in d:
        print(f'ℹ️  POST returned error (expected without valid JFS): {d[\"error\"][:100]}')
    else:
        print(f'✅ POST returned valid snap JSON')
        print(f'   Elements: {len(d.get(\"ui\",{}).get(\"elements\",{}))}')
except:
    print(f'ℹ️  POST response not JSON (likely JFS validation error)')
" 2>/dev/null
fi

echo ""
echo "Done."

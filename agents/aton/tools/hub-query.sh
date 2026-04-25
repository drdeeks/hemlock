#!/usr/bin/env bash
# =============================================================================
# hub-query.sh — Query Neynar Hub API (free tier)
# =============================================================================
#
# Usage:
#   bash tools/hub-query.sh <endpoint> [params...]
#
# Examples:
#   bash tools/hub-query.sh castsByFid fid=3 pageSize=5
#   bash tools/hub-query.sh userDataByFid fid=3
#   bash tools/hub-query.sh castsByParent fid=3 hash=0xabc pageSize=3
#   bash tools/hub-query.sh verificationsByFid fid=3
#   bash tools/hub-query.sh reactionsByFid fid=3
#
# What it does:
#   1. Reads NEYNAR_API_KEY from encrypted secrets
#   2. Queries snapchain-api.neynar.com (free Hub API)
#   3. Pretty-prints the response summary
#
# Available Hub endpoints:
#   castsByFid          Get casts by a user
#   castsByParent       Get replies to a cast
#   castById            Get a specific cast
#   userDataByFid       Get user profile data (name, bio, pfp, etc.)
#   verificationsByFid  Get verified addresses
#   reactionsByFid      Get reactions by a user
#   linksByFid          Get follows by a user
#   storageLimitsByFid  Get storage allocation
#
# =============================================================================
set -euo pipefail

ENDPOINT="${1:?Usage: hub-query.sh <endpoint> [params...]}"
shift
HERMES_HOME="${HERMES_HOME:-$HOME}"
SECRETS_SCRIPT="$HERMES_HOME/tools/secret.sh"

# ─── Read API key ──────────────────────────────────────────────────
API_KEY=$($SECRETS_SCRIPT get neynar api_key 2>/dev/null) || {
    echo "❌ No neynar.api_key found. Run: secret.sh set neynar api_key <key>"
    exit 1
}

# ─── Build query string ────────────────────────────────────────────
PARAMS=""
for arg in "$@"; do
    if [ -n "$PARAMS" ]; then
        PARAMS="${PARAMS}&${arg}"
    else
        PARAMS="${arg}"
    fi
done

URL="https://snapchain-api.neynar.com/v1/${ENDPOINT}"
if [ -n "$PARAMS" ]; then
    URL="${URL}?${PARAMS}"
fi

# ─── Query ─────────────────────────────────────────────────────────
RESPONSE=$(curl -s "$URL" -H "x-api-key: $API_KEY" 2>/dev/null)

# ─── Summarize ─────────────────────────────────────────────────────
python3 -c "
import json, sys

try:
    d = json.loads('''$RESPONSE''')
except:
    print('❌ Invalid JSON response')
    print('''$RESPONSE'''[:500])
    sys.exit(1)

if 'error' in d:
    print(f\"❌ Error: {d['error']}\")
    sys.exit(1)

messages = d.get('messages', [])
print(f'Endpoint: $ENDPOINT')
print(f'Messages: {len(messages)}')
print()

for i, msg in enumerate(messages[:10]):
    data = msg.get('data', {})
    msg_type = data.get('type', '?')
    fid = data.get('fid', '?')
    ts = data.get('timestamp', '?')
    hash_short = msg.get('hash', '?')[:16] + '...'
    
    if 'castAddBody' in data:
        body = data['castAddBody']
        text = body.get('text', '')[:80]
        mentions = body.get('mentions', [])
        parent = body.get('parentCastId')
        parent_info = f' → reply to FID {parent[\"fid\"]}' if parent else ''
        embeds = len(body.get('embeds', []))
        print(f'  [{i+1}] FID {fid}{parent_info}')
        print(f'      {text}')
        if mentions:
            print(f'      mentions: {mentions}')
        if embeds:
            print(f'      embeds: {embeds}')
    elif 'userDataBody' in data:
        udb = data['userDataBody']
        print(f'  [{i+1}] {udb.get(\"type\", \"?\")}: {str(udb.get(\"value\", \"\"))[:80]}')
    elif 'verificationAddAddressBody' in data:
        v = data['verificationAddAddressBody']
        print(f'  [{i+1}] Verification: {v.get(\"address\", \"?\")[:20]}...')
    else:
        print(f'  [{i+1}] {msg_type} from FID {fid}')
    print()

if len(messages) > 10:
    print(f'  ... and {len(messages) - 10} more')

# Check for next page
next_page = d.get('nextPageToken')
if next_page:
    print(f'📄 Next page token: {next_page[:30]}...')
" 2>/dev/null

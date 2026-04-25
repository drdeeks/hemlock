#!/usr/bin/env bash
# =============================================================================
# auth-login.sh — Non-interactive OAuth login for Telegram
# =============================================================================
#
# Runs hermes login in the background, captures the auth URL, and waits
# for the user to complete the OAuth flow.
#
# Usage:
#   bash auth-login.sh nous            # Login to Nous Portal
#   bash auth-login.sh openai-codex    # Login to OpenAI Codex
#
# The script:
# 1. Starts hermes login --no-browser in background
# 2. Waits for the auth URL to appear in output
# 3. Prints the URL + device code
# 4. Polls until auth completes or times out
# 5. Reports success/failure
# =============================================================================

set -euo pipefail

PROVIDER="${1:-nous}"
TIMEOUT="${2:-300}"  # 5 minutes default
POLL_INTERVAL=3

TMPDIR=$(mktemp -d)
LOGFILE="$TMPDIR/login.log"
PIDFILE="$TMPDIR/login.pid"

cleanup() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Start login in background
python3 -m hermes_cli.main login --provider "$PROVIDER" --no-browser \
    > "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

# Wait for URL to appear (up to 30 seconds)
elapsed=0
while [ $elapsed -lt 30 ]; do
    if grep -qiE "https?://.*code|device_code|verification_uri|authorize" "$LOGFILE" 2>/dev/null; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

# Extract and display the URL
if grep -qiE "https?://" "$LOGFILE" 2>/dev/null; then
    echo "=== AUTH URL ==="
    grep -oE 'https?://[^ ]+' "$LOGFILE" | head -1
    echo ""
    
    # Extract device code if present
    if grep -qiE "code[: ]+[A-Z0-9]" "$LOGFILE" 2>/dev/null; then
        echo "=== DEVICE CODE ==="
        grep -oE '[A-Z0-9]{4,}-?[A-Z0-9]{4,}' "$LOGFILE" | head -1
        echo ""
    fi
    
    echo "Open the URL above and enter the code to authorize."
    echo "Waiting for completion (timeout: ${TIMEOUT}s)..."
    
    # Poll until login completes
    elapsed=0
    while [ $elapsed -lt "$TIMEOUT" ]; do
        if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            # Process finished
            wait "$(cat "$PIDFILE")" 2>/dev/null
            exit_code=$?
            if [ $exit_code -eq 0 ]; then
                echo "=== SUCCESS ==="
                echo "Login complete. Auth tokens saved."
                exit 0
            else
                echo "=== FAILED ==="
                tail -5 "$LOGFILE"
                exit 1
            fi
        fi
        
        # Check for success in output
        if grep -qiE "success|authenticated|token.*saved|credentials.*saved" "$LOGFILE" 2>/dev/null; then
            echo "=== SUCCESS ==="
            echo "Login complete. Auth tokens saved."
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            exit 0
        fi
        
        # Check for error
        if grep -qiE "error|denied|expired|timeout|revoked" "$LOGFILE" 2>/dev/null; then
            if grep -qiE "revoked|expired" "$LOGFILE" 2>/dev/null; then
                echo "=== FAILED ==="
                echo "Auth session expired or revoked. Try again."
                tail -3 "$LOGFILE"
                exit 1
            fi
        fi
        
        sleep $POLL_INTERVAL
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    echo "=== TIMEOUT ==="
    echo "Timed out after ${TIMEOUT}s. Auth may still be pending."
    echo "Check with: hermes auth list"
    tail -5 "$LOGFILE"
    exit 1
else
    echo "=== ERROR ==="
    echo "Failed to start login. Output:"
    cat "$LOGFILE"
    exit 1
fi

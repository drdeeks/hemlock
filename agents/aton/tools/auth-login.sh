#!/usr/bin/env bash
# =============================================================================
# auth-login.sh — Provider & Model Selection with OAuth
# =============================================================================
#
# CORRECT COMMAND: `hermes model` (NOT `hermes login`)
#   - `hermes model` = interactive provider + model selection + OAuth
#   - `hermes login` = OAuth only (no model selection, different flow)
#
# USAGE FROM HOST TERMINAL (requires interactive TTY):
#   docker exec -it oc-titan hermes model
#   docker exec -it oc-aton hermes model
#   docker exec -it oc-allman hermes model
#
# NOTE: The -it flags are REQUIRED. Without them you get:
#   Error: 'hermes model' requires an interactive terminal.
#
# USAGE FROM THIS SCRIPT (non-interactive contexts like Telegram):
#   bash tools/auth-login.sh
#
# `hermes model` is a fully interactive TUI menu — you pick provider + model
# in the terminal. It does NOT accept --provider as a flag.
# =============================================================================

set -euo pipefail

TIMEOUT="${1:-300}"  # 5 minutes default
POLL_INTERVAL=3

# If we have a TTY, just run hermes model directly
if [ -t 0 ] && [ -t 1 ]; then
    echo "Interactive terminal detected. Running hermes model directly..."
    echo ""
    exec hermes model
fi

# Non-interactive mode — try --no-browser
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

echo "Running hermes model --no-browser in background..."
hermes model --no-browser > "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

# Wait for URL or TTY error (up to 30 seconds)
elapsed=0
while [ $elapsed -lt 30 ]; do
    # URL appeared — auth flow started
    if grep -qiE "https?://.*code|device_code|verification_uri|authorize" "$LOGFILE" 2>/dev/null; then
        break
    fi

    # Process exited early — check for TTY error
    if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        wait "$(cat "$PIDFILE")" 2>/dev/null || true
        echo ""
        echo "=== ERROR: TTY REQUIRED ==="
        echo "hermes model needs an interactive terminal."
        echo ""
        echo "Run from your HOST terminal with -it flags:"
        echo "  docker exec -it oc-titan hermes model"
        echo "  docker exec -it oc-aton hermes model"
        echo "  docker exec -it oc-allman hermes model"
        echo ""
        echo "The -it flags are mandatory. Without them:"
        echo "  Error: 'hermes model' requires an interactive terminal."
        echo ""
        echo "Details:"
        tail -5 "$LOGFILE" 2>/dev/null
        rm -rf "$TMPDIR"
        exit 1
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
            wait "$(cat "$PIDFILE")" 2>/dev/null
            exit_code=$?
            if [ $exit_code -eq 0 ]; then
                echo "=== SUCCESS ==="
                echo "Provider and model configured. Auth tokens saved."
                exit 0
            else
                echo "=== FAILED ==="
                tail -5 "$LOGFILE"
                exit 1
            fi
        fi

        if grep -qiE "success|authenticated|token.*saved|credentials.*saved" "$LOGFILE" 2>/dev/null; then
            echo "=== SUCCESS ==="
            echo "Provider and model configured. Auth tokens saved."
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            exit 0
        fi

        if grep -qiE "revoked|expired" "$LOGFILE" 2>/dev/null; then
            echo "=== FAILED ==="
            echo "Auth session expired or revoked. Try again."
            tail -3 "$LOGFILE"
            exit 1
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
    echo "Failed to start hermes model. Output:"
    cat "$LOGFILE"
    exit 1
fi

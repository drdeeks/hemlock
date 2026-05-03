#!/usr/bin/env bash
set -e

echo "=== GitHub Personal Access Token required ==="
echo "Generate one at: https://github.com/settings/tokens"
echo "(Needs 'repo' scope)"
echo ""
read -rsp "Paste your PAT (input hidden): " GH_TOKEN
echo ""

REPO_URL="https://${GH_TOKEN}@github.com/drdeeks/hemlock.git"

echo "=== Pushing cleaned history to gamma ==="
git push "$REPO_URL" main:gamma --force

echo ""
echo "=== Done. Gamma branch is clean (no LFS objects). ==="

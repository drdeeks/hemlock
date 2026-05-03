#!/usr/bin/env bash
set -e

TOKEN="${1:-$GITHUB_TOKEN}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: bash scripts/fix-lfs-push.sh <your-github-PAT>"
  echo "Generate one at: https://github.com/settings/tokens (needs 'repo' scope)"
  exit 1
fi

REPO_URL="https://${TOKEN}@github.com/drdeeks/hemlock.git"

echo "=== Pushing cleaned history to gamma ==="
git push "$REPO_URL" main:gamma --force

echo ""
echo "=== Done. Gamma branch is clean (no LFS objects). ==="

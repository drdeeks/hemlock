#!/usr/bin/env bash
set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set."
  echo "Add it in Replit Secrets (Tools > Secrets) then re-run."
  exit 1
fi

REPO_URL="https://${GITHUB_TOKEN}@github.com/drdeeks/hemlock.git"

echo "=== Pushing cleaned history to gamma ==="
git push "$REPO_URL" main:gamma --force

echo ""
echo "=== Done. Gamma branch is clean (no LFS objects). ==="

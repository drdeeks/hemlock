#!/usr/bin/env bash
set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set."
  echo "Add it in Replit Secrets (Tools > Secrets) then re-run."
  exit 1
fi

REPO_URL="https://drdeeks:${GITHUB_TOKEN}@github.com/drdeeks/hemlock.git"

echo "=== Pushing cleaned history to main ==="
GIT_ASKPASS=true \
GIT_TERMINAL_PROMPT=0 \
GIT_CONFIG_NOSYSTEM=1 \
  git -c credential.helper='' \
      push "$REPO_URL" main:main --force

echo ""
echo "=== Done. ==="

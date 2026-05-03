#!/usr/bin/env bash
set -e

echo "=== Removing model files from git history ==="
git filter-branch --index-filter \
  'git rm --cached --ignore-unmatch -r scripts/models/ dta-*.tar.gz export-agent.tar.gz' \
  HEAD~5..HEAD

echo ""
echo "=== Pushing cleaned history to gamma ==="
git push origin main:gamma --force

echo ""
echo "=== Done. Gamma branch is clean (no LFS objects). ==="

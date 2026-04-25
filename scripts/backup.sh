#!/bin/bash
# =============================================================================
# Backup Script - Point-in-time snapshots of the runtime
# =============================================================================

set -euo pipefail

if [[ ! -f .env ]]; then
    echo "Error: .env file not found"
    exit 1
fi

source .env

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_ROOT}/${TIMESTAMP}"

echo "Creating backup: $TIMESTAMP"

mkdir -p "$BACKUP_PATH"

# rsync with exclusions for transient data
rsync -a --exclude='node_modules' --exclude='.git' --exclude='__pycache__' \
    --exclude='*.pyc' --exclude='logs/' --exclude='backups/' \
    "${RUNTIME_ROOT}/" "${BACKUP_PATH}/"

# Create tarball
tar -czf "${BACKUP_ROOT}/${TIMESTAMP}.tar.gz" -C "$BACKUP_ROOT" "$TIMESTAMP"

# Clean up uncompressed backup
rm -rf "$BACKUP_PATH"

echo "Backup complete: ${BACKUP_ROOT}/${TIMESTAMP}.tar.gz"
#!/usr/bin/env bash
# restore.sh - Restore Docker volumes of the Icinga and monitoring stacks from a backup.sh archive.
# Usage: ./restore.sh [BACKUP.tar.gz]
# Nothing is stopped or changed before the restore is confirmed.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib-volumes.sh
. ./lib-volumes.sh

BACKUP_FILE_PATH=${1:-}
if [ -z "$BACKUP_FILE_PATH" ]; then
    read -r -p "Enter the full path to the backup TAR.GZ file: " BACKUP_FILE_PATH
fi
if [ ! -f "$BACKUP_FILE_PATH" ]; then
    echo "ERROR: Backup file not found at $BACKUP_FILE_PATH. Aborting restore." >&2
    exit 1
fi
BACKUP_FILE_PATH=$(realpath "$BACKUP_FILE_PATH")

echo "Analyzing backup contents..."
if ! BACKUP_CONTENTS=$(tar -tzf "$BACKUP_FILE_PATH" | sed 's|^\./||' | cut -d/ -f1 | grep -v '^$' | sort -u); then
    echo "ERROR: Cannot read backup file." >&2
    exit 1
fi
if [ -z "$BACKUP_CONTENTS" ]; then
    echo "ERROR: Backup is empty." >&2
    exit 1
fi

echo "Backup contains the following volume data:"
sed 's/^/  - /' <<<"$BACKUP_CONTENTS"

# Map every volume key in the backup to its target volume. Existing volumes
# (also with legacy names) are reused, missing ones get the current project name.
TARGETS=()
KEYS=()
declare -A STACKS=()
WARNINGS=()
echo ""
echo "Determining volumes to restore (project: $PROJECT)..."
while read -r key; do
    if ! compose_file=$(compose_file_for "$key"); then
        WARNINGS+=("Unknown entry '$key' in backup - skipping")
        continue
    fi
    if [ ! -f "$compose_file" ]; then
        WARNINGS+=("Backup contains $key but $compose_file not found - skipping")
        continue
    fi
    target=$(find_volume "$key") || target="${PROJECT}_${key}"
    echo "  Will restore: $key -> $target"
    KEYS+=("$key")
    TARGETS+=("$target")
    STACKS[$compose_file]=1
done <<<"$BACKUP_CONTENTS"

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo "RESTORE WARNINGS:"
    printf '  WARNING: %s\n' "${WARNINGS[@]}"
fi

if [ ${#KEYS[@]} -eq 0 ]; then
    echo "ERROR: No volumes to restore. Either backup is empty or no matching compose files found." >&2
    exit 1
fi

echo ""
read -r -p "WARNING: This will stop the affected stacks and permanently REPLACE the data of the volumes above. Continue? (yes/no): " CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then
    echo "Restore cancelled by user."
    exit 0
fi

for compose_file in "${!STACKS[@]}"; do
    echo "Stopping and removing services from $compose_file..."
    docker compose -f "$compose_file" stop
    docker compose -f "$compose_file" rm -f
done

MOUNTS=()
for i in "${!KEYS[@]}"; do
    key=${KEYS[$i]}
    target=${TARGETS[$i]}
    if ! volume_exists "$target"; then
        echo "  Creating volume: $target"
        docker volume create \
            --label "com.docker.compose.project=$PROJECT" \
            --label "com.docker.compose.volume=$key" \
            "$target" >/dev/null
    fi
    MOUNTS+=(-v "$target:/vols/$key")
done

echo "Starting restore from: $BACKUP_FILE_PATH"
# Empty the target volumes, then extract. Any error aborts with a non-zero exit code.
if ! docker run --rm -v "$BACKUP_FILE_PATH:/backup.tar.gz:ro" "${MOUNTS[@]}" "$HELPER_IMAGE" \
        sh -euc 'for key; do find "/vols/$key" -mindepth 1 -delete; done; tar -xzf /backup.tar.gz -C /vols' sh "${KEYS[@]}"; then
    echo "ERROR: Restore failed. The volumes may be incomplete; services were not started." >&2
    exit 1
fi

echo "Restore successful!"
echo "Restored volumes: ${TARGETS[*]}"
echo ""

for compose_file in "${!STACKS[@]}"; do
    echo "Starting services from $compose_file..."
    docker compose -f "$compose_file" up -d
done

echo ""
echo "Restore process completed!"

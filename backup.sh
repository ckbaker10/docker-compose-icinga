#!/usr/bin/env bash
# backup.sh - Back up the Docker volumes of the Icinga and monitoring stacks.
# Running services are stopped for a consistent copy and started again afterwards,
# also when the backup fails.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib-volumes.sh
. ./lib-volumes.sh

BACKUP_DIR="$PWD/backups"
STAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="monitoring_stack_backup_${STAMP}.tar.gz"
METADATA_FILE="${BACKUP_DIR}/backup_metadata_${STAMP}.txt"

mkdir -p "$BACKUP_DIR"

echo "Discovering existing volumes (project: $PROJECT)..."
MOUNTS=()
KEYS=()
VOLUMES=()
for key in "${ICINGA_VOLUMES[@]}" "${MONITORING_VOLUMES[@]}"; do
    if vol=$(find_volume "$key"); then
        echo "  Found volume: $vol"
        MOUNTS+=(-v "$vol:/vols/$key:ro")
        KEYS+=("$key")
        VOLUMES+=("$vol")
    fi
done

if [ ${#KEYS[@]} -eq 0 ]; then
    echo "No volumes found to back up. Exiting."
    exit 0
fi

# Remember running services per stack so exactly those are started again.
declare -A RUNNING=()
for compose_file in "$ICINGA_COMPOSE" "$MONITORING_COMPOSE"; do
    if [ -f "$compose_file" ]; then
        RUNNING[$compose_file]=$(running_services "$compose_file" | tr '\n' ' ')
    fi
done

restart_services() {
    local compose_file services
    for compose_file in "${!RUNNING[@]}"; do
        services=${RUNNING[$compose_file]}
        if [ -n "${services// /}" ]; then
            echo "Starting services from $compose_file: $services"
            # shellcheck disable=SC2086 # service names are word-split on purpose
            docker compose -f "$compose_file" start $services || echo "WARNING: Could not start services from $compose_file" >&2
        fi
    done
}
trap restart_services EXIT

for compose_file in "${!RUNNING[@]}"; do
    if [ -n "${RUNNING[$compose_file]// /}" ]; then
        echo "Stopping services from $compose_file for a consistent backup..."
        docker compose -f "$compose_file" stop
    fi
done

echo "Creating archive $ARCHIVE..."
if ! docker run --rm -v "${BACKUP_DIR}:/backup" "${MOUNTS[@]}" "$HELPER_IMAGE" \
        tar -czf "/backup/${ARCHIVE}.partial" -C /vols "${KEYS[@]}"; then
    rm -f "${BACKUP_DIR}/${ARCHIVE}.partial"
    echo "ERROR: Backup failed during tar operation." >&2
    exit 1
fi
mv "${BACKUP_DIR}/${ARCHIVE}.partial" "${BACKUP_DIR}/${ARCHIVE}"

cat >"$METADATA_FILE" <<EOF
# Backup Metadata
Backup Date: $(date)
Backup File: ${ARCHIVE}
Compose Project: ${PROJECT}
Volumes Included: ${VOLUMES[*]}
EOF

echo "Backup successful!"
echo "  Archive: ${BACKUP_DIR}/${ARCHIVE}"
echo "  Metadata: $METADATA_FILE"
echo "  Volumes backed up: ${VOLUMES[*]}"

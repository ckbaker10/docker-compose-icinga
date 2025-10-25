#!/bin/bash
# restore.sh - Script to restore Icinga Docker Compose volumes from a backup

# Define variables
PROJECT_NAME="icinga-playground"
VOLUMES_TO_MANAGE="${PROJECT_NAME}_icinga2 ${PROJECT_NAME}_icingaweb ${PROJECT_NAME}_mysql"

# --- USER INPUT ---
# You need to provide the exact path to the backup file you want to restore.
read -p "Enter the full path to the backup TAR.GZ file (e.g., ./backups/${PROJECT_NAME}_volumes_backup_YYYYMMDD_HHMMSS.tar.gz): " BACKUP_FILE_PATH

if [ ! -f "$BACKUP_FILE_PATH" ]; then
    echo "ERROR: Backup file not found at $BACKUP_FILE_PATH. Aborting restore."
    exit 1
fi
# --- END USER INPUT ---

echo "Stopping and removing running services..."
# Use -p to explicitly target the running containers
docker compose -p "${PROJECT_NAME}" stop
docker compose -p "${PROJECT_NAME}" rm -f

# Safety confirmation before deleting data
read -p "WARNING: This will permanently DELETE the current data in the volumes. Continue? (yes/no): " CONFIRMATION
if [[ "$CONFIRMATION" != "yes" ]]; then
    echo "Restore cancelled by user."
    exit 0
fi

echo "Deleting existing Docker volumes: $VOLUMES_TO_MANAGE"
docker volume rm $VOLUMES_TO_MANAGE

echo "Creating empty volumes for the restore..."
for vol in $VOLUMES_TO_MANAGE; do
    docker volume create "$vol"
done

echo "Starting restore from: $BACKUP_FILE_PATH"

# Run a temporary container to extract the archive into the volumes
docker run --rm \
  -v "$(dirname "$BACKUP_FILE_PATH"):/backup_source" \
  -v "${PROJECT_NAME}_icinga2:/vols/icinga2" \
  -v "${PROJECT_NAME}_icingaweb:/vols/icingaweb" \
  -v "${PROJECT_NAME}_mysql:/vols/mysql" \
  alpine /bin/sh -c "\
    echo 'Extracting backup...'; \
    tar -xvpzf /backup_source/$(basename "$BACKUP_FILE_PATH") -C /vols
  "

if [ $? -eq 0 ]; then
    echo "Restore successful!"
else
    echo "Restore failed during tar extraction."
    exit 1
fi

echo "Starting Docker Compose services with restored data..."
# Use -p to ensure the new services are correctly named
docker compose -p "${PROJECT_NAME}" up -d

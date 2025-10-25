#!/bin/bash
# backup.sh - Script to backup Icinga Docker Compose volumes

# Define variables
PROJECT_NAME="icinga-playground"
BACKUP_DIR="$(pwd)/backups"
BACKUP_FILE="${BACKUP_DIR}/${PROJECT_NAME}_volumes_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "Stopping Docker Compose services for a consistent backup..."
# Use -p to explicitly target the running containers
docker compose -p "${PROJECT_NAME}" stop

# Check if services stopped successfully
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to stop Docker Compose services. Aborting backup."
    # Attempt to start services again if stop failed, to leave things as they were
    docker compose -p "${PROJECT_NAME}" start
    exit 1
fi

echo "Starting backup of volumes: ${PROJECT_NAME}_icinga2, ${PROJECT_NAME}_icingaweb, ${PROJECT_NAME}_mysql"

# Run a temporary container to archive the volumes, using the correct prefix
docker run --rm \
  -v "${BACKUP_DIR}:/backup" \
  -v "${PROJECT_NAME}_icinga2:/vols/icinga2:ro" \
  -v "${PROJECT_NAME}_icingaweb:/vols/icingaweb:ro" \
  -v "${PROJECT_NAME}_mysql:/vols/mysql:ro" \
  alpine /bin/sh -c "\
    echo 'Creating tar archive...'; \
    tar -cvzf /backup/$(basename "$BACKUP_FILE") -C /vols .
  "

if [ $? -eq 0 ]; then
    echo "Backup successful! Archive saved to: $BACKUP_FILE"
else
    echo "Backup failed during tar operation."
fi

echo "Starting Docker Compose services back up..."
# Use -p to ensure the correct services are started
docker compose -p "${PROJECT_NAME}" start

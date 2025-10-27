#!/bin/bash
# backup.sh - Script to backup Docker Compose volumes for both Icinga and Monitoring stacks

# Define variables  
BACKUP_DIR="$(pwd)/backups"
BACKUP_FILE="${BACKUP_DIR}/monitoring_stack_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

# Auto-detect project names
CURRENT_DIR_NAME=$(basename "$(pwd)")

# Define volume name patterns to search for (prioritize current directory naming)
ICINGA_VOLUME_PATTERNS="${CURRENT_DIR_NAME}_icinga2 ${CURRENT_DIR_NAME}_icingaweb ${CURRENT_DIR_NAME}_mysql icinga-playground_icinga2 icinga-playground_icingaweb icinga-playground_mysql"
MONITORING_VOLUME_PATTERNS="${CURRENT_DIR_NAME}_influxdb-storage ${CURRENT_DIR_NAME}_chronograf-storage ${CURRENT_DIR_NAME}_grafana-storage influxdb-storage chronograf-storage grafana-storage"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to check if volume exists
volume_exists() {
    docker volume ls --format "{{.Name}}" | grep -q "^$1$"
}

# Function to stop compose services if running
stop_services() {
    local compose_file=$1
    
    if [ -f "$compose_file" ]; then
        echo "Stopping services from $compose_file..."
        docker compose -f "$compose_file" stop 2>/dev/null
    fi
}

# Function to start compose services
start_services() {
    local compose_file=$1
    
    if [ -f "$compose_file" ]; then
        echo "Starting services from $compose_file..."
        docker compose -f "$compose_file" start 2>/dev/null
    fi
}

# Discover existing volumes and track which stacks were active
EXISTING_VOLUMES=""
VOLUME_MOUNTS=""
BACKUP_PATHS=""
ICINGA_STACK_ACTIVE=false
MONITORING_STACK_ACTIVE=false

echo "Discovering existing volumes..."

# Check Icinga volumes (auto-detect naming pattern)
for vol in $ICINGA_VOLUME_PATTERNS; do
    if volume_exists "$vol"; then
        echo "  Found Icinga volume: $vol"
        EXISTING_VOLUMES="$EXISTING_VOLUMES $vol"
        
        # Extract the base volume name (icinga2, icingaweb, mysql)
        if echo "$vol" | grep -q "_icinga2$"; then
            vol_name="icinga2"
        elif echo "$vol" | grep -q "_icingaweb$"; then
            vol_name="icingaweb"
        elif echo "$vol" | grep -q "_mysql$"; then
            vol_name="mysql"
        else
            vol_name="$vol"  # fallback
        fi
        
        VOLUME_MOUNTS="$VOLUME_MOUNTS -v $vol:/vols/$vol_name:ro"
        BACKUP_PATHS="$BACKUP_PATHS $vol_name"
        ICINGA_STACK_ACTIVE=true
    fi
done

# Check Monitoring volumes (auto-detect naming pattern)
for vol in $MONITORING_VOLUME_PATTERNS; do
    if volume_exists "$vol"; then
        echo "  Found monitoring volume: $vol"
        EXISTING_VOLUMES="$EXISTING_VOLUMES $vol"
        
        # Extract the base volume name (influxdb-storage, chronograf-storage, grafana-storage)
        if echo "$vol" | grep -q "_influxdb-storage$" || [ "$vol" = "influxdb-storage" ]; then
            vol_name="influxdb-storage"
        elif echo "$vol" | grep -q "_chronograf-storage$" || [ "$vol" = "chronograf-storage" ]; then
            vol_name="chronograf-storage"  
        elif echo "$vol" | grep -q "_grafana-storage$" || [ "$vol" = "grafana-storage" ]; then
            vol_name="grafana-storage"
        else
            vol_name="$vol"  # fallback
        fi
        
        VOLUME_MOUNTS="$VOLUME_MOUNTS -v $vol:/vols/$vol_name:ro"
        BACKUP_PATHS="$BACKUP_PATHS $vol_name"
        MONITORING_STACK_ACTIVE=true
    fi
done

if [ -z "$EXISTING_VOLUMES" ]; then
    echo "No volumes found to backup. Exiting."
    exit 0
fi

echo "Stopping Docker Compose services for consistent backup..."

# Stop Icinga stack (no -p flag as mentioned)
if [ "$ICINGA_STACK_ACTIVE" = true ]; then
    stop_services "docker-compose.yml"
fi

# Stop Monitoring stack
if [ "$MONITORING_STACK_ACTIVE" = true ]; then
    stop_services "docker-compose-influx-grafana.yml"
fi

echo "Starting backup of volumes:$EXISTING_VOLUMES"

# Create backup metadata
METADATA_FILE="${BACKUP_DIR}/backup_metadata_$(date +%Y%m%d_%H%M%S).txt"
cat > "$METADATA_FILE" << EOF
# Backup Metadata
Backup Date: $(date)
Backup File: $(basename "$BACKUP_FILE")
Volumes Included:$EXISTING_VOLUMES
EOF

# Run backup container with dynamic volume mounts
eval "docker run --rm \
  -v \"${BACKUP_DIR}:/backup\" \
  $VOLUME_MOUNTS \
  alpine /bin/sh -c \"
    echo 'Creating tar archive...'; 
    tar -czf /backup/\$(basename '$BACKUP_FILE') -C /vols $BACKUP_PATHS 2>/dev/null || true
  \""

if [ $? -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
    echo "Backup successful!"
    echo "  Archive: $BACKUP_FILE"
    echo "  Metadata: $METADATA_FILE"
    echo "  Volumes backed up:$EXISTING_VOLUMES"
else
    echo "Backup failed during tar operation."
fi

echo "Starting Docker Compose services back up..."

# Only restart stacks that were originally active
if [ "$ICINGA_STACK_ACTIVE" = true ]; then
    echo "Restarting Icinga stack (was active before backup)..."
    start_services "docker-compose.yml"
fi

if [ "$MONITORING_STACK_ACTIVE" = true ]; then
    echo "Restarting monitoring stack (was active before backup)..."
    start_services "docker-compose-influx-grafana.yml"
fi

echo "Backup process completed."

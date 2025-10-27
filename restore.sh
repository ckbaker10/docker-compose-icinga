#!/bin/bash
# restore.sh - Script to restore Docker Compose volumes from backup for both Icinga and Monitoring stacks

# Define variables
CURRENT_DIR_NAME=$(basename "$(pwd)")

# Define volume name patterns to search for (prioritize current directory naming)
ICINGA_VOLUME_PATTERNS="${CURRENT_DIR_NAME}_icinga2 ${CURRENT_DIR_NAME}_icingaweb ${CURRENT_DIR_NAME}_mysql icinga-playground_icinga2 icinga-playground_icingaweb icinga-playground_mysql"
MONITORING_VOLUME_PATTERNS="${CURRENT_DIR_NAME}_influxdb-storage ${CURRENT_DIR_NAME}_chronograf-storage ${CURRENT_DIR_NAME}_grafana-storage influxdb-storage chronograf-storage grafana-storage"

# --- USER INPUT ---
read -p "Enter the full path to the backup TAR.GZ file: " BACKUP_FILE_PATH

if [ ! -f "$BACKUP_FILE_PATH" ]; then
    echo "ERROR: Backup file not found at $BACKUP_FILE_PATH. Aborting restore."
    exit 1
fi

# Check what's in the backup
echo "Analyzing backup contents..."
BACKUP_CONTENTS_RAW=$(tar -tzf "$BACKUP_FILE_PATH" 2>/dev/null)
BACKUP_CONTENTS=$(echo "$BACKUP_CONTENTS_RAW" | sed 's|^\./||' | cut -d'/' -f1 | sort -u)

if [ $? -ne 0 ] || [ -z "$BACKUP_CONTENTS" ]; then
    echo "ERROR: Cannot read backup file or backup is empty."
    exit 1
fi

# Detect if this is a legacy backup (contains icinga2/icingaweb/mysql directories directly)
IS_LEGACY_BACKUP=false
if echo "$BACKUP_CONTENTS" | grep -q "^icinga2$" && echo "$BACKUP_CONTENTS" | grep -q "^icingaweb$" && echo "$BACKUP_CONTENTS" | grep -q "^mysql$"; then
    # Check if it doesn't contain any monitoring volumes (to distinguish from new backups)
    if ! echo "$BACKUP_CONTENTS" | grep -qE "(influxdb-storage|chronograf-storage|grafana-storage)"; then
        IS_LEGACY_BACKUP=true
        echo "Detected LEGACY backup format (Icinga-only with icinga2/icingaweb/mysql directories)"
    fi
fi

echo "Backup contains the following volume data:"
for item in $BACKUP_CONTENTS; do
    echo "  - $item"
done

if [ "$IS_LEGACY_BACKUP" = true ]; then
    echo ""
    echo "LEGACY BACKUP DETECTED:"
    echo "  This backup will be restored to current volume naming convention:"
    echo "  icinga2 -> ${CURRENT_DIR_NAME}_icinga2"
    echo "  icingaweb -> ${CURRENT_DIR_NAME}_icingaweb"
    echo "  mysql -> ${CURRENT_DIR_NAME}_mysql"
fi

# --- END USER INPUT ---

# Function to stop and remove services
stop_and_remove_services() {
    local compose_file=$1
    
    if [ -f "$compose_file" ]; then
        echo "Stopping services from $compose_file..."
        docker compose -f "$compose_file" stop 2>/dev/null
        docker compose -f "$compose_file" rm -f 2>/dev/null
    fi
}

# Function to start services
start_services() {
    local compose_file=$1
    
    if [ -f "$compose_file" ]; then
        echo "Starting services from $compose_file..."
        docker compose -f "$compose_file" up -d 2>/dev/null
    fi
}

echo "Stopping and removing running services..."

# Stop both stacks (no -p flag for Icinga stack)
stop_and_remove_services "docker-compose.yml"
stop_and_remove_services "docker-compose-influx-grafana.yml"

# Safety confirmation
read -p "WARNING: This will permanently DELETE current volume data and restore from backup. Continue? (yes/no): " CONFIRMATION
if [[ "$CONFIRMATION" != "yes" ]]; then
    echo "Restore cancelled by user."
    exit 0
fi

# Function to check if volume exists
volume_exists() {
    docker volume ls --format "{{.Name}}" | grep -q "^$1$"
}

# Track which stacks had volumes before restore (so we only start what was there)
ICINGA_HAD_VOLUMES=false
MONITORING_HAD_VOLUMES=false

# Check what was there before
for vol in $ICINGA_VOLUME_PATTERNS; do
    if volume_exists "$vol"; then
        ICINGA_HAD_VOLUMES=true
        break
    fi
done

for vol in $MONITORING_VOLUME_PATTERNS; do
    if volume_exists "$vol"; then
        MONITORING_HAD_VOLUMES=true
        break
    fi
done

# Determine which volumes to restore based on what exists and what user wants
VOLUMES_TO_RESTORE=""
VOLUME_MOUNTS=""
RESTORE_WARNINGS=""

echo ""
echo "Determining volumes to restore..."

# Check Icinga volumes (auto-detect naming pattern)
if [ "$IS_LEGACY_BACKUP" = true ]; then
    # For legacy backups, map to current volume naming convention
    if [ -f "docker-compose.yml" ]; then
        for vol_type in icinga2 icingaweb mysql; do
            if echo "$BACKUP_CONTENTS" | grep -q "^$vol_type$"; then
                target_vol="${CURRENT_DIR_NAME}_$vol_type"
                echo "  Will restore legacy Icinga volume: $vol_type -> $target_vol"
                VOLUMES_TO_RESTORE="$VOLUMES_TO_RESTORE $target_vol"
                VOLUME_MOUNTS="$VOLUME_MOUNTS -v $target_vol:/vols/$vol_type"
            fi
        done
    else
        RESTORE_WARNINGS="$RESTORE_WARNINGS\n  WARNING: Legacy backup found but docker-compose.yml not found - skipping"
    fi
else
    # Normal backup processing for existing volumes
    for vol in $ICINGA_VOLUME_PATTERNS; do
        if volume_exists "$vol"; then
            # Extract the base volume name for backup matching
            if echo "$vol" | grep -q "_icinga2$"; then
                backup_name="icinga2"
            elif echo "$vol" | grep -q "_icingaweb$"; then
                backup_name="icingaweb"
            elif echo "$vol" | grep -q "_mysql$"; then
                backup_name="mysql"
            else
                backup_name="$vol"  # fallback
            fi
            
            if echo "$BACKUP_CONTENTS" | grep -q "^$backup_name$"; then
                if [ -f "docker-compose.yml" ]; then
                    echo "  Will restore Icinga volume: $vol (from backup: $backup_name)"
                    VOLUMES_TO_RESTORE="$VOLUMES_TO_RESTORE $vol"
                    VOLUME_MOUNTS="$VOLUME_MOUNTS -v $vol:/vols/$backup_name"
                else
                    RESTORE_WARNINGS="$RESTORE_WARNINGS\n  WARNING: Backup contains $backup_name but docker-compose.yml not found - skipping"
                fi
            fi
        fi
    done
fi

# Check Monitoring volumes (auto-detect naming pattern)  
for vol in $MONITORING_VOLUME_PATTERNS; do
    if volume_exists "$vol"; then
        # Extract the base volume name for backup matching
        if echo "$vol" | grep -q "_influxdb-storage$" || [ "$vol" = "influxdb-storage" ]; then
            backup_name="influxdb-storage"
        elif echo "$vol" | grep -q "_chronograf-storage$" || [ "$vol" = "chronograf-storage" ]; then
            backup_name="chronograf-storage"
        elif echo "$vol" | grep -q "_grafana-storage$" || [ "$vol" = "grafana-storage" ]; then
            backup_name="grafana-storage"
        else
            backup_name="$vol"  # fallback
        fi
        
        if echo "$BACKUP_CONTENTS" | grep -q "^$backup_name$"; then
            if [ -f "docker-compose-influx-grafana.yml" ]; then
                echo "  Will restore monitoring volume: $vol (from backup: $backup_name)"
                VOLUMES_TO_RESTORE="$VOLUMES_TO_RESTORE $vol"
                VOLUME_MOUNTS="$VOLUME_MOUNTS -v $vol:/vols/$backup_name"
            else
                RESTORE_WARNINGS="$RESTORE_WARNINGS\n  WARNING: Backup contains $backup_name but docker-compose-influx-grafana.yml not found - skipping"
            fi
        fi
    fi
done

# Show warnings if any
if [ -n "$RESTORE_WARNINGS" ]; then
    echo ""
    echo "RESTORE WARNINGS:"
    echo -e "$RESTORE_WARNINGS"
    echo ""
    read -p "Continue with partial restore? (yes/no): " CONTINUE_PARTIAL
    if [[ "$CONTINUE_PARTIAL" != "yes" ]]; then
        echo "Restore cancelled by user."
        exit 0
    fi
fi

if [ -z "$VOLUMES_TO_RESTORE" ]; then
    echo "ERROR: No volumes to restore. Either backup is empty or no matching compose files found."
    exit 1
fi

# Delete existing volumes and recreate them
echo "Preparing volumes for restore..."
for vol in $VOLUMES_TO_RESTORE; do
    if volume_exists "$vol"; then
        echo "  Removing existing volume: $vol"
        docker volume rm "$vol" 2>/dev/null || true
    fi
    echo "  Creating volume: $vol"
    docker volume create "$vol" >/dev/null
done

echo "Starting restore from: $BACKUP_FILE_PATH"

# Run restoration with dynamic volume mounts
eval "docker run --rm \
  -v \"$(dirname "$BACKUP_FILE_PATH"):/backup_source\" \
  $VOLUME_MOUNTS \
  alpine /bin/sh -c \"
    echo 'Extracting backup...'; 
    cd /vols && tar -xzf /backup_source/\$(basename '$BACKUP_FILE_PATH') 2>/dev/null
  \""

if [ $? -eq 0 ]; then
    echo "Restore successful!"
    echo "Restored volumes:$VOLUMES_TO_RESTORE"
else
    echo "Restore failed during tar extraction."
    exit 1
fi

echo ""
echo "Starting Docker Compose services with restored data..."

# Only start stacks that had volumes before OR are being restored from backup
SHOULD_START_ICINGA=false
SHOULD_START_MONITORING=false

# Start Icinga if it had volumes before OR we're restoring Icinga volumes OR legacy backup
if [ "$ICINGA_HAD_VOLUMES" = true ] || echo "$VOLUMES_TO_RESTORE" | grep -qE "(icinga2|icingaweb|mysql)" || [ "$IS_LEGACY_BACKUP" = true ]; then
    if [ -f "docker-compose.yml" ]; then
        SHOULD_START_ICINGA=true
    fi
fi

# Start Monitoring if it had volumes before OR we're restoring monitoring volumes
if [ "$MONITORING_HAD_VOLUMES" = true ] || echo "$VOLUMES_TO_RESTORE" | grep -qE "(influxdb|chronograf|grafana)"; then
    if [ -f "docker-compose-influx-grafana.yml" ]; then
        SHOULD_START_MONITORING=true
    fi
fi

# Actually start the services
if [ "$SHOULD_START_ICINGA" = true ]; then
    echo "Starting Icinga stack..."
    start_services "docker-compose.yml"
fi

if [ "$SHOULD_START_MONITORING" = true ]; then
    echo "Starting monitoring stack..."
    start_services "docker-compose-influx-grafana.yml"
fi

# Inform user about what was started
if [ "$SHOULD_START_ICINGA" = false ] && [ "$SHOULD_START_MONITORING" = false ]; then
    echo "No services started (no volumes existed before and none restored)."
elif [ "$SHOULD_START_ICINGA" = false ]; then
    echo "Icinga stack not started (no volumes existed before and none restored)."
elif [ "$SHOULD_START_MONITORING" = false ]; then
    echo "Monitoring stack not started (no volumes existed before and none restored)."
fi

echo ""
echo "Restore process completed!"

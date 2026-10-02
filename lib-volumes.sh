# shellcheck shell=bash
# lib-volumes.sh - Shared helpers for backup.sh and restore.sh (sourced, not executed)

ICINGA_COMPOSE=docker-compose.yml
MONITORING_COMPOSE=docker-compose-influx-grafana.yml
ICINGA_VOLUMES=(icinga2 icingaweb mysql)
MONITORING_VOLUMES=(influxdb-storage chronograf-storage grafana-storage)
# shellcheck disable=SC2034 # used by backup.sh and restore.sh
HELPER_IMAGE=alpine:3

# Compose project name as resolved by Docker Compose (honours COMPOSE_PROJECT_NAME and .env).
project_name() {
    docker compose -f "$ICINGA_COMPOSE" config 2>/dev/null | awk '/^name:/ { print $2; exit }'
}

PROJECT=$(project_name)
if [ -z "$PROJECT" ]; then
    echo "ERROR: Cannot determine the Compose project name from $ICINGA_COMPOSE." >&2
    exit 1
fi

volume_exists() {
    docker volume inspect "$1" >/dev/null 2>&1
}

# Prints the name of the existing Docker volume for a Compose volume key.
# Older setups used the project name "icinga-playground" or unprefixed names.
find_volume() {
    local key=$1 candidate
    for candidate in "${PROJECT}_${key}" "icinga-playground_${key}" "$key"; do
        if volume_exists "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Prints the compose file a volume key belongs to.
compose_file_for() {
    local key=$1 v
    for v in "${ICINGA_VOLUMES[@]}"; do
        [ "$v" = "$key" ] && { echo "$ICINGA_COMPOSE"; return 0; }
    done
    for v in "${MONITORING_VOLUMES[@]}"; do
        [ "$v" = "$key" ] && { echo "$MONITORING_COMPOSE"; return 0; }
    done
    return 1
}

running_services() {
    docker compose -f "$1" ps --services --status running
}

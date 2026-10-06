#!/usr/bin/env bash
# End-to-end acceptance test for both compose stacks.
#
# Copies the compose files into a temporary directory, rewrites names and
# ports so nothing collides with a running installation, starts both stacks
# with Podman and checks the data flow:
#   Icinga 2 API -> Icinga DB (Redis, MariaDB) -> Icinga Web login and host list,
#   Director schema, InfluxDB write/query, Chronograf and Grafana health.
# All containers, volumes and networks of the test are removed afterwards
# unless E2E_KEEP=1. Nothing is pushed.
#
# Usage: tests/e2e/run.sh
# Environment (all optional):
#   E2E_ENGINE     container engine         (default: podman)
#   E2E_COMPOSE    compose command          (default: podman-compose)
#   E2E_PROJECT    project/resource prefix  (default: icinga-e2e)
#   E2E_PORT_BASE  first of 6 host ports    (default: 13060)
#   E2E_TIMEOUT    seconds per wait         (default: 300)
#   E2E_KEEP       1 = keep stacks and work dir

set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
ENGINE=${E2E_ENGINE:-podman}
read -r -a COMPOSE <<<"${E2E_COMPOSE:-podman-compose}"
PROJECT=${E2E_PROJECT:-icinga-e2e}
BASE=${E2E_PORT_BASE:-13060}
TIMEOUT=${E2E_TIMEOUT:-300}
WEB_PORT=$BASE API_PORT=$((BASE + 1)) INFLUX_PORT=$((BASE + 2))
CHRONO_PORT=$((BASE + 3)) GRAFANA_PORT=$((BASE + 4))
BRIDGE=${PROJECT}_monitoring_bridge
GRAPH_PROJECT=${PROJECT}-graph

WORK=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT}.XXXXXX")
FAILURES=0

log() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

core() { (cd "$WORK" && "${COMPOSE[@]}" -p "$PROJECT" -f docker-compose.yml "$@"); }
graph() { (cd "$WORK" && "${COMPOSE[@]}" -p "$GRAPH_PROJECT" -f docker-compose-influx-grafana.yml "$@"); }

container() {
    "$ENGINE" ps -aq --filter "label=com.docker.compose.project=$1" \
        --filter "label=com.docker.compose.service=$2" | head -n 1
}

env_value() { sed -n "s/^$1=//p" "$WORK/.env"; }

cleanup() {
    local rc=$?
    if [ "${E2E_KEEP:-0}" = "1" ]; then
        echo "E2E_KEEP=1: projects $PROJECT and $GRAPH_PROJECT, network $BRIDGE and $WORK kept"
        return "$rc"
    fi
    graph down -v >/dev/null 2>&1 || true
    core down -v >/dev/null 2>&1 || true
    # podman-compose down keeps the networks it created
    local net
    for net in "$BRIDGE" "${PROJECT}_icinga_internal" "${GRAPH_PROJECT}_monitoring_internal"; do
        "$ENGINE" network rm "$net" >/dev/null 2>&1 || true
    done
    rm -rf "$WORK"
    return "$rc"
}
trap cleanup EXIT

prepare() {
    # Tracked files of the working tree, including uncommitted changes
    (cd "$REPO" && git ls-files -z | xargs -0 cp --parents -t "$WORK")
    cp "$REPO/.env.example" "$WORK/.env"
    # Own network/container names and ports; fully qualified images for Podman.
    sed -i -e "s/name: monitoring_bridge/name: $BRIDGE/" \
        -e "s/container_name: \(.*\)/container_name: ${PROJECT}_\1/" \
        -e "s/127\.0\.0\.1:3065:8080/127.0.0.1:$WEB_PORT:8080/" \
        -e "s/127\.0\.0\.1:3070:5665/127.0.0.1:$API_PORT:5665/" \
        -e "s/127\.0\.0\.1:8086:8086/127.0.0.1:$INFLUX_PORT:8086/" \
        -e "s/127\.0\.0\.1:8888:8888/127.0.0.1:$CHRONO_PORT:8888/" \
        -e "s/127\.0\.0\.1:3075:3000/127.0.0.1:$GRAFANA_PORT:3000/" \
        -e '/10\.200\.200\.1:3075:3000/d' \
        -e 's#image: \([a-z0-9-]*\):#image: docker.io/library/\1:#' \
        -e 's#image: \([a-z0-9-]*\)/\([a-z0-9-]*\):#image: docker.io/\1/\2:#' \
        "$WORK/docker-compose.yml" "$WORK/docker-compose-influx-grafana.yml"
    # podman-compose treats any non-empty "external" value as true
    "$ENGINE" network create "$BRIDGE" >/dev/null
}

wait_for() {
    # wait_for DESCRIPTION COMMAND...: retry until COMMAND succeeds
    local what=$1 waited=0
    shift
    until "$@" >/dev/null 2>&1; do
        if [ "$waited" -ge "$TIMEOUT" ]; then
            fail "$what (timeout after ${TIMEOUT}s)"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
    pass "$what"
}

# check: like wait_for, but a failure is only counted and the run continues
check() { wait_for "$@" || true; }

healthy() {
    [ "$("$ENGINE" inspect -f '{{.State.Health.Status}}' "$(container "$1" "$2")" 2>/dev/null)" = healthy ]
}

db() {
    "$ENGINE" exec "$(container "$PROJECT" mysql)" \
        sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$0"' "$1"
}

icingadb_has_host() { [ "$(db 'SELECT COUNT(*) FROM icingadb.host' 2>/dev/null)" -ge 1 ]; }
icingadb_heartbeat() {
    [ "$(db 'SELECT UNIX_TIMESTAMP()*1000-MAX(heartbeat) < 60000 FROM icingadb.icingadb_instance' 2>/dev/null)" = 1 ]
}
director_schema() { [ "$(db 'SELECT COUNT(*) FROM director.director_schema_migration' 2>/dev/null)" -ge 1 ]; }

icinga2_api() {
    curl -skf -u "icingaweb:$(env_value ICINGAWEB_ICINGA2_API_USER_PASSWORD)" \
        "https://127.0.0.1:$API_PORT/v1/status/IcingaApplication" | grep -q '"app"'
}

hosts_page() {
    # hosts_page PASSWORD: logs in as icingaadmin and prints the Icinga DB host list
    local jar token page url="http://127.0.0.1:$WEB_PORT"
    jar=$(mktemp)
    # The login page first redirects to ?_checkCookie=1
    page=$(curl -sL -c "$jar" -b "$jar" "$url/authentication/login")
    token=$(grep -o '<input[^>]*name="CSRFToken"[^>]*>' <<<"$page" |
        sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -n 1)
    curl -s -c "$jar" -b "$jar" -o /dev/null \
        --data-urlencode username=icingaadmin --data-urlencode "password=$1" \
        --data-urlencode uid=form_login --data-urlencode "CSRFToken=$token" \
        --data-urlencode submit_login=Login "$url/authentication/login"
    curl -sL -c "$jar" -b "$jar" "$url/icingadb/hosts"
    rm -f "$jar"
}

web_login() {
    local page
    page=$(hosts_page "$(env_value ICINGAWEB_ADMIN_PASSWORD)")
    grep -q 'authentication/logout' <<<"$page" && grep -q 'icinga2' <<<"$page"
}

wrong_login_rejected() {
    local page
    page=$(hosts_page wrong)
    grep -q 'name="CSRFToken"' <<<"$page" && ! grep -q 'authentication/logout' <<<"$page"
}

influx_roundtrip() {
    local token now
    token=$(env_value INFLUXDB_ADMIN_TOKEN)
    now=$(date +%s)
    curl -sf -XPOST "http://127.0.0.1:$INFLUX_PORT/api/v2/write?org=myorg&bucket=mybucket&precision=s" \
        -H "Authorization: Token $token" --data-binary "e2e,host=test value=42 $now" &&
        curl -sf -XPOST "http://127.0.0.1:$INFLUX_PORT/api/v2/query?org=myorg" \
            -H "Authorization: Token $token" -H 'Content-Type: application/vnd.flux' \
            -H 'Accept: application/csv' \
            --data 'from(bucket:"mybucket") |> range(start: -1h) |> filter(fn:(r)=>r._measurement=="e2e")' |
        grep -q ',42,'
}

http_ok() { curl -sf -o /dev/null "$1"; }

main() {
    echo "Icinga e2e: project $PROJECT, ports $WEB_PORT-$GRAFANA_PORT, work $WORK"
    prepare

    log "Core stack"
    # podman-compose ignores depends_on conditions: start the databases first
    core up -d mysql icingadb-redis >"$WORK/up-db.log" 2>&1
    wait_for "MariaDB healthy" healthy "$PROJECT" mysql || exit 1
    wait_for "Redis healthy" healthy "$PROJECT" icingadb-redis || exit 1
    core up -d >"$WORK/up-core.log" 2>&1
    check "Icinga 2 healthy" healthy "$PROJECT" icinga2
    check "Icinga 2 API answers" icinga2_api
    check "Icinga DB writes hosts to MariaDB" icingadb_has_host
    check "Icinga DB heartbeat is current" icingadb_heartbeat
    check "Director schema migrated" director_schema
    check "Icinga Web login shows the Icinga DB host list" web_login
    wrong_login_rejected && pass "wrong Icinga Web password rejected" || fail "wrong password accepted"

    log "Graphing stack"
    graph up -d >"$WORK/up-graph.log" 2>&1
    wait_for "InfluxDB healthy" healthy "$GRAPH_PROJECT" influxdb || exit 1
    check "InfluxDB write and query with the admin token" influx_roundtrip
    check "Grafana healthy" healthy "$GRAPH_PROJECT" grafana
    check "Grafana API health" http_ok "http://127.0.0.1:$GRAFANA_PORT/api/health"
    check "Chronograf answers" http_ok "http://127.0.0.1:$CHRONO_PORT/"

    log "Result"
    if [ "$FAILURES" -eq 0 ]; then
        echo "All checks passed."
    else
        echo "$FAILURES check(s) failed."
        exit 1
    fi
}

main "$@"

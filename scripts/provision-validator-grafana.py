#!/usr/bin/env python3
"""Provision one scoped Flux source and three anonymous mail dashboards."""

import argparse
import base64
import datetime as dt
import json
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

SOURCE_UID = "iev-influx-flux"
PERIODS = {
    "hour": ("iev_stats_hour", "Testmails pro UTC-Stunde", "now-24h"),
    "day": ("iev_stats_day", "Testmails pro UTC-Tag", "now-30d"),
    "month": ("iev_stats_month", "Testmails pro UTC-Kalendermonat", "now-1y"),
}


def grafana_credentials():
    raw = subprocess.check_output(
        ["docker", "inspect", "-f", "{{json .Config.Env}}", "viz_grafana"], timeout=5,
    )
    values = dict(entry.split("=", 1) for entry in json.loads(raw))
    return values["GF_SECURITY_ADMIN_USER"], values["GF_SECURITY_ADMIN_PASSWORD"]


def request_api(credentials, method, path, payload=None):
    user, password = credentials
    auth = base64.b64encode(f"{user}:{password}".encode()).decode("ascii")
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:3075" + path,
        data=body,
        headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


def datasource(token):
    return {
        "uid": SOURCE_UID,
        "name": "Validator UTC buckets",
        "type": "influxdb",
        "access": "proxy",
        "url": "http://tsdb_influxdb:8086",
        "jsonData": {
            "version": "Flux", "organization": "myorg", "defaultBucket": "iev_stats_hour",
        },
        "secureJsonData": {"token": token},
    }


def panel(period, bucket, panel_id, title, fields, y):
    selected = " or ".join(f'r._field == "{name}"' for name in fields)
    query = (
        f'from(bucket: "{bucket}")\n'
        '  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n'
        f'  |> filter(fn: (r) => r._measurement == "mail_test_count" and ({selected}))\n'
        '  |> keep(columns: ["_time", "_value", "_field"])'
    )
    return {
        "id": panel_id, "title": title, "type": "timeseries",
        "gridPos": {"x": 0, "y": y, "w": 24, "h": 8},
        "datasource": {"type": "influxdb", "uid": SOURCE_UID},
        "targets": [{
            "refId": "A", "datasource": {"type": "influxdb", "uid": SOURCE_UID},
            "query": query,
        }],
        "fieldConfig": {"defaults": {"unit": "short", "decimals": 0}, "overrides": []},
        "options": {"legend": {"showLegend": True, "displayMode": "list", "placement": "bottom"}},
        "description": f"Exact UTC {period} bucket timestamps; known=0 marks migration overlap.",
    }


def dashboard(period):
    bucket, title, default_range = PERIODS[period]
    return {
        "uid": f"iev-stats-{period}", "title": title,
        "description": "Anonymous test mail counts. The current interval is incomplete; earlier migration intervals may be partial.",
        "schemaVersion": 41, "version": 0, "timezone": "utc", "refresh": "5m",
        "time": {"from": default_range, "to": "now"},
        "tags": ["incoming-email-validator", "anonymous"],
        "templating": {"list": []},
        "panels": [
            panel(period, bucket, 1, "Gesamt", ("total",), 0),
            panel(period, bucket, 2, "Nach Modus", tuple("mode_" + mode for mode in
                  ("check", "bounce", "reply", "other")), 8),
            panel(period, bucket, 3, "Nach Ergebnis", tuple("status_" + status for status in
                  ("ohne_festgestellte_probleme", "auffaellig", "unvollstaendig", "other")), 16),
            panel(period, bucket, 4, "Datenstatus (1 = vollständig)", ("known", "complete"), 24),
        ],
    }


def provision(token):
    credentials = grafana_credentials()
    try:
        request_api(credentials, "GET", "/api/datasources/uid/" + SOURCE_UID)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        method, path = "POST", "/api/datasources"
    else:
        method, path = "PUT", "/api/datasources/uid/" + SOURCE_UID
    request_api(credentials, method, path, datasource(token))
    health = request_api(credentials, "GET", "/api/datasources/uid/" + SOURCE_UID + "/health")
    if health.get("status") != "OK":
        raise ValueError("Grafana InfluxDB source unhealthy")
    for period in PERIODS:
        result = request_api(credentials, "POST", "/api/dashboards/db", {
            "dashboard": dashboard(period), "overwrite": True, "message": "Versioned validator dashboard",
        })
        if result.get("uid") != f"iev-stats-{period}":
            raise ValueError("Grafana dashboard UID mismatch")
        print("dashboard=" + result["uid"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--read-token-file", required=True)
    args = parser.parse_args()
    try:
        token = pathlib.Path(args.read_token_file).read_text(encoding="ascii").strip()
        if not token:
            raise ValueError("missing Grafana read token")
        provision(token)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, subprocess.TimeoutExpired,
            urllib.error.HTTPError) as error:
        print(f"Grafana provisioning failed ({type(error).__name__})", file=sys.stderr)
        return 1
    print("Grafana validator views ready at " + dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

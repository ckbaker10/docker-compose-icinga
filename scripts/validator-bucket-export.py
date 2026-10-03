#!/usr/bin/env python3
"""Idempotently copy validator UTC buckets into three InfluxDB v2 buckets."""

import argparse
import datetime as dt
import fcntl
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

PERIODS = ("hour", "day", "month")
MODES = ("check", "bounce", "reply", "other")
STATUSES = ("ohne_festgestellte_probleme", "auffaellig", "unvollstaendig", "other")
BUCKETS = {"hour": "iev_stats_hour", "day": "iev_stats_day", "month": "iev_stats_month"}


def parse_time(value):
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError("UTC timestamp required")
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def stamp(value):
    return value.isoformat().replace("+00:00", "Z")


def floor(period, value):
    if period == "hour":
        return value.replace(minute=0, second=0, microsecond=0)
    if period == "day":
        return value.replace(hour=0, minute=0, second=0, microsecond=0)
    return value.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def next_bucket(period, value):
    if period == "hour":
        return value + dt.timedelta(hours=1)
    if period == "day":
        return value + dt.timedelta(days=1)
    month = value.year * 12 + value.month
    return value.replace(year=month // 12, month=month % 12 + 1)


def chunk_end(period, start, limit):
    end = start
    for _ in range(256):
        if end >= limit:
            break
        end = next_bucket(period, end)
    return end


def source_series(cfg, period, start, end):
    command = f"stats {period} {stamp(start)} {stamp(end)}"
    result = subprocess.run(
        [
            "ssh", "-F", "/dev/null", "-i", cfg["ssh_key"],
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
            "-o", "UserKnownHostsFile=" + cfg["known_hosts"],
            "-p", str(cfg["ssh_port"]), cfg["ssh_user"] + "@" + cfg["ssh_host"], command,
        ],
        capture_output=True, timeout=15, check=False,
    )
    if result.returncode or len(result.stdout) > 256 * 1024:
        raise ValueError("validator series unavailable")
    series = json.loads(result.stdout)
    if not isinstance(series, list):
        raise ValueError("invalid validator series")
    expected = start
    for item in series:
        if item.get("start") != stamp(expected):
            raise ValueError("missing or reordered validator bucket")
        expected = next_bucket(period, expected)
    if expected != end:
        raise ValueError("incomplete validator series")
    return series


def line(period, item):
    start = parse_time(item["start"])
    total = item["total"]
    if type(total) is not int or total < 0:
        raise ValueError("invalid total")
    fields = {"total": total}
    for dimension, names, prefix in (
        ("by_mode", MODES, "mode"),
        ("by_status", STATUSES, "status"),
    ):
        values = item[dimension]
        if set(values) != set(names) or any(type(values[name]) is not int or values[name] < 0 for name in names):
            raise ValueError("invalid bucket dimensions")
        if sum(values.values()) != total:
            raise ValueError("inconsistent bucket dimensions")
        fields.update({f"{prefix}_{name}": values[name] for name in names})
    for name in ("known", "complete"):
        if type(item[name]) is not bool:
            raise ValueError("invalid bucket marker")
        fields[name] = int(item[name])
    values = ",".join(f"{name}={value}i" for name, value in fields.items())
    timestamp = int(start.timestamp()) * 1_000_000_000
    return f"mail_test_count,period={period} {values} {timestamp}\n"


def write_influx(cfg, token, period, items):
    payload = "".join(line(period, item) for item in items).encode("ascii")
    if not payload:
        return
    query = urllib.parse.urlencode({"org": cfg["influx_org"], "bucket": BUCKETS[period], "precision": "ns"})
    request = urllib.request.Request(
        "http://127.0.0.1:8086/api/v2/write?" + query,
        data=payload,
        headers={"Authorization": "Token " + token, "Content-Type": "text/plain"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 204:
            raise ValueError("InfluxDB write failed")


def save_state(path, state):
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=".cursor-", delete=False,
    ) as stream:
        temporary = pathlib.Path(stream.name)
        os.fchmod(stream.fileno(), 0o600)
        json.dump(state, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def run(cfg):
    state_path = pathlib.Path(cfg["state_file"])
    lock_path = state_path.with_suffix(".lock")
    with open(lock_path, "a+b") as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
        token = pathlib.Path(cfg["influx_token_file"]).read_text(encoding="ascii").strip()
        if not token:
            raise ValueError("missing InfluxDB token")
        now = dt.datetime.now(dt.timezone.utc)
        next_state = dict(state)
        for period in PERIODS:
            start = parse_time(state.get(period, cfg["initial"][period]))
            current = floor(period, now)
            if start != floor(period, start) or start > current:
                raise ValueError("invalid statistics cursor")
            limit = next_bucket(period, current)
            while start < limit:
                end = chunk_end(period, start, limit)
                write_influx(cfg, token, period, source_series(cfg, period, start, end))
                start = end
            next_state[period] = stamp(current)
        save_state(state_path, next_state)
    return next_state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    try:
        cfg = json.loads(pathlib.Path(args.config).read_text(encoding="utf-8"))
        state = run(cfg)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"validator bucket export failed ({type(exc).__name__})", file=sys.stderr)
        return 1
    print("validator bucket export ok " + " ".join(f"{p}={state[p]}" for p in PERIODS))
    return 0


if __name__ == "__main__":
    sys.exit(main())

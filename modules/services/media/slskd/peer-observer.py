#!/usr/bin/env python3
"""Observe conntrack NEW events and export privacy-preserving geographic cells."""

import argparse
import ipaddress
import json
import os
import re
import selectors
import signal
import sqlite3
import subprocess
import tempfile
import time

FLOW = re.compile(r"\bsrc=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+)")


def label(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def atomic_write(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=".peer-observer-", dir=os.path.dirname(path), text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_state(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as source:
            state = json.load(source)
            if isinstance(state, dict):
                return state
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return {"cells": {}, "flows": 0, "lookup_failures": 0, "last_event": 0}


def save_state(path: str, state: dict) -> None:
    atomic_write(path, json.dumps(state, separators=(",", ":"), sort_keys=True) + "\n")


def render_metrics(path: str, state: dict, service: str) -> None:
    lines = [
        "# HELP service_peer_geo_last_seen_seconds Unix timestamp of the newest observed connection in a geographic cell.",
        "# TYPE service_peer_geo_last_seen_seconds gauge",
        "# HELP service_peer_geo_connections_total Connections observed in a geographic cell.",
        "# TYPE service_peer_geo_connections_total counter",
    ]
    for cell in state["cells"].values():
        labels = {
            "service": service,
            "cell": cell["cell"],
            "country": cell["country"],
            "region": cell["region"],
            "city": cell["city"],
            "label": cell["label"],
            "latitude": cell["latitude"],
            "longitude": cell["longitude"],
        }
        encoded = ",".join(f'{key}="{label(value)}"' for key, value in labels.items())
        lines.append(
            f"service_peer_geo_last_seen_seconds{{{encoded}}} {cell['last_seen']}"
        )
        lines.append(
            f"service_peer_geo_connections_total{{{encoded}}} {cell['connections']}"
        )
    lines.extend(
        [
            "# HELP peer_observer_flows_total New globally routed flows observed.",
            "# TYPE peer_observer_flows_total counter",
            f'peer_observer_flows_total{{service="{label(service)}"}} {state["flows"]}',
            "# HELP peer_observer_geo_lookup_failures_total Globally routed flows absent from the location database.",
            "# TYPE peer_observer_geo_lookup_failures_total counter",
            f'peer_observer_geo_lookup_failures_total{{service="{label(service)}"}} {state["lookup_failures"]}',
            "# HELP peer_observer_unique_cells Number of retained geographic cells.",
            "# TYPE peer_observer_unique_cells gauge",
            f'peer_observer_unique_cells{{service="{label(service)}"}} {len(state["cells"])}',
            "# HELP peer_observer_last_event_timestamp_seconds Unix timestamp of the newest observed flow.",
            "# TYPE peer_observer_last_event_timestamp_seconds gauge",
            f'peer_observer_last_event_timestamp_seconds{{service="{label(service)}"}} {state["last_event"]}',
        ]
    )
    atomic_write(path, "\n".join(lines) + "\n")


class Locator:
    def __init__(self, path: str):
        self.path = path
        self.mtime = 0.0
        self.database = None

    def lookup(self, address: ipaddress.IPv4Address):
        mtime = os.stat(self.path).st_mtime
        if self.database is None or mtime != self.mtime:
            if self.database is not None:
                self.database.close()
            self.database = sqlite3.connect(f"file:{self.path}?mode=ro", uri=True)
            self.mtime = mtime
        number = int(address)
        row = self.database.execute(
            "SELECT range_end, country, region, city, latitude, longitude "
            "FROM location WHERE range_start <= ? ORDER BY range_start DESC LIMIT 1",
            (number,),
        ).fetchone()
        return row[1:] if row and number <= row[0] else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--retention-days", type=int, default=90)
    args = parser.parse_args()

    state = load_state(args.state)
    locator = Locator(args.database)
    process = subprocess.Popen(
        [
            "conntrack",
            "--event",
            "--event-mask",
            "NEW",
            "--output",
            "extended",
            "--buffer-size",
            "1048576",
        ],
        stdout=subprocess.PIPE,
        stderr=None,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    dirty = True
    last_flush = 0.0
    source = ipaddress.ip_address(args.source)

    while not stopping:
        events = selector.select(timeout=5)
        for _key, _mask in events:
            line = process.stdout.readline()
            if not line:
                stopping = True
                break
            match = FLOW.search(line)
            if not match:
                continue
            source_text, destination_text, _source_port, _destination_port = (
                match.groups()
            )
            if source_text != str(source):
                continue
            try:
                destination = ipaddress.ip_address(destination_text)
            except ValueError:
                continue
            if (
                not isinstance(destination, ipaddress.IPv4Address)
                or not destination.is_global
            ):
                continue
            now = int(time.time())
            state["flows"] += 1
            state["last_event"] = now
            location = locator.lookup(destination)
            if location is None:
                state["lookup_failures"] += 1
                dirty = True
                continue
            country, region, city, latitude, longitude = location
            cell_latitude = round(float(latitude) * 2) / 2
            cell_longitude = round(float(longitude) * 2) / 2
            cell_name = f"{cell_latitude:.1f},{cell_longitude:.1f}"
            cell = state["cells"].setdefault(
                cell_name,
                {
                    "cell": cell_name,
                    "country": country,
                    "region": region,
                    "city": city,
                    "label": ", ".join(
                        value for value in (city, region, country) if value
                    ),
                    "latitude": f"{cell_latitude:.1f}",
                    "longitude": f"{cell_longitude:.1f}",
                    "connections": 0,
                    "last_seen": 0,
                },
            )
            cell["connections"] += 1
            cell["last_seen"] = now
            dirty = True

        now_monotonic = time.monotonic()
        if dirty and now_monotonic - last_flush >= 5:
            cutoff = int(time.time()) - args.retention_days * 86400
            state["cells"] = {
                name: cell
                for name, cell in state["cells"].items()
                if cell["last_seen"] >= cutoff
            }
            save_state(args.state, state)
            render_metrics(args.metrics, state, args.service)
            last_flush = now_monotonic
            dirty = False

    process.terminate()
    process.wait(timeout=10)
    save_state(args.state, state)
    render_metrics(args.metrics, state, args.service)


if __name__ == "__main__":
    main()

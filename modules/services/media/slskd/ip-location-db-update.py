#!/usr/bin/env python3
"""Download sapics/ip-location-db and atomically build an indexed SQLite DB."""

import argparse
import csv
import gzip
import hashlib
import ipaddress
import os
import sqlite3
import tempfile
import urllib.request


def download(url: str, destination: str) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": "nixos-peer-observer/1"}
    )
    with (
        urllib.request.urlopen(request, timeout=120) as response,
        open(destination, "wb") as output,
    ):
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--checksum-url", required=True)
    args = parser.parse_args()

    directory = os.path.dirname(args.database)
    os.makedirs(directory, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=directory) as temporary:
        archive = os.path.join(temporary, "city.csv.gz")
        checksum_file = os.path.join(temporary, "city.csv.gz.sha256")
        candidate = os.path.join(temporary, "locations.sqlite")
        download(args.url, archive)
        download(args.checksum_url, checksum_file)

        expected = open(checksum_file, encoding="ascii").read().split()[0].lower()
        digest = hashlib.sha256()
        with open(archive, "rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise RuntimeError(
                "downloaded geolocation database failed its SHA-256 check"
            )

        database = sqlite3.connect(candidate)
        database.executescript("""
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            CREATE TABLE location (
                range_start INTEGER PRIMARY KEY,
                range_end INTEGER NOT NULL,
                country TEXT NOT NULL,
                region TEXT NOT NULL,
                city TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        """)
        rows = []
        with gzip.open(archive, "rt", encoding="utf-8", newline="") as source:
            for row in csv.reader(source):
                if len(row) != 10:
                    continue
                (
                    start,
                    end,
                    country,
                    state1,
                    state2,
                    city,
                    _postcode,
                    latitude,
                    longitude,
                    _timezone,
                ) = row
                try:
                    start_number = int(ipaddress.IPv4Address(start))
                    end_number = int(ipaddress.IPv4Address(end))
                    lat = float(latitude)
                    lon = float(longitude)
                except ValueError:
                    continue
                rows.append(
                    (
                        start_number,
                        end_number,
                        country,
                        state2 or state1,
                        city,
                        lat,
                        lon,
                    )
                )
                if len(rows) == 10000:
                    database.executemany(
                        "INSERT INTO location VALUES (?, ?, ?, ?, ?, ?, ?)", rows
                    )
                    rows.clear()
        if rows:
            database.executemany(
                "INSERT INTO location VALUES (?, ?, ?, ?, ?, ?, ?)", rows
            )
        database.execute("INSERT INTO metadata VALUES ('sha256', ?)", (expected,))
        database.execute("INSERT INTO metadata VALUES ('source', ?)", (args.url,))
        database.commit()
        database.execute("PRAGMA optimize")
        database.close()
        os.chmod(candidate, 0o644)
        os.replace(candidate, args.database)


if __name__ == "__main__":
    main()

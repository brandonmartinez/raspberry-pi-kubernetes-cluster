#!/usr/bin/env python3
"""Pi-hole v6 gravity sync.

Exports the Teleporter backup from pihole-0 (primary) and restores it to
pihole-1 and pihole-2 (secondaries) using the Pi-hole v6 REST API.

Pi-hole v6 API flow:
  POST   /api/auth       {"password": "..."} → session.sid
  GET    /api/teleporter sid:<SID>           → tar.gz binary (gravity + config)
  POST   /api/teleporter sid:<SID>           → multipart file restore
  DELETE /api/auth       sid:<SID>           → logout

NOTE: Orbital Sync (ghcr.io/mattwebbio/orbital-sync) was the preferred tool but
was archived March 2025 without Pi-hole v6 support. This script replicates its
function directly against the v6 API using only Python stdlib.
"""

import json
import os
import sys
import urllib.error
import urllib.request

NAMESPACE = "pihole"
HEADLESS_SVC = "pihole"
CLUSTER_DOMAIN = "svc.cluster.local"

PRIMARY_HOST = f"pihole-0.{HEADLESS_SVC}.{NAMESPACE}.{CLUSTER_DOMAIN}"
SECONDARY_HOSTS = [
    f"pihole-1.{HEADLESS_SVC}.{NAMESPACE}.{CLUSTER_DOMAIN}",
    f"pihole-2.{HEADLESS_SVC}.{NAMESPACE}.{CLUSTER_DOMAIN}",
]

PASSWORD = os.environ["PIHOLE_PASSWORD"]


def api(host: str, path: str) -> str:
    return f"http://{host}/api/{path}"


def authenticate(host: str) -> str:
    """POST /api/auth → return session SID."""
    body = json.dumps({"password": PASSWORD}).encode()
    req = urllib.request.Request(
        api(host, "auth"),
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    sid = data["session"]["sid"]
    print(f"  auth {host}: sid={sid[:8]}...", flush=True)
    return sid


def logout(host: str, sid: str) -> None:
    """DELETE /api/auth — best-effort, never raises."""
    req = urllib.request.Request(
        api(host, "auth"),
        method="DELETE",
        headers={"sid": sid},
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as exc:
        print(f"  WARN logout {host}: {exc}", flush=True)


def export_backup(host: str, sid: str) -> bytes:
    """GET /api/teleporter → tar.gz binary."""
    req = urllib.request.Request(
        api(host, "teleporter"),
        headers={"sid": sid},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    print(f"  exported {len(data)} bytes from {host}", flush=True)
    return data


def import_backup(host: str, sid: str, backup: bytes) -> None:
    """POST /api/teleporter with multipart file."""
    boundary = "PiholeGravitySync42"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="gravity.tar.gz"\r\n'
        "Content-Type: application/gzip\r\n"
        "\r\n"
    ).encode() + backup + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        api(host, "teleporter"),
        data=body,
        method="POST",
        headers={
            "sid": sid,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.loads(resp.read())
    print(f"  imported to {host}: {result}", flush=True)


def main() -> None:
    print(f"Pi-hole gravity sync: primary={PRIMARY_HOST}", flush=True)

    primary_sid = authenticate(PRIMARY_HOST)
    try:
        backup = export_backup(PRIMARY_HOST, primary_sid)
    finally:
        logout(PRIMARY_HOST, primary_sid)

    errors: list[tuple[str, Exception]] = []
    for host in SECONDARY_HOSTS:
        print(f"Syncing to {host}", flush=True)
        try:
            sid = authenticate(host)
            try:
                import_backup(host, sid, backup)
            finally:
                logout(host, sid)
        except Exception as exc:
            print(f"  ERROR: {exc}", flush=True)
            errors.append((host, exc))

    if errors:
        failed = [h for h, _ in errors]
        print(f"Sync FAILED for: {failed}", flush=True)
        sys.exit(1)
    print("Sync complete.", flush=True)


if __name__ == "__main__":
    main()

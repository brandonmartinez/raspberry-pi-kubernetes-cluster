#!/usr/bin/env python3
"""Tune Uptime Kuma monitor retry/interval policy (idempotent).

Uptime Kuma stores monitor configuration in its MariaDB database, not in git, so
this script is the reviewable source of truth for the homelab monitor policy. It
re-applies the policy after a database restore or a fresh setup.

Why this policy:
  * Fewer false outages / less Discord noise — monitors need several consecutive
    failed checks (``maxretries``) before they are reported DOWN, so a transient
    blip no longer pages.
  * Gentler on probed services — the normal check ``interval`` is *staggered*
    per monitor so the checks do not all fire in the same instant (a
    thundering-herd on the LAN/services). Uptime Kuma exposes only a per-monitor
    period, so a slightly different period per monitor makes them drift apart.
  * Slower, calmer retries — ``retryInterval`` is widened so a struggling
    service is not hammered while it is being re-checked.

Tiers are detected from the existing normal interval:
  * Internal/LAN monitors (interval <= 120s): maxretries=4, retryInterval=90,
    staggered interval starting at 60s (60, 61, 62, ... by monitor id order).
  * External internet canaries (interval > 120s, e.g. Google/Cloudflare): these
    hit third-party sites, so keep the gentle ~5-minute cadence — maxretries=3,
    retryInterval=90, staggered interval starting at 300s (300, 304, 308, ...).
GROUP monitors are organizational containers and are never probed, so they are
skipped.

Usage:
  # Port-forward the in-cluster service first (the app is ClusterIP-only):
  kubectl -n uptime port-forward svc/uptime-svc 3001:80 &

  # Credentials: either export UK_USER / UK_PASS, or let the script read them
  # from 1Password (op must be signed in or OP_SERVICE_ACCOUNT_TOKEN set):
  scripts/tune-uptime-monitors.py            # apply
  scripts/tune-uptime-monitors.py --dry-run  # show planned changes only

Environment:
  UPTIME_KUMA_URL   Base URL of the Uptime Kuma instance (default
                    http://localhost:3001 — i.e. the port-forward above).
  UK_USER / UK_PASS Admin credentials. If unset, read from 1Password item
                    "uptime" (fields UPTIME_USERNAME / UPTIME_PASSWORD) in the
                    vault named by OP_VAULT (default: homelab).

Requires: pip install uptime-kuma-api
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

# Tier policy. Keep these in one place so review is trivial.
INTERNAL_MAXRETRIES = 4
INTERNAL_INTERVAL_BASE = 60   # seconds; staggered by +1s per monitor
EXTERNAL_MAXRETRIES = 3
EXTERNAL_INTERVAL_BASE = 300  # seconds; staggered by +4s per monitor
EXTERNAL_INTERVAL_STEP = 4
RETRY_INTERVAL = 90           # seconds between re-checks while retrying
INTERNAL_TIER_MAX_INTERVAL = 120  # monitors at/under this are "internal"


def _op_read(ref: str) -> str:
    """Resolve a 1Password secret reference with the op CLI."""
    return subprocess.run(
        ["op", "read", ref],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def _credentials() -> tuple[str, str]:
    user = os.environ.get("UK_USER")
    password = os.environ.get("UK_PASS")
    if user and password:
        return user, password
    vault = os.environ.get("OP_VAULT", "homelab")
    try:
        return (
            _op_read(f"op://{vault}/uptime/UPTIME_USERNAME"),
            _op_read(f"op://{vault}/uptime/UPTIME_PASSWORD"),
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        sys.exit(
            "Could not obtain credentials. Set UK_USER/UK_PASS or sign in to "
            f"1Password (op). Underlying error: {exc}"
        )


def _plan(monitors: list[dict]) -> dict[int, dict]:
    """Build the desired settings per monitor id (deterministic, id-ordered)."""
    probes = sorted(
        (m for m in monitors if str(m.get("type")) != "MonitorType.GROUP"),
        key=lambda m: m["id"],
    )
    internal = [m for m in probes if (m.get("interval") or 0) <= INTERNAL_TIER_MAX_INTERVAL]
    external = [m for m in probes if (m.get("interval") or 0) > INTERNAL_TIER_MAX_INTERVAL]
    plan: dict[int, dict] = {}
    for rank, m in enumerate(internal):
        plan[m["id"]] = {
            "maxretries": INTERNAL_MAXRETRIES,
            "retryInterval": RETRY_INTERVAL,
            "interval": INTERNAL_INTERVAL_BASE + rank,
        }
    for rank, m in enumerate(external):
        plan[m["id"]] = {
            "maxretries": EXTERNAL_MAXRETRIES,
            "retryInterval": RETRY_INTERVAL,
            "interval": EXTERNAL_INTERVAL_BASE + rank * EXTERNAL_INTERVAL_STEP,
        }
    return plan


def main() -> int:
    parser = argparse.ArgumentParser(description="Tune Uptime Kuma monitor retry/stagger policy.")
    parser.add_argument("--dry-run", action="store_true", help="Show planned changes; apply nothing.")
    args = parser.parse_args()

    try:
        from uptime_kuma_api import UptimeKumaApi
    except ImportError:
        sys.exit("uptime-kuma-api is required: pip install uptime-kuma-api")

    url = os.environ.get("UPTIME_KUMA_URL", "http://localhost:3001")
    user, password = _credentials()

    api = UptimeKumaApi(url, timeout=40)
    try:
        api.login(user, password)
        monitors = api.get_monitors()
        plan = _plan(monitors)
        by_id = {m["id"]: m for m in monitors}

        changed = skipped = errors = 0
        for mid, desired in sorted(plan.items()):
            current = by_id[mid]
            if all(current.get(k) == v for k, v in desired.items()):
                skipped += 1
                continue
            name = (current.get("name") or "")[:28]
            summary = (
                f"maxretries={desired['maxretries']} "
                f"interval={desired['interval']} "
                f"retryInterval={desired['retryInterval']}"
            )
            if args.dry_run:
                print(f"  WOULD UPDATE id={mid:>3} {name:<28} -> {summary}")
                changed += 1
                continue
            try:
                api.edit_monitor(mid, **desired)
                print(f"  updated id={mid:>3} {name:<28} -> {summary}")
                changed += 1
            except Exception as exc:  # noqa: BLE001 - report and continue
                print(f"  ERROR  id={mid:>3} {name:<28}: {exc}", file=sys.stderr)
                errors += 1

        verb = "would change" if args.dry_run else "changed"
        print(f"\n{verb}={changed} unchanged={skipped} errors={errors} "
              f"(skipped GROUP monitors are organizational, never probed)")
        return 1 if errors else 0
    finally:
        api.disconnect()


if __name__ == "__main__":
    raise SystemExit(main())

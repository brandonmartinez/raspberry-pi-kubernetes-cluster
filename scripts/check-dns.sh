#!/usr/bin/env bash
# check-dns.sh — Live DNS validation for the dnsdist → Pi-hole stack.
#
# Validates UDP and TCP resolution against the MetalLB VIP and optionally
# against each per-ordinal Pi-hole backend.  All checks are READ-ONLY / NON-
# MUTATING — only DNS queries, no kubectl writes.
#
# USAGE:
#   scripts/check-dns.sh [--vip IP] [--ordinals] [--tcp]
#
# OPTIONS:
#   --vip IP        MetalLB VIP to test (default: 192.168.52.53)
#   --ordinals      Also test each per-ordinal Pi-hole backend directly.
#                   Run from a cluster node or another host with ClusterIP routes.
#   --tcp           Also test DNS-over-TCP in addition to UDP
#
# ENVIRONMENT (override defaults):
#   DNS_VIP         MetalLB VIP (default: 192.168.52.53)
#   TEST_ORDINALS   Set non-empty to enable ordinal backend tests
#   TEST_TCP        Set non-empty to enable TCP tests
#   QUERY_NAME      DNS name to resolve (default: a.root-servers.net)
#
# REQUIREMENTS: dig (from bind-utils or similar). Per-ordinal checks require
# network access to the cluster Service CIDR.
#
# NOTE: This script is NOT wired into scripts/validate.sh because it requires
# live cluster access.  Run it manually after syncing changes to verify the
# full DNS stack end-to-end.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

FAILURES=0
WARNINGS=0

fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
pass() { log "PASS: $*"; }

# --- Defaults ---
DNS_VIP="${DNS_VIP:-192.168.52.53}"
QUERY_NAME="${QUERY_NAME:-a.root-servers.net}"
TEST_ORDINALS="${TEST_ORDINALS:-}"
TEST_TCP="${TEST_TCP:-}"

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vip)
      [[ $# -ge 2 && "${2-}" != --* ]] || { echo "--vip requires a value" >&2; exit 1; }
      DNS_VIP="$2"
      shift 2
      ;;
    --ordinals) TEST_ORDINALS=1;    shift   ;;
    --tcp)      TEST_TCP=1;         shift   ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# Per-ordinal Pi-hole DNS ClusterIPs (must match apps/pihole/service.yml).
PIHOLE_ORDINAL_IPS=(10.43.100.31 10.43.100.32 10.43.100.33)

# --- Pre-flight ---
if ! command -v dig >/dev/null 2>&1; then
  echo "dig is required" >&2
  exit 1
fi

# --- Helper ---
dig_query() {
  local server="$1" proto="$2" name="$3" qtype="${4:-A}"
  local dig_args=(+tries=1 +time=3 +short "@${server}" "${name}" "${qtype}")
  [[ "${proto}" == "tcp" ]] && dig_args+=(+tcp)
  dig "${dig_args[@]}"
}

# --- VIP UDP resolution ---
section "VIP UDP — ${DNS_VIP}"
log "Querying ${QUERY_NAME} A via UDP @ ${DNS_VIP}"
if result=$(dig_query "${DNS_VIP}" udp "${QUERY_NAME}" A 2>&1) && [[ -n "${result}" ]]; then
  pass "VIP UDP: ${QUERY_NAME} → ${result}"
else
  fail "VIP UDP: no response from ${DNS_VIP} for ${QUERY_NAME} (result: '${result:-empty}')"
fi

# --- VIP TCP resolution (opt-in) ---
if [[ -n "${TEST_TCP}" ]]; then
  section "VIP TCP — ${DNS_VIP}"
  log "Querying ${QUERY_NAME} A via TCP @ ${DNS_VIP}"
  if result=$(dig_query "${DNS_VIP}" tcp "${QUERY_NAME}" A 2>&1) && [[ -n "${result}" ]]; then
    pass "VIP TCP: ${QUERY_NAME} → ${result}"
  else
    fail "VIP TCP: no response from ${DNS_VIP} for ${QUERY_NAME}"
  fi
fi

# --- Per-ordinal backend checks (opt-in) ---
if [[ -n "${TEST_ORDINALS}" ]]; then
  section "Per-ordinal Pi-hole backends"
  for i in 0 1 2; do
    ip="${PIHOLE_ORDINAL_IPS[$i]}"
    log "Querying ${QUERY_NAME} A via UDP @ pihole-${i} (${ip})"
    if result=$(dig_query "${ip}" udp "${QUERY_NAME}" A 2>&1) && [[ -n "${result}" ]]; then
      pass "pihole-${i} UDP (${ip}): ${QUERY_NAME} → ${result}"
    else
      fail "pihole-${i} UDP (${ip}): no response for ${QUERY_NAME}"
    fi

    # CHAOS version.bind — same query dnsdist uses for health checks.
    log "Querying version.bind TXT CHAOS @ pihole-${i} (${ip})"
    if result=$(dig +tries=1 +time=3 +short "@${ip}" version.bind TXT CH 2>&1) && [[ -n "${result}" ]]; then
      pass "pihole-${i} CHAOS version.bind (${ip}): ${result}"
    else
      fail "pihole-${i} CHAOS version.bind (${ip}): no response"
    fi

    if [[ -n "${TEST_TCP}" ]]; then
      log "Querying ${QUERY_NAME} A via TCP @ pihole-${i} (${ip})"
      if result=$(dig_query "${ip}" tcp "${QUERY_NAME}" A 2>&1) && [[ -n "${result}" ]]; then
        pass "pihole-${i} TCP (${ip}): ${QUERY_NAME} → ${result}"
      else
        fail "pihole-${i} TCP (${ip}): no response for ${QUERY_NAME}"
      fi
    fi
  done
fi

# --- Failover semantics assertion (static) ---
section "Failover semantics (static assertions)"
conf="${REPO_ROOT}/apps/dnsdist/dnsdist.conf"

# 10.43.100.30 must NOT be a backend address in dnsdist.conf.
if grep -q "10\.43\.100\.30" "${conf}"; then
  fail "STATIC: 10.43.100.30 (shared ClusterIP) still present in dnsdist.conf"
else
  pass "STATIC: 10.43.100.30 not referenced in dnsdist.conf"
fi

# Three per-ordinal backend IPs must be present.
for i in 0 1 2; do
  ip="${PIHOLE_ORDINAL_IPS[$i]}"
  if grep -q "${ip}:53" "${conf}"; then
    pass "STATIC: pihole-${i} backend ${ip}:53 present in dnsdist.conf"
  else
    fail "STATIC: pihole-${i} backend ${ip}:53 missing from dnsdist.conf"
  fi
done

# Backup pool fallback must be present.
if grep -q 'return DNSAction.Pool, "backup"' "${conf}"; then
  pass "STATIC: backup pool fallback present"
else
  fail "STATIC: backup pool fallback missing from dnsdist.conf"
fi

# --- Summary ---
section "DNS check summary"
log "Warnings: ${WARNINGS}"
if [[ ${FAILURES} -gt 0 ]]; then
  echo "DNS check FAILED with ${FAILURES} failure(s)." >&2
  exit 1
fi
log "DNS check PASSED."

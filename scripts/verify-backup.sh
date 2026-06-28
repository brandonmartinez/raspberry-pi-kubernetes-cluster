#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

FAILURES=0

usage() {
  cat <<'USAGE'
Usage: scripts/verify-backup.sh <namespace> [pvc]

Read-only backup gate for data-risking changes.

Checks every PVC in <namespace>, or one named [pvc], and exits 0 only when each
PVC is Longhorn-backed, assigned to a Longhorn backup RecurringJob group, and has
evidence that at least one backup has completed.

Examples:
  scripts/verify-backup.sh uptime
  scripts/verify-backup.sh uptime uptime-data
USAGE
}

need_command() {
  command -v "$1" >/dev/null 2>&1
}

fail_pvc() {
  local pvc=$1
  local message=$2
  echo "FAIL: ${pvc}: ${message}" >&2
  FAILURES=$((FAILURES + 1))
}

pass_pvc() {
  local pvc=$1
  local message=$2
  log "PASS: ${pvc}: ${message}"
}

warn_pvc() {
  local pvc=$1
  local message=$2
  echo "WARN: ${pvc}: ${message}" >&2
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

if ! need_command kubectl; then
  echo "FAIL: kubectl is required for read-only backup verification." >&2
  exit 1
fi

NAMESPACE=$1
REQUESTED_PVC=${2:-}

section "Loading Longhorn backup jobs"
if ! BACKUP_JOBS=$(kubectl -n longhorn-system get recurringjobs.longhorn.io -o json | python3 -c '
import json, sys
for job in json.load(sys.stdin).get("items", []):
    spec = job.get("spec", {}) or {}
    if spec.get("task") != "backup":
        continue
    name = job.get("metadata", {}).get("name", "<unnamed>")
    status = job.get("status", {}) or {}
    try:
        execution_count = int(status.get("executionCount") or 0)
    except (TypeError, ValueError):
        execution_count = 0
    for group in spec.get("groups") or []:
        print(f"{group}\t{name}\t{execution_count}")
'); then
  echo "FAIL: could not list Longhorn RecurringJobs in longhorn-system." >&2
  exit 1
fi

if [[ -z "${BACKUP_JOBS}" ]]; then
  echo "FAIL: no Longhorn backup RecurringJobs found in longhorn-system." >&2
  exit 1
fi

log "Backup RecurringJob groups: $(awk -F '\t' '{print $1 " (" $2 ", executions=" $3 ")"}' <<<"${BACKUP_JOBS}" | paste -sd ', ' -)"

section "Resolving PVCs"
if [[ -n "${REQUESTED_PVC}" ]]; then
  if ! PVC_ROWS=$(kubectl -n "${NAMESPACE}" get pvc "${REQUESTED_PVC}" -o json | python3 -c '
import json, sys
pvc = json.load(sys.stdin)
name = pvc.get("metadata", {}).get("name", "")
spec = pvc.get("spec", {}) or {}
print("\t".join([name, spec.get("volumeName") or "", spec.get("storageClassName") or ""]))
'); then
    echo "FAIL: could not read PVC ${NAMESPACE}/${REQUESTED_PVC}." >&2
    exit 1
  fi
else
  if ! PVC_ROWS=$(kubectl -n "${NAMESPACE}" get pvc -o json | python3 -c '
import json, sys
for pvc in json.load(sys.stdin).get("items", []):
    name = pvc.get("metadata", {}).get("name", "")
    spec = pvc.get("spec", {}) or {}
    print("\t".join([name, spec.get("volumeName") or "", spec.get("storageClassName") or ""]))
'); then
    echo "FAIL: could not list PVCs in namespace ${NAMESPACE}." >&2
    exit 1
  fi
fi

if [[ -z "${PVC_ROWS}" ]]; then
  echo "FAIL: no PVCs found in namespace ${NAMESPACE}." >&2
  exit 1
fi

while IFS=$'\t' read -r pvc pv pvc_storage_class; do
  [[ -n "${pvc}" ]] || continue
  section "Checking ${NAMESPACE}/${pvc}"

  if [[ -z "${pv}" ]]; then
    fail_pvc "${pvc}" "PVC is not bound to a PV yet; no backup can be verified."
    continue
  fi

  if ! pv_storage_class=$(kubectl get pv "${pv}" -o jsonpath='{.spec.storageClassName}'); then
    fail_pvc "${pvc}" "could not resolve bound PV ${pv}."
    continue
  fi

  storage_class=${pv_storage_class:-${pvc_storage_class}}
  log "PVC ${NAMESPACE}/${pvc} -> PV ${pv} (storageClass=${storage_class:-<unset>})"

  if [[ "${storage_class}" != "longhorn" ]]; then
    warn_pvc "${pvc}" "LOUD WARNING: storageClass '${storage_class:-<unset>}' is NOT covered by Longhorn backups. Treat this data as unprotected."
    FAILURES=$((FAILURES + 1))
    continue
  fi

  if ! volume_json=$(kubectl -n longhorn-system get volumes.longhorn.io "${pv}" -o json 2>/dev/null); then
    fail_pvc "${pvc}" "Longhorn volume ${pv} was not found."
    continue
  fi

  volume_info=$(printf '%s' "${volume_json}" | python3 -c '
import json, sys
volume = json.load(sys.stdin)
labels = volume.get("metadata", {}).get("labels", {}) or {}
groups = []
for key, value in labels.items():
    prefix = "recurring-job-group.longhorn.io/"
    if key.startswith(prefix) and str(value).lower() == "enabled":
        groups.append(key[len(prefix):])
last_backup = ((volume.get("status", {}) or {}).get("lastBackup") or "")
print("\t".join([",".join(sorted(groups)), last_backup]))
')
  IFS=$'\t' read -r volume_groups last_backup <<<"${volume_info}"

  if [[ -z "${volume_groups}" ]]; then
    fail_pvc "${pvc}" "Longhorn volume ${pv} has no recurring-job-group.longhorn.io/<group>: enabled label."
    continue
  fi

  configured_group=""
  configured_jobs=""
  max_execution_count=0
  IFS=',' read -ra groups <<<"${volume_groups}"
  for group in "${groups[@]}"; do
    jobs_for_group=$(awk -F '\t' -v group="${group}" '$1 == group {print $2}' <<<"${BACKUP_JOBS}" | paste -sd ',' -)
    group_execution_count=$(awk -F '\t' -v group="${group}" '$1 == group && ($3 + 0) > max {max = $3 + 0} END {print max + 0}' <<<"${BACKUP_JOBS}")
    if [[ -n "${jobs_for_group}" ]]; then
      configured_group=${group}
      configured_jobs=${jobs_for_group}
      max_execution_count=${group_execution_count}
      break
    fi
  done

  if [[ -z "${configured_group}" ]]; then
    fail_pvc "${pvc}" "Longhorn groups '${volume_groups}' are enabled on the volume, but none maps to a task: backup RecurringJob."
    continue
  fi

  log "Backup configured: group '${configured_group}' via job(s) ${configured_jobs}."

  if [[ -n "${last_backup}" ]]; then
    pass_pvc "${pvc}" "backup completed; Longhorn lastBackup=${last_backup}."
  elif [[ ${max_execution_count} -gt 0 ]]; then
    pass_pvc "${pvc}" "backup job has completed ${max_execution_count} time(s); volume lastBackup is empty/unavailable."
  else
    fail_pvc "${pvc}" "backup is configured, but no completed backup was observed (executionCount=0 and lastBackup empty)."
  fi
done <<<"${PVC_ROWS}"

section "Backup verification summary"
if [[ ${FAILURES} -gt 0 ]]; then
  echo "Backup verification failed for ${FAILURES} PVC check(s)." >&2
  exit 1
fi

log "Backup verification passed for namespace ${NAMESPACE}${REQUESTED_PVC:+ PVC ${REQUESTED_PVC}}."

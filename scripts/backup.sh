#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${REPO_ROOT}/_backups/${TS}"
mkdir -p "${BACKUP_DIR}/helm-values" "${BACKUP_DIR}/compiled" "${BACKUP_DIR}/postgres" "${BACKUP_DIR}/longhorn"

section "Capturing Helm state"
helm list -A -o yaml > "${BACKUP_DIR}/helm-list.yaml"
while IFS=$'\t' read -r namespace release; do
  [[ -z "${namespace}" || -z "${release}" ]] && continue
  safe="${namespace}__${release}"
  log "Capturing helm values for ${namespace}/${release}"
  helm get values "${release}" --namespace "${namespace}" --all > "${BACKUP_DIR}/helm-values/${safe}.yaml"
done < <(helm list -A -o json | python3 -c "import json,sys
for r in json.load(sys.stdin):
    print(r.get('namespace','') + '\t' + r.get('name',''))")

section "Capturing Kubernetes inventory"
kubectl get all -A -o wide > "${BACKUP_DIR}/kubectl-get-all.txt"
kubectl get all -A -o yaml > "${BACKUP_DIR}/kubectl-get-all.yaml"

section "Snapshotting compiled manifests"
shopt -s nullglob
for file in "${REPO_ROOT}"/k8s/src/compiled*.yml; do
  log "Copying ${file}"
  cp "${file}" "${BACKUP_DIR}/compiled/"
done
shopt -u nullglob

section "Capturing PostgreSQL dump"
cat > "${BACKUP_DIR}/postgres/README.txt" <<'README'
PostgreSQL dump uses standard pg_dump environment variables:
  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, PGSSLMODE
Set them before running scripts/backup.sh. No credentials are hardcoded here.
README
if command -v pg_dump >/dev/null 2>&1 && [[ -n "${PGHOST:-}" && -n "${PGDATABASE:-}" && -n "${PGUSER:-}" ]]; then
  log "Running pg_dump for ${PGDATABASE} on ${PGHOST}"
  pg_dump --format=custom --file "${BACKUP_DIR}/postgres/${PGDATABASE}.dump"
else
  log "Skipping pg_dump: install pg_dump and set PGHOST, PGDATABASE, PGUSER, and PGPASSWORD/pgpass as needed."
fi

section "Capturing Longhorn inventory"
kubectl -n longhorn-system get volumes,backups -o wide > "${BACKUP_DIR}/longhorn/volumes-backups.txt" 2>&1 || log "Longhorn volume/backup listing failed; see output file."
kubectl -n longhorn-system get volumes,backups -o yaml > "${BACKUP_DIR}/longhorn/volumes-backups.yaml" 2>&1 || true

section "Backup complete"
log "Wrote read-only capture to ${BACKUP_DIR}"

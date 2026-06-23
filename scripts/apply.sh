#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

DRY_RUN=()
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=(--dry-run=server)
  shift
elif [[ "${1:-}" == "--dry-run=client" || "${1:-}" == "--dry-run=server" ]]; then
  DRY_RUN=("$1")
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/apply.sh [--dry-run|--dry-run=client|--dry-run=server] <path-to-kustomize-dir>" >&2
  exit 2
fi

TARGET_DIR=$1
if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "Directory not found: ${TARGET_DIR}" >&2
  exit 1
fi

if [[ ! -f "${TARGET_DIR}/kustomization.yml" && ! -f "${TARGET_DIR}/kustomization.yaml" && ! -f "${TARGET_DIR}/Kustomization" ]]; then
  echo "Refusing to apply ${TARGET_DIR}: no kustomization file found." >&2
  exit 1
fi

section "Break-glass apply"
log "Rendering ${TARGET_DIR} with kustomize and applying with kubectl"
log "Reminder: reconcile Git promptly so ArgoCD selfHeal will not revert this manual change."

kustomize build "${TARGET_DIR}" | kubectl apply "${DRY_RUN[@]}" -f -

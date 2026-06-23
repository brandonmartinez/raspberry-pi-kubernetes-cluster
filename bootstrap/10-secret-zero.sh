#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

NAMESPACE=${EXTERNAL_SECRETS_NAMESPACE:-external-secrets}
SECRET_NAME=${ONEPASSWORD_TOKEN_SECRET_NAME:-onepassword-token}
SECRET_KEY=${ONEPASSWORD_TOKEN_SECRET_KEY:-token}
OP_SECRET_REF=${OP_SERVICE_ACCOUNT_TOKEN_REF:-}
TOKEN=${OP_SERVICE_ACCOUNT_TOKEN:-}

section "Seeding 1Password secret zero"

if [[ -z "${TOKEN}" && -n "${OP_SECRET_REF}" ]]; then
  if ! command -v op >/dev/null 2>&1; then
    echo "OP_SERVICE_ACCOUNT_TOKEN is unset and op CLI is not installed; cannot read OP_SERVICE_ACCOUNT_TOKEN_REF." >&2
    exit 1
  fi
  log "Reading token with op CLI from OP_SERVICE_ACCOUNT_TOKEN_REF (token value will not be printed)"
  TOKEN=$(op read "${OP_SECRET_REF}")
fi

if [[ -z "${TOKEN}" ]]; then
  echo "OP_SERVICE_ACCOUNT_TOKEN is required. Alternatively set OP_SERVICE_ACCOUNT_TOKEN_REF to an op:// vault/item/field path and install/sign in to op CLI." >&2
  exit 1
fi

log "Creating namespace ${NAMESPACE} if needed"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log "Upserting Secret ${NAMESPACE}/${SECRET_NAME} (token value hidden)"
kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --from-literal="${SECRET_KEY}=${TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Secret ${NAMESPACE}/${SECRET_NAME} is present."

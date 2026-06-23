#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

NAMESPACE=${EXTERNAL_SECRETS_NAMESPACE:-external-secrets}
RELEASE=${ESO_RELEASE:-external-secrets}
CHART_REPO_NAME=${ESO_CHART_REPO_NAME:-external-secrets}
CHART_REPO_URL=${ESO_CHART_REPO_URL:-https://charts.external-secrets.io}
CHART=${ESO_CHART:-external-secrets/external-secrets}
# Verify this chart version supports provider.onepasswordSDK before upgrades.
ESO_CHART_VERSION=${ESO_CHART_VERSION:-0.18.2}
VALUES_FILE="${REPO_ROOT}/platform/external-secrets/helm-values.yaml"
STORE_FILE="${REPO_ROOT}/platform/external-secrets/clustersecretstore.yml"
TIMEOUT_SECONDS=${ESO_STORE_READY_TIMEOUT_SECONDS:-120}

section "Installing External Secrets Operator"
log "Creating namespace ${NAMESPACE} if needed"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log "Adding Helm repo ${CHART_REPO_NAME}"
helm repo add "${CHART_REPO_NAME}" "${CHART_REPO_URL}" >/dev/null
helm repo update "${CHART_REPO_NAME}" >/dev/null

log "Installing/upgrading ${RELEASE} chart ${CHART} ${ESO_CHART_VERSION}"
helm upgrade --install "${RELEASE}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${ESO_CHART_VERSION}" \
  -f "${VALUES_FILE}"

section "Applying ClusterSecretStore"
kubectl apply -f "${STORE_FILE}"

section "Waiting for ClusterSecretStore readiness"
deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  status=$(kubectl get clustersecretstore onepassword -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  reason=$(kubectl get clustersecretstore onepassword -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)
  if [[ "${status}" == "True" ]]; then
    log "ClusterSecretStore onepassword is Ready."
    exit 0
  fi
  log "Waiting for ClusterSecretStore onepassword Ready status (current: ${status:-unknown} ${reason:-})"
  sleep 5
done

echo "Timed out waiting for ClusterSecretStore onepassword to become Ready." >&2
kubectl describe clustersecretstore onepassword >&2 || true
exit 1

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

# Verify this version against https://github.com/argoproj/argo-cd/releases before upgrades.
ARGOCD_VERSION=${ARGOCD_VERSION:-v3.1.7}
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-argocd}
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

section "Installing ArgoCD"
log "Creating namespace ${ARGOCD_NAMESPACE} if needed"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log "Applying upstream ArgoCD install manifest pinned to ${ARGOCD_VERSION}"
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_INSTALL_URL}"

section "Exposing ArgoCD UI behind Traefik"
# Load the hostname suffix from the root .env (for the external URL). The ingress
# host itself is resolved by the cluster-config kustomize component, so this is
# only used to set argocd-cm's url. Re-applying the upstream manifest above resets
# these two ConfigMaps, so (re)apply our overrides every run.
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +o allexport
fi
HOSTNAME_SUFFIX="${NETWORK_HOSTNAME_SUFFIX:-}"

log "Running argocd-server with --insecure (Traefik terminates TLS)"
kubectl -n "${ARGOCD_NAMESPACE}" patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'

if [[ -n "${HOSTNAME_SUFFIX}" ]]; then
  log "Setting external URL to https://gitops.${HOSTNAME_SUFFIX}"
  kubectl -n "${ARGOCD_NAMESPACE}" patch configmap argocd-cm --type merge \
    -p "{\"data\":{\"url\":\"https://gitops.${HOSTNAME_SUFFIX}\"}}"
fi

log "Applying ArgoCD ingress (gitops.<suffix>, own login + redirect-https only)"
kubectl apply -k "${REPO_ROOT}/platform/argocd"

log "Restarting argocd-server to pick up --insecure"
kubectl -n "${ARGOCD_NAMESPACE}" rollout restart deployment/argocd-server

section "Next steps"
log "UI: https://gitops.${HOSTNAME_SUFFIX:-<hostname-suffix>} (user: admin)"
log "Initial admin password: kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
log "Fallback port-forward UI/API: kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
log "ArgoCD is intentionally installed imperatively and is not self-managed yet."

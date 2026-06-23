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

section "Next steps"
log "Initial admin password: kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
log "Port-forward UI/API: kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
log "ArgoCD is intentionally installed imperatively and is not self-managed yet."

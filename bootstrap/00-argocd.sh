#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

# ArgoCD is installed/adopted via the argo/argo-cd Helm chart so its own config
# lives in platform/argocd/helm-values.yaml like every other platform stack.
#
# Two version knobs, kept in lockstep:
#   ARGOCD_CHART_VERSION  the argo/argo-cd Helm chart version
#   ARGOCD_VERSION        the ArgoCD appVersion that chart ships (drives the CRDs)
# Verify both against https://github.com/argoproj/argo-helm/releases before bumps.
ARGOCD_CHART_VERSION=${ARGOCD_CHART_VERSION:-8.5.7}
ARGOCD_VERSION=${ARGOCD_VERSION:-v3.1.7}
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-argocd}
ARGOCD_CRDS_URL="https://github.com/argoproj/argo-cd/manifests/crds?ref=${ARGOCD_VERSION}"

section "Installing / adopting ArgoCD via Helm"
log "Creating namespace ${ARGOCD_NAMESPACE} if needed"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# CRDs are deliberately NOT managed by Helm (helm-values sets crds.install:false)
# so a chart removal can never cascade-delete the Application/AppProject CRs that
# hold the whole cluster's GitOps state. Install them out-of-band, pinned to the
# appVersion. Server-side apply avoids the "annotations too long" limit on the
# large ArgoCD CRDs. Idempotent: safe to re-run.
log "Applying ArgoCD CRDs (${ARGOCD_VERSION}, server-side, not Helm-managed)"
kubectl apply --server-side --force-conflicts -k "${ARGOCD_CRDS_URL}"

log "Adding/updating the argo-helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

# --take-ownership + --force-conflicts let a first run ADOPT a pre-existing
# raw-manifest install (overriding the kubectl-client-side-apply field manager);
# on a release that is already Helm-managed they are harmless no-ops. Selectors
# on the component Deployments/StatefulSet are immutable: if adopting a raw
# install whose selectors lack app.kubernetes.io/instance, delete those five
# workloads first (pods are stateless; Application CRs are untouched) — see
# platform/argocd/README.md.
log "helm upgrade --install argocd (chart ${ARGOCD_CHART_VERSION}, appVersion ${ARGOCD_VERSION})"
helm upgrade --install argocd argo/argo-cd \
  --version "${ARGOCD_CHART_VERSION}" \
  --namespace "${ARGOCD_NAMESPACE}" \
  -f "${REPO_ROOT}/platform/argocd/helm-values.yaml" \
  --take-ownership --force-conflicts --server-side=true --timeout 5m

section "Exposing ArgoCD UI behind Traefik"
# server.insecure (Traefik terminates TLS) and the external url are set in
# helm-values.yaml (configs.params / configs.cm), so no ConfigMap patching here.
# The ingress is not part of the chart; (re)apply it every run.
log "Applying ArgoCD ingress (gitops.<suffix>, own login + redirect-https only)"
kubectl apply -k "${REPO_ROOT}/platform/argocd"

HOSTNAME_SUFFIX=""
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +o allexport
  HOSTNAME_SUFFIX="${NETWORK_HOSTNAME_SUFFIX:-}"
fi

section "Next steps"
log "UI: https://gitops.${HOSTNAME_SUFFIX:-<hostname-suffix>} (user: admin)"
log "Initial admin password (fresh install): kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
log "Fallback port-forward UI/API: kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
log "ArgoCD is Helm-managed (release 'argocd'); upgrades are a helm-values.yaml change applied with this script."

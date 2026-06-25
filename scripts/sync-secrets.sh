#!/usr/bin/env bash
set -euo pipefail

# Push-sync secrets from 1Password into the cluster as Kubernetes Secrets.
#
# This is the homelab-friendly replacement for External Secrets Operator: instead
# of the cluster pulling from 1Password (which needs a Business service account),
# the operator PUSHES secrets from their signed-in `op` session. Nothing in the
# cluster depends on 1Password at runtime, so a 1Password/DNS/internet outage has
# ZERO effect on running workloads — secrets live in etcd until you re-push.
#
# Mechanism: every file in secrets/templates/ is a Kubernetes Secret manifest
# whose values are 1Password references ({{ op://$OP_VAULT/item/field }}).
# `op inject` resolves them; `kubectl apply` upserts the Secret. The shared
# postgres-app Secret is fanned out to every namespace labeled
# postgres-client=true (secrets/postgres-app.tpl.yaml).
#
# Usage:
#   scripts/sync-secrets.sh                 # sync every secret
#   scripts/sync-secrets.sh shlink          # sync one (template basename)
#   scripts/sync-secrets.sh postgres-app    # sync only the shared postgres fan-out
#   scripts/sync-secrets.sh --dry-run       # render + validate, apply nothing
#
# Env:
#   OP_VAULT    1Password vault holding homelab items (default: homelab)
#   OP_ACCOUNT  1Password account shorthand/sign-in address (for multi-account)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

export OP_VAULT="${OP_VAULT:-homelab}"
TEMPLATE_DIR="${REPO_ROOT}/secrets/templates"
PG_TEMPLATE="${REPO_ROOT}/secrets/postgres-app.tpl.yaml"
PG_LABEL="postgres-client=true"

OP_ARGS=()
[[ -n "${OP_ACCOUNT:-}" ]] && OP_ARGS=(--account "${OP_ACCOUNT}")

DRY_RUN=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h | --help)
      sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg" >&2
      exit 2
      ;;
    *) TARGET="$arg" ;;
  esac
done

# --- preconditions -----------------------------------------------------------
command -v op >/dev/null 2>&1 || {
  echo "op (1Password CLI) is required. Install it and sign in." >&2
  exit 1
}
command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required." >&2
  exit 1
}

section "1Password push-sync (vault: ${OP_VAULT})"
if ! op "${OP_ARGS[@]}" account get >/dev/null 2>&1; then
  echo "No usable 1Password session. Run 'eval \$(op signin)' (or enable the" >&2
  echo "desktop app CLI integration), then retry. Set OP_ACCOUNT for multi-account." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == false ]]; then
  if ! kubectl version >/dev/null 2>&1; then
    echo "kubectl cannot reach a cluster. Check KUBECONFIG / context." >&2
    exit 1
  fi
  log "Target context: $(kubectl config current-context 2>/dev/null || echo unknown)"
fi

# --- select templates --------------------------------------------------------
TEMPLATES=()
SYNC_PG=true
if [[ -n "${TARGET}" ]]; then
  if [[ "${TARGET}" == "postgres-app" ]]; then
    TEMPLATES=()
  elif [[ -f "${TEMPLATE_DIR}/${TARGET}.yaml" ]]; then
    TEMPLATES=("${TEMPLATE_DIR}/${TARGET}.yaml")
    SYNC_PG=false
  else
    echo "Unknown target '${TARGET}'. Expected 'postgres-app' or one of:" >&2
    (cd "${TEMPLATE_DIR}" && ls -1 ./*.yaml | sed 's#\./##;s#\.yaml$##') >&2
    exit 2
  fi
else
  while IFS= read -r f; do TEMPLATES+=("$f"); done \
    < <(find "${TEMPLATE_DIR}" -maxdepth 1 -name '*.yaml' | sort)
fi

template_ns() { grep -m1 -E '^\s*namespace:' "$1" | awk '{print $2}'; }

ensure_namespace() {
  local ns=$1
  kubectl get namespace "$ns" >/dev/null 2>&1 && return 0
  log "Creating namespace ${ns} (ArgoCD will reconcile its labels later)"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

# --- validation pass (resolve everything before touching the cluster) --------
section "Validating 1Password references"
for tpl in "${TEMPLATES[@]}"; do
  rel=${tpl#"${REPO_ROOT}/"}
  log "Resolving ${rel}"
  if ! op "${OP_ARGS[@]}" inject -f -i "$tpl" >/dev/null 2>&1; then
    echo "FAIL: could not resolve 1Password references in ${rel}." >&2
    echo "      Check the item/field labels exist in vault '${OP_VAULT}'." >&2
    exit 1
  fi
done
if [[ "${SYNC_PG}" == true ]]; then
  log "Resolving $(basename "${PG_TEMPLATE}")"
  if ! op "${OP_ARGS[@]}" inject -f -i "${PG_TEMPLATE}" >/dev/null 2>&1; then
    echo "FAIL: could not resolve postgres/password in vault '${OP_VAULT}'." >&2
    exit 1
  fi
fi
pass_msg="All references resolved."
log "${pass_msg}"

if [[ "${DRY_RUN}" == true ]]; then
  section "Dry run complete — nothing applied"
  exit 0
fi

# --- apply pass --------------------------------------------------------------
section "Applying namespaced secrets"
for tpl in "${TEMPLATES[@]}"; do
  rel=${tpl#"${REPO_ROOT}/"}
  ns=$(template_ns "$tpl")
  [[ -n "$ns" ]] || {
    echo "FAIL: no namespace found in ${rel}." >&2
    exit 1
  }
  ensure_namespace "$ns"
  log "Applying ${rel} -> namespace ${ns}"
  op "${OP_ARGS[@]}" inject -f -i "$tpl" | kubectl apply -f -
done

# --- shared postgres-app fan-out --------------------------------------------
if [[ "${SYNC_PG}" == true || "${TARGET}" == "postgres-app" ]]; then
  section "Fanning out postgres-app (namespaces labeled ${PG_LABEL})"
  mapfile -t PG_NS < <(kubectl get namespaces -l "${PG_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  if [[ ${#PG_NS[@]} -eq 0 ]]; then
    warn_msg="No namespaces labeled ${PG_LABEL} yet; skipping postgres-app."
    log "${warn_msg}"
    log "Re-run after those app namespaces exist (e.g. shlink, keycloak)."
  else
    rendered=$(op "${OP_ARGS[@]}" inject -f -i "${PG_TEMPLATE}")
    for ns in "${PG_NS[@]}"; do
      log "Applying postgres-app -> namespace ${ns}"
      printf '%s\n' "${rendered}" | sed "s/__NAMESPACE__/${ns}/g" | kubectl apply -f -
    done
  fi
fi

section "Secret push-sync complete"

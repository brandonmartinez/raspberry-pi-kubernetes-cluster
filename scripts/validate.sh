#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
source "${REPO_ROOT}/_shared/echo.sh"

FAILURES=0
WARNINGS=0
KUSTOMIZE_DIRS=()

fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
pass() { log "PASS: $*"; }

need_command() {
  command -v "$1" >/dev/null 2>&1
}

find_kustomizations() {
  KUSTOMIZE_DIRS=()
  for root in platform apps clusters/rpi; do
    [[ -d "${REPO_ROOT}/${root}" ]] || continue
    while IFS= read -r file; do
      dir=$(dirname "$file")
      if [[ "${dir}" == "${REPO_ROOT}/clusters/rpi" || "${dir}" == "${REPO_ROOT}/platform"* || "${dir}" == "${REPO_ROOT}/apps"* ]]; then
        KUSTOMIZE_DIRS+=("${dir}")
      fi
    done < <(find "${REPO_ROOT}/${root}" -type f \( -name kustomization.yml -o -name kustomization.yaml -o -name Kustomization \) | sort)
  done
}

check_kustomize() {
  section "Kustomize builds"
  if ! need_command kustomize; then
    fail "kustomize is required for local CI validation."
    return
  fi

  find_kustomizations
  if [[ ${#KUSTOMIZE_DIRS[@]} -eq 0 ]]; then
    warn "No platform/apps/clusters/rpi kustomizations found."
    return
  fi

  for dir in "${KUSTOMIZE_DIRS[@]}"; do
    rel=${dir#"${REPO_ROOT}/"}
    if [[ -z $(find "${dir}" -mindepth 1 -maxdepth 1 ! -name 'kustomization.*' ! -name 'Kustomization' -print -quit) ]]; then
      warn "${rel} contains only a kustomization file; treating in-progress empty tree as warning."
      continue
    fi
    log "kustomize build ${rel}"
    if ! kustomize build "${dir}" >/dev/null; then
      fail "kustomize build failed for ${rel}"
    fi
  done
}

lint_yaml_file() {
  local file=$1
  if need_command ruby; then
    ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$file" >/dev/null
  elif python3 - <<'PY' >/dev/null 2>&1
import yaml
PY
  then
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$file" >/dev/null
  else
    warn "No YAML parser (ruby or PyYAML) available; skipped YAML parse for ${file#"${REPO_ROOT}/"}."
    return 0
  fi
}

helm_component() {
  case "$1" in
    cert-manager) echo "jetstack|https://charts.jetstack.io|jetstack/cert-manager|${CERT_MANAGER_CHART_VERSION:-}|cert-manager" ;;
    longhorn) echo "longhorn|https://charts.longhorn.io|longhorn/longhorn|${LONGHORN_CHART_VERSION:-1.10.0}|longhorn-system" ;;
    descheduler) echo "descheduler|https://kubernetes-sigs.github.io/descheduler|descheduler/descheduler|${DESCHEDULER_CHART_VERSION:-}|kube-system" ;;
    monitoring) echo "prometheus-community|https://prometheus-community.github.io/helm-charts|prometheus-community/kube-prometheus-stack|${PROMETHEUS_CHART_VERSION:-}|monitoring" ;;
    *) return 1 ;;
  esac
}

check_helm() {
  section "Helm values and templates"
  shopt -s nullglob
  local values_files=("${REPO_ROOT}"/platform/*/helm-values.yaml "${REPO_ROOT}"/platform/*/helm-values.yml)
  shopt -u nullglob
  [[ ${#values_files[@]} -gt 0 ]] || { warn "No platform Helm values files found."; return; }

  for values in "${values_files[@]}"; do
    rel=${values#"${REPO_ROOT}/"}
    component=$(basename "$(dirname "$values")")
    log "Linting YAML ${rel}"
    lint_yaml_file "$values" || fail "YAML parse failed for ${rel}"

    if ! need_command helm; then
      warn "helm not installed; skipped helm template for ${component}."
      continue
    fi
    if ! info=$(helm_component "$component"); then
      warn "No chart mapping for platform/${component}; skipped helm template."
      continue
    fi
    IFS='|' read -r repo_name repo_url chart version namespace <<<"$info"
    if ! helm repo add "$repo_name" "$repo_url" >/dev/null 2>&1; then
      warn "Could not add Helm repo ${repo_url}; skipped ${component} template (offline?)."
      continue
    fi
    helm repo update "$repo_name" >/dev/null 2>&1 || warn "Could not update Helm repo ${repo_name}; using cached index if available."
    version_args=()
    [[ -n "$version" && "$version" != 0.0.0-* ]] && version_args=(--version "$version")
    if ! helm template "$component" "$chart" --namespace "$namespace" -f "$values" "${version_args[@]}" >/dev/null; then
      warn "helm template skipped/failed for ${component}; chart may be unavailable offline or version may need freezing."
    fi
  done
}

check_kubeconform() {
  section "kubeconform"
  if ! need_command kubeconform; then
    warn "kubeconform not installed; skipped schema validation."
    return
  fi
  if ! need_command kustomize; then
    warn "kustomize missing; skipped kubeconform."
    return
  fi
  [[ ${#KUSTOMIZE_DIRS[@]} -gt 0 ]] || find_kustomizations
  for dir in "${KUSTOMIZE_DIRS[@]}"; do
    rel=${dir#"${REPO_ROOT}/"}
    [[ -n $(find "${dir}" -mindepth 1 -maxdepth 1 ! -name 'kustomization.*' ! -name 'Kustomization' -print -quit) ]] || continue
    log "kubeconform ${rel}"
    if ! kustomize build "${dir}" | kubeconform -strict -ignore-missing-schemas >/dev/null; then
      fail "kubeconform failed for ${rel}"
    fi
  done
}

check_secrets() {
  section "Secret scan"
  set +e
  secret_output=$(python3 - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
failures = []
warnings = []
exts = {'.yml', '.yaml', '.env', '.sample', '.sh', '.json', '.txt', '.md'}
key_re = re.compile(r'(?i)(password|passwd|token|secret|api[_-]?key|apikey|client[_-]?secret)')
assign_re = re.compile(r'''(?ix)
    (?P<key>[A-Z0-9_./-]*(?:password|passwd|token|secret|api[_-]?key|apikey|client[_-]?secret)[A-Z0-9_./-]*)
    \s*[:=]\s*
    (?P<value>.+?)\s*$
''')
allowed_value_bits = ('${', '$(', '$', '{{', 'op://', 'REPLACE', '#Your', 'your', '<', '>', 'changeme', 'changeit', 'example', 'placeholder', 'jsonpath')
allowed_line_bits = (
    'remoteRef:', 'secretKey:', 'serviceAccountSecretRef:', 'secretStoreRef',
    'secretName:', 'existingSecret:', 'envFromSecret:', 'bearerTokenFile:', 'passwordKey:',
    'secret:',
    'possible plaintext secret',
)
allowed_key_suffixes = (
    'namespace', 'secretname', 'existingsecret', 'envfromsecret',
    'bearertokenfile', 'passwordkey', 'userkey', 'password_hash', 'admin_password_hash',
)
warning_paths = {
    '.env.sample': ('UPTIME_PASSWORD',),
    'docker/scrypted.yml': ('TOKEN',),
}
for dirpath, dirnames, filenames in os.walk(root):
    rel_dir = os.path.relpath(dirpath, root)
    parts = set(rel_dir.split(os.sep))
    if parts & {'.git', '_backups', 'node_modules', '.terraform'}:
        dirnames[:] = []
        continue
    for name in filenames:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        if rel == 'scripts/validate.sh' or rel.startswith('docs/'):
            continue
        if name.startswith('compiled') or name == 'kubeconfig.yml':
            continue
        if not (name == '.env.sample' or os.path.splitext(name)[1] in exts):
            continue
        try:
            lines = open(path, encoding='utf-8', errors='ignore').read().splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if not stripped or stripped.startswith('#') or not key_re.search(stripped):
                continue
            if any(bit in stripped for bit in allowed_line_bits):
                continue
            m = assign_re.search(stripped)
            if not m:
                continue
            key = m.group('key').lower().replace('-', '_').replace('.', '_').replace('/', '_')
            if key.endswith(allowed_key_suffixes):
                continue
            value = m.group('value').strip().strip('"\'')
            raw_value = m.group('value').strip()
            if raw_value.startswith(('""', "''")):
                continue
            if not value or value.startswith('#') or len(value) < 8:
                continue
            if any(bit.lower() in value.lower() for bit in allowed_value_bits):
                continue
            if rel in warning_paths and any(bit.lower() in stripped.lower() for bit in warning_paths[rel]):
                warnings.append(f'{rel}:{i}: known legacy sample/token-like value: {stripped}')
            else:
                failures.append(f'{rel}:{i}: possible plaintext secret: {m.group("key")}')
for msg in warnings:
    print('WARN_SECRET ' + msg)
for msg in failures:
    print('FAIL_SECRET ' + msg)
sys.exit(1 if failures else 0)
PY
  )
  local rc=$?
  set -e
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == WARN_SECRET* ]]; then
      warn "${line#WARN_SECRET }"
    else
      echo "$line" >&2
    fi
  done <<<"$secret_output"
  if [[ $rc -ne 0 ]]; then
    fail "Secret scan found possible plaintext secrets."
  else
    pass "No disallowed plaintext secrets found."
  fi
}

check_prune_policy() {
  section "Prune/selfHeal guard"
  set +e
  python3 - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
violations = []
protected = re.compile(r'(?i)(crd|longhorn|pihole|data|postgres)')
for base in ('clusters', 'platform', 'apps'):
    scan_root = os.path.join(root, base)
    if not os.path.isdir(scan_root):
        continue
    for dirpath, _, filenames in os.walk(scan_root):
        for name in filenames:
            if not name.endswith(('.yml', '.yaml')):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            text = open(path, encoding='utf-8', errors='ignore').read()
            for doc in re.split(r'(?m)^---\s*$', text):
                if not re.search(r'(?m)^kind:\s*Application(Set)?\s*$', doc):
                    continue
                name_match = re.search(r'(?m)^metadata:\s*\n(?:\s+.*\n)*?\s+name:\s*["\']?([^"\'\n]+)', doc)
                app_name = name_match.group(1).strip() if name_match else rel
                if not (protected.search(app_name) or protected.search(rel) or protected.search(doc)):
                    continue
                for field in ('prune', 'selfHeal'):
                    if re.search(rf'(?m)^\s*{field}:\s*true\s*(?:#.*)?$', doc):
                        violations.append(f'{rel}: protected Application {app_name} enables {field}: true')
for v in violations:
    print(v)
sys.exit(1 if violations else 0)
PY
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail "Protected Application prune/selfHeal guard failed."
  else
    pass "Protected Applications do not enable prune/selfHeal."
  fi
}

check_kustomize
check_helm
check_kubeconform
check_secrets
check_prune_policy

section "Validation summary"
log "Warnings: ${WARNINGS}"
if [[ ${FAILURES} -gt 0 ]]; then
  echo "Validation failed with ${FAILURES} failure(s)." >&2
  exit 1
fi
log "Validation passed."

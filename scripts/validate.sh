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

# Route Python-script result lines (prefixed PASS:/FAIL:/WARN:) through the
# standard fail/warn/pass helpers so FAILURES and WARNINGS are updated.
emit_py_results() {
  local _line
  while IFS= read -r _line; do
    [[ -z "${_line}" ]] && continue
    case "${_line}" in
      PASS:*) pass "${_line#PASS: }" ;;
      FAIL:*) fail "${_line#FAIL: }" ;;
      WARN:*) warn "${_line#WARN: }" ;;
      *)      log  "${_line}" ;;
    esac
  done <<<"$1"
}

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
    metallb) echo "metallb|https://metallb.github.io/metallb|metallb/metallb|${METALLB_CHART_VERSION:-0.15.2}|metallb-system" ;;
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
    if ! helm template "$component" "$chart" --namespace "$namespace" -f "$values" ${version_args[@]+"${version_args[@]}"} >/dev/null; then
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
    'automountServiceAccountToken:',
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
    if parts & {'.git', '_backups', 'node_modules', '.terraform', '.copilot', '.squad'}:
        dirnames[:] = []
        continue
    for name in filenames:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        if rel == 'scripts/validate.sh' or rel.startswith('docs/') or rel.startswith('.github/skills/'):
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
            value = m.group('value').strip().strip(chr(34)).strip(chr(39))
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

check_appset_preserve_policy() {
  section "ApplicationSet deletion safety"
  set +e
  python3 - "$REPO_ROOT" <<'PY'
import os, sys

root = sys.argv[1]
path = os.path.join(root, 'clusters', 'rpi', 'apps-appset.yml')
rel = os.path.relpath(path, root)
with open(path, encoding='utf-8') as fh:
    text = fh.read()

try:
    import yaml
except ImportError:
    yaml = None

def scalar_true(value):
    return value.split('#', 1)[0].strip().strip(chr(34)).strip(chr(39)).lower() == 'true'

def stripped_docs(raw):
    import re
    return [doc for doc in re.split(r'(?m)^---\s*$', raw) if doc.strip()]

def fallback_doc_kind(doc):
    import re
    match = re.search(r'(?m)^kind:\s*["\']?([^"\'\n#]+)', doc)
    return match.group(1).strip() if match else None

def fallback_doc_name(doc):
    import re
    match = re.search(r'(?m)^metadata:\s*\n(?:\s+.*\n)*?\s+name:\s*["\']?([^"\'\n#]+)', doc)
    return match.group(1).strip() if match else '<unnamed>'

def fallback_spec_sync_policy_preserve(doc):
    stack = []
    for raw_line in doc.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith('#'):
            continue
        if ':' not in raw_line:
            continue
        indent = len(raw_line) - len(raw_line.lstrip(' '))
        key, value = raw_line.strip().split(':', 1)
        key = key.strip().strip(chr(34)).strip(chr(39))
        while stack and indent <= stack[-1][0]:
            stack.pop()
        stack.append((indent, key))
        path = [item[1] for item in stack]
        if path == ['spec', 'syncPolicy', 'preserveResourcesOnDeletion']:
            return scalar_true(value)
    return False

if yaml:
    docs = [doc for doc in yaml.safe_load_all(text) if isinstance(doc, dict)]
    appsets = [doc for doc in docs if doc.get('kind') == 'ApplicationSet']
    if not appsets:
        print(f'{rel}: expected an ApplicationSet document.', file=sys.stderr)
        sys.exit(1)

    appset = appsets[0]
    explicit_apps = [
        doc.get('metadata', {}).get('name', '<unnamed>')
        for doc in docs
        if doc.get('kind') == 'Application'
    ]

    def has_exclude_true(node):
        if isinstance(node, dict):
            if node.get('exclude') is True:
                return True
            return any(has_exclude_true(value) for value in node.values())
        if isinstance(node, list):
            return any(has_exclude_true(value) for value in node)
        return False

    has_generator_excludes = has_exclude_true(appset.get('spec', {}).get('generators', []))
    preserve = appset.get('spec', {}).get('syncPolicy', {}).get('preserveResourcesOnDeletion') is True
else:
    docs = stripped_docs(text)
    appset_docs = [doc for doc in docs if fallback_doc_kind(doc) == 'ApplicationSet']
    if not appset_docs:
        print(f'{rel}: expected an ApplicationSet document.', file=sys.stderr)
        sys.exit(1)
    appset_doc = appset_docs[0]
    explicit_apps = [
        fallback_doc_name(doc)
        for doc in docs
        if fallback_doc_kind(doc) == 'Application'
    ]
    has_generator_excludes = any(
        scalar_true(line.split(':', 1)[1])
        for line in appset_doc.splitlines()
        if line.strip().startswith('exclude:')
    )
    preserve = fallback_spec_sync_policy_preserve(appset_doc)

uses_ownership_transfer = bool(explicit_apps) or has_generator_excludes

# Excluding generator paths or defining explicit Applications transfers ownership
# away from the ApplicationSet. Without this flag, the controller can cascade
# delete generated Applications and their live resources (including PVCs).
if uses_ownership_transfer and not preserve:
    details = []
    if explicit_apps:
        details.append('explicit Application objects: ' + ', '.join(explicit_apps))
    if has_generator_excludes:
        details.append('generator exclude: true entries')
    print(
        f'{rel}: ownership-transfer pattern in use ({ "; ".join(details) }) '
        'but spec.syncPolicy.preserveResourcesOnDeletion is not true.',
        file=sys.stderr,
    )
    sys.exit(1)
PY
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail "ApplicationSet preserveResourcesOnDeletion guard failed."
  else
    pass "ApplicationSet ownership-transfer paths preserve live resources on deletion."
  fi
}

check_dns_policy() {
  section "DNS policy invariants"

  local conf="${REPO_ROOT}/apps/dnsdist/dnsdist.conf"
  if [[ ! -f "${conf}" ]]; then
    fail "apps/dnsdist/dnsdist.conf not found"
    return
  fi

  # --- 1. Static dnsdist.conf assertions (exact Lua-table parsing; no kustomize) ---
  local _out _rc
  set +e
  _out=$(python3 - "${conf}" <<'PY'
import re, sys

try:
    conf = open(sys.argv[1], encoding='utf-8').read()
except OSError as e:
    print(f'FAIL: cannot read dnsdist.conf: {e}')
    sys.exit(1)

results = []

# Parse every newServer({...}) block and its byte offset in the file.
server_entries = []
for m in re.finditer(r'newServer\(\{([^}]+)\}\)', conf, re.DOTALL):
    block, pos = m.group(1), m.start()

    def _str(key, b=block):
        mm = re.search(r'\b' + re.escape(key) + r'\s*=\s*"([^"]+)"', b)
        return mm.group(1) if mm else None

    def _val(key, b=block):
        # Captures bare Lua identifiers/booleans (not double-quoted strings).
        mm = re.search(r'\b' + re.escape(key) + r'\s*=\s*([^\s,\n"]+)', b)
        return mm.group(1) if mm else None

    server_entries.append({
        'pos': pos, 'address': _str('address'), 'pool': _str('pool'),
        'name': _str('name'), 'checkClass': _val('checkClass'),
        'mustResolve': _val('mustResolve'),
    })

pihole_servers = [s for s in server_entries if s.get('pool') == 'pihole']
backup_servers = [s for s in server_entries if s.get('pool') == 'backup']

# Exactly 3 distinct per-ordinal pihole backends.
results.append(
    'PASS: exactly 3 pihole pool newServer entries' if len(pihole_servers) == 3
    else f'FAIL: expected 3 pihole pool newServer entries, found {len(pihole_servers)}')

# 10.43.100.30 must not appear anywhere in the file.
results.append(
    'FAIL: 10.43.100.30 (shared ClusterIP) referenced in dnsdist.conf'
    if '10.43.100.30' in conf else
    'PASS: 10.43.100.30 not referenced in dnsdist.conf')

# Per-ordinal server assertions: exact address, name, and FTL health-check fields.
for i, (exp_addr, exp_name) in enumerate([
        ('10.43.100.31:53', 'pihole-0'),
        ('10.43.100.32:53', 'pihole-1'),
        ('10.43.100.33:53', 'pihole-2')]):
    matched = [s for s in pihole_servers
               if s.get('address') == exp_addr and s.get('name') == exp_name]
    if not matched:
        results.append(f'FAIL: pihole-{i} newServer address={exp_addr} name={exp_name} not found')
        continue
    s = matched[0]
    results.append(f'PASS: pihole-{i} newServer address={exp_addr} name={exp_name}')
    cc = s.get('checkClass') or '(missing)'
    mr = s.get('mustResolve') or '(missing)'
    results.append(
        f'PASS: pihole-{i} checkClass=DNSClass.CHAOS' if cc == 'DNSClass.CHAOS'
        else f'FAIL: pihole-{i} checkClass={cc}, expected DNSClass.CHAOS')
    results.append(
        f'PASS: pihole-{i} mustResolve=true' if mr == 'true'
        else f'FAIL: pihole-{i} mustResolve={mr}, expected true')

# Backup pool: >=2 servers, all after the last pihole newServer in file order
# (preserves the any-up-loop-then-fallback semantics).
results.append(
    f'PASS: {len(backup_servers)} backup pool newServer entries present'
    if len(backup_servers) >= 2 else
    f'FAIL: expected >=2 backup pool newServer entries, found {len(backup_servers)}')

if pihole_servers and backup_servers:
    last_pihole = max(s['pos'] for s in pihole_servers)
    first_backup = min(s['pos'] for s in backup_servers)
    results.append(
        'PASS: backup pool entries follow pihole pool entries (any-up loop before fallback)'
        if first_backup > last_pihole else
        'FAIL: backup pool entries must follow pihole pool in file (any-up loop before fallback)')

# Routing addAction: pihole pool inside the loop, backup as after-loop fallback.
pihole_act = conf.find('return DNSAction.Pool, "pihole"')
backup_act = conf.find('return DNSAction.Pool, "backup"')
results.append(
    'PASS: pihole pool routing action present' if pihole_act >= 0
    else 'FAIL: pihole pool routing action (return DNSAction.Pool, "pihole") missing')
results.append(
    'PASS: backup pool fallback action present' if backup_act >= 0
    else 'FAIL: backup pool fallback action (return DNSAction.Pool, "backup") missing')
if pihole_act >= 0 and backup_act >= 0:
    results.append(
        'PASS: backup fallback follows pihole routing in addAction (correct loop structure)'
        if backup_act > pihole_act else
        'FAIL: backup fallback must appear after pihole routing in addAction')

for r in results:
    print(r)
sys.exit(1 if any(r.startswith('FAIL:') for r in results) else 0)
PY
)
  _rc=$?
  set -e
  emit_py_results "${_out}"
  [[ ${_rc} -eq 0 ]] || grep -q '^FAIL:' <<<"${_out}" || fail "dnsdist.conf static check: unexpected non-zero exit"

  # --- 2. Rendered pihole Service assertions (object-correlated by document) ---
  if ! need_command kustomize; then
    warn "kustomize missing; skipped rendered DNS service selector checks."
    return
  fi

  set +e
  _out=$(python3 - "${REPO_ROOT}" <<'PY'
import re, subprocess, sys

repo_root = sys.argv[1]
results = []

try:
    proc = subprocess.run(
        ['kustomize', 'build', f'{repo_root}/apps/pihole'],
        capture_output=True, text=True, timeout=60)
except FileNotFoundError:
    print('FAIL: kustomize not found in PATH')
    sys.exit(1)
if proc.returncode != 0:
    print(f'FAIL: kustomize build apps/pihole: {proc.stderr[:200].strip()}')
    sys.exit(1)

docs = [d for d in re.split(r'(?m)^---[ \t]*$', proc.stdout) if d.strip()]

def parse_dns_service(doc):
    """Extract DNS-service invariants from a single YAML document."""
    kind_m = re.search(r'(?m)^kind:\s*(\S+)', doc)
    if not kind_m or kind_m.group(1) != 'Service':
        return None
    name_m = re.search(r'(?m)^  name:\s*(\S+)', doc)
    if not name_m:
        return None
    name = name_m.group(1).strip(chr(34)).strip(chr(39))
    if not (re.match(r'^pihole-[012]-dns-svc$', name) or name == 'pihole-dns-svc'):
        return None
    cip_m  = re.search(r'(?m)^\s+clusterIP:\s*(\S+)', doc)
    pod_m  = re.search(r'(?m)statefulset\.kubernetes\.io/pod-name["\x27]* *:\s*(\S+)', doc)
    # Check port 53 presence via the 'port:' key (not targetPort/containerPort).
    has_p53 = bool(re.search(r'(?m)^\s+port:\s*53\s*$', doc))
    return {
        'name':      name,
        'clusterIP': cip_m.group(1).strip(chr(34)).strip(chr(39)) if cip_m else None,
        'podName':   pod_m.group(1).strip(chr(34)).strip(chr(39)) if pod_m else None,
        'hasTCP53':  has_p53 and bool(re.search(r'(?m)protocol:\s*TCP', doc)),
        'hasUDP53':  has_p53 and bool(re.search(r'(?m)protocol:\s*UDP', doc)),
    }

services = {}
for doc in docs:
    svc = parse_dns_service(doc)
    if svc:
        services[svc['name']] = svc

# Shared backwards-compat service (10.43.100.30).
sh = services.get('pihole-dns-svc')
if sh and sh['clusterIP'] == '10.43.100.30':
    results.append('PASS: pihole-dns-svc renders with clusterIP 10.43.100.30 (backwards compat)')
elif sh:
    results.append(f"FAIL: pihole-dns-svc clusterIP={sh['clusterIP']}, expected 10.43.100.30")
else:
    results.append('FAIL: pihole-dns-svc not found in rendered output')

# Per-ordinal: correlate Service name → ClusterIP → selector.pod-name → TCP+UDP 53.
for ordinal in range(3):
    svc_name = f'pihole-{ordinal}-dns-svc'
    exp_ip   = f'10.43.100.{31 + ordinal}'
    exp_pod  = f'pihole-{ordinal}'
    svc = services.get(svc_name)
    if not svc:
        results.append(f'FAIL: {svc_name} not found in rendered output')
        continue
    results.append(
        f'PASS: {svc_name} clusterIP={exp_ip}' if svc['clusterIP'] == exp_ip
        else f"FAIL: {svc_name} clusterIP={svc['clusterIP']}, expected {exp_ip}")
    results.append(
        f'PASS: {svc_name} selector.pod-name={exp_pod}' if svc['podName'] == exp_pod
        else f"FAIL: {svc_name} selector.pod-name={svc['podName']}, expected {exp_pod}")
    results.append(
        f'PASS: {svc_name} port 53/TCP' if svc['hasTCP53']
        else f'FAIL: {svc_name} missing port 53/TCP')
    results.append(
        f'PASS: {svc_name} port 53/UDP' if svc['hasUDP53']
        else f'FAIL: {svc_name} missing port 53/UDP')

for r in results:
    print(r)
sys.exit(1 if any(r.startswith('FAIL:') for r in results) else 0)
PY
)
  _rc=$?
  set -e
  emit_py_results "${_out}"
  [[ ${_rc} -eq 0 ]] || grep -q '^FAIL:' <<<"${_out}" || fail "pihole service render check: unexpected non-zero exit"

  # --- 3. Rendered dnsdist Deployment probe assertions ---
  set +e
  _out=$(python3 - "${REPO_ROOT}" <<'PY'
import re, subprocess, sys

repo_root = sys.argv[1]
results = []

try:
    proc = subprocess.run(
        ['kustomize', 'build', f'{repo_root}/apps/dnsdist'],
        capture_output=True, text=True, timeout=60)
except FileNotFoundError:
    print('FAIL: kustomize not found in PATH')
    sys.exit(1)
if proc.returncode != 0:
    print(f'FAIL: kustomize build apps/dnsdist: {proc.stderr[:200].strip()}')
    sys.exit(1)

docs = [d for d in re.split(r'(?m)^---[ \t]*$', proc.stdout) if d.strip()]

depl_doc = cfgmap_doc = None
for doc in docs:
    kind_m = re.search(r'(?m)^kind:\s*(\S+)', doc)
    name_m = re.search(r'(?m)^  name:\s*(\S+)', doc)
    if not (kind_m and name_m):
        continue
    k = kind_m.group(1)
    n = name_m.group(1).strip(chr(34)).strip(chr(39))
    if k == 'Deployment' and n == 'dnsdist':
        depl_doc = doc
    elif k == 'ConfigMap' and n.startswith('dnsdist-config'):
        cfgmap_doc = doc

if not depl_doc:
    results.append('FAIL: dnsdist Deployment not found in kustomize output')
else:
    # readinessProbe: use a local UDP DNS exchange, but do not couple readiness
    # to an upstream-success RCODE that could withdraw the VIP during WAN loss.
    has_py3      = bool(re.search(r'python3', depl_doc))
    has_dgram    = bool(re.search(r'SOCK_DGRAM', depl_doc))
    has_version  = bool(re.search(r'version', depl_doc, re.IGNORECASE))
    checks_reply = bool(re.search(r'0x8000', depl_doc))
    checks_rcode = bool(re.search(r'\brcode\b', depl_doc, re.IGNORECASE))
    results.append(
        'PASS: readinessProbe uses python3 UDP SOCK_DGRAM DNS check'
        if has_py3 and has_dgram else
        'FAIL: readinessProbe must use python3 with SOCK_DGRAM (proven UDP DNS-response check)')
    results.append(
        'PASS: readinessProbe validates a version.bind DNS response without requiring upstream success'
        if has_version and checks_reply and not checks_rcode else
        'FAIL: readinessProbe must validate a version.bind DNS response without checking RCODE')
    # startupProbe + livenessProbe: /dev/tcp TCP listener check (offline-safe).
    n_tcp = len(re.findall(r'/dev/tcp/127\.0\.0\.1/53', depl_doc))
    results.append(
        'PASS: startupProbe and livenessProbe use /dev/tcp/127.0.0.1/53'
        if n_tcp >= 2 else
        f'FAIL: expected >=2 /dev/tcp/127.0.0.1/53 probes (startup+liveness), found {n_tcp}')

# ConfigMap must not contain 10.43.100.30 (must not reference the shared ClusterIP).
if cfgmap_doc is not None:
    results.append(
        'PASS: 10.43.100.30 not in rendered dnsdist ConfigMap'
        if '10.43.100.30' not in cfgmap_doc else
        'FAIL: 10.43.100.30 found in rendered dnsdist ConfigMap (must not be a backend)')
else:
    results.append('WARN: dnsdist-config ConfigMap not found in kustomize output')

for r in results:
    print(r)
sys.exit(1 if any(r.startswith('FAIL:') for r in results) else 0)
PY
)
  _rc=$?
  set -e
  emit_py_results "${_out}"
  [[ ${_rc} -eq 0 ]] || grep -q '^FAIL:' <<<"${_out}" || fail "dnsdist deployment render check: unexpected non-zero exit"
}

check_script_syntax() {
  section "Shell script syntax"
  local major="${BASH_VERSION%%.*}"
  local script
  while IFS= read -r script; do
    local rel
    rel="${script#"${REPO_ROOT}/"}"
    local _err
    _err=$(bash -n "${script}" 2>&1) && { pass "syntax ok: ${rel}"; continue; }
    # bash 3.x misreports heredocs inside $() as "unexpected EOF"; treat as a warning
    # rather than a hard failure so the count isn't polluted on macOS system bash.
    if [[ "${major}" -lt 4 && ( "${_err}" == *"unexpected EOF"* || "${_err}" == *"syntax error: unexpected end"* ) ]]; then
      warn "bash ${BASH_VERSION} heredoc-in-\$() false-positive on ${rel} (see Homebrew bash note below)"
    else
      fail "syntax error: ${rel}"
    fi
  done < <(find "${REPO_ROOT}/scripts" "${REPO_ROOT}/_shared" -name '*.sh' -type f | sort)
  if [[ "${major}" -lt 4 ]]; then
    warn "System bash is ${BASH_VERSION} (< 4.0) — Homebrew bash 5.x syntax validation is a coordinator blocker before merge."
  fi
}

check_kustomize
check_helm
check_kubeconform
check_secrets
check_prune_policy
check_appset_preserve_policy
check_dns_policy
check_script_syntax

section "Validation summary"
log "Warnings: ${WARNINGS}"
if [[ ${FAILURES} -gt 0 ]]; then
  echo "Validation failed with ${FAILURES} failure(s)." >&2
  exit 1
fi
log "Validation passed."

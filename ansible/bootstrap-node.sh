#!/usr/bin/env bash
#
# bootstrap-node.sh — node-local (ansible-pull style) bootstrap for a Pi.
#
# Run this ON a Raspberry Pi. It installs Ansible + git, clones/updates this
# repo on the node, figures out the node's own inventory name, and runs the
# Ansible playbook against the node over a LOCAL connection. The node's
# inventory group (k3s_servers vs k3s_agents) selects the master/worker role
# automatically — no per-node config edits required.
#
# Safe by default: with no mode flag it runs the read-mostly `adopt.yml` with
# --check --diff (no changes, no reboot). Disruptive convergence and fresh
# provisioning are explicit opt-ins.
#
# Quick start (on the node):
#   sudo ./bootstrap-node.sh                       # read-only adopt --check
#   sudo ./bootstrap-node.sh --list-hosts          # show which role would run
#   sudo ./bootstrap-node.sh --adopt               # apply gated convergence
#   sudo K3S_TOKEN=... ./bootstrap-node.sh --provision   # fresh node only
#
# Self-contained clone (only the script staged on the node):
#   sudo ./bootstrap-node.sh --repo https://github.com/<owner>/<repo>.git \
#       --branch main
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults (override via flags or environment).
# ----------------------------------------------------------------------------
DEFAULT_REPO="https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git"
REPO_URL="${RPI_BOOTSTRAP_REPO:-$DEFAULT_REPO}"
REPO_BRANCH="${RPI_BOOTSTRAP_BRANCH:-main}"
DEST_DIR="${RPI_BOOTSTRAP_DIR:-$HOME/.cache/rpi-cluster-bootstrap}"

MODE="check"            # check | adopt | provision
INV_HOST=""             # explicit inventory host override (--host)
DO_PULL=1               # update an existing checkout before running
DO_PURGE=0              # remove the cloned checkout when finished
LIST_ONLY=0             # --list-hosts: print play/host mapping and exit
FORCE=0                 # allow provision on a node that already runs k3s
NO_SUDO=0               # do not auto-elevate
declare -a EXTRA_VARS=() # passthrough -e key=value

K3S_TOKEN="${K3S_TOKEN:-}"
ADMIN_PASSWORD_HASH="${ADMIN_PASSWORD_HASH:-}"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap] WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[bootstrap] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --adopt                Apply gated convergence (adopt.yml -e allow_disruptive=true).
  --provision            Fresh-node provisioning (provision.yml). Refuses on a
                         node that already runs k3s unless --force is given.
  --check                Read-only adopt --check --diff (default).
  --list-hosts           Print which plays/role would run for this node and exit.
  --host NAME            Inventory host name to target (default: auto-detect).
  --repo URL             Git URL to clone (default: built-in / $RPI_BOOTSTRAP_REPO).
  --branch REF           Branch/tag/commit to check out (default: main).
  --dest DIR             Where to clone/update the repo (default: ~/.cache/...).
  --no-pull              Use the existing checkout as-is; do not git pull.
  --purge                Delete the checkout after the run.
  --k3s-token TOKEN      k3s join token (or env K3S_TOKEN). Needed for fresh agents.
  --admin-pass-hash HASH Hashed admin password (or env ADMIN_PASSWORD_HASH).
  -e, --extra KEY=VAL    Extra ansible var (repeatable).
  --no-sudo              Do not auto-elevate with sudo.
  -h, --help             Show this help.
EOF
}

# ----------------------------------------------------------------------------
# Parse arguments.
# ----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --adopt) MODE="adopt" ;;
    --provision) MODE="provision" ;;
    --check) MODE="check" ;;
    --list-hosts) LIST_ONLY=1 ;;
    --host) INV_HOST="${2:?--host needs a value}"; shift ;;
    --repo) REPO_URL="${2:?--repo needs a value}"; shift ;;
    --branch) REPO_BRANCH="${2:?--branch needs a value}"; shift ;;
    --dest) DEST_DIR="${2:?--dest needs a value}"; shift ;;
    --no-pull) DO_PULL=0 ;;
    --purge) DO_PURGE=1 ;;
    --force) FORCE=1 ;;
    --no-sudo) NO_SUDO=1 ;;
    --k3s-token) K3S_TOKEN="${2:?--k3s-token needs a value}"; shift ;;
    --admin-pass-hash) ADMIN_PASSWORD_HASH="${2:?--admin-pass-hash needs a value}"; shift ;;
    -e|--extra) EXTRA_VARS+=("${2:?-e needs KEY=VAL}"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# Elevate if needed (package install + provisioning require root).
# ----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ] && [ "$NO_SUDO" -eq 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    log "Re-executing with sudo to install packages / converge node state."
    exec sudo -E "$0" "$@"
  fi
  warn "Not running as root and sudo is unavailable; package install may fail."
fi

# ----------------------------------------------------------------------------
# Locate the repo: reuse an enclosing checkout if present, else clone.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENCLOSING_ROOT=""
if command -v git >/dev/null 2>&1; then
  ENCLOSING_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi

ensure_packages() {
  local missing=()
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v ansible-playbook >/dev/null 2>&1 || missing+=(ansible)
  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi
  log "Installing: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  else
    die "apt-get not found; install ${missing[*]} manually and re-run."
  fi
}

if [ -n "$ENCLOSING_ROOT" ] && [ -f "$ENCLOSING_ROOT/ansible/provision.yml" ]; then
  REPO_DIR="$ENCLOSING_ROOT"
  log "Using existing checkout: $REPO_DIR"
  ensure_packages
  if [ "$DO_PULL" -eq 1 ]; then
    log "Updating checkout ($REPO_BRANCH)…"
    git -C "$REPO_DIR" fetch --depth 1 origin "$REPO_BRANCH" \
      && git -C "$REPO_DIR" checkout "$REPO_BRANCH" \
      && git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH" \
      || warn "git update failed; continuing with the checkout as-is."
  fi
else
  ensure_packages
  if [ -d "$DEST_DIR/.git" ]; then
    log "Updating clone at $DEST_DIR ($REPO_BRANCH)…"
    git -C "$DEST_DIR" remote set-url origin "$REPO_URL"
    git -C "$DEST_DIR" fetch --depth 1 origin "$REPO_BRANCH"
    git -C "$DEST_DIR" checkout "$REPO_BRANCH"
    git -C "$DEST_DIR" reset --hard "origin/$REPO_BRANCH"
  else
    log "Cloning $REPO_URL ($REPO_BRANCH) → $DEST_DIR"
    mkdir -p "$(dirname "$DEST_DIR")"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$DEST_DIR"
  fi
  REPO_DIR="$DEST_DIR"
fi

ANSIBLE_DIR="$REPO_DIR/ansible"
[ -d "$ANSIBLE_DIR" ] || die "ansible/ not found under $REPO_DIR"
cd "$ANSIBLE_DIR"

# ----------------------------------------------------------------------------
# Ensure required collections (idempotent; tolerate offline in check mode).
# ----------------------------------------------------------------------------
if [ -f requirements.yml ]; then
  log "Installing Ansible collections from requirements.yml…"
  if ! ansible-galaxy collection install -r requirements.yml >/dev/null 2>&1; then
    if [ "$MODE" = "check" ]; then
      warn "Collection install failed (offline?); continuing for read-only check."
    else
      die "Collection install failed; resolve connectivity and re-run."
    fi
  fi
fi

# ----------------------------------------------------------------------------
# Resolve this node's inventory name. The matching group decides the role.
# ----------------------------------------------------------------------------
host_in_inventory() {
  ansible-inventory -i inventory/hosts.yml --host "$1" >/dev/null 2>&1
}

if [ -z "$INV_HOST" ]; then
  suffix="$(awk -F': *' '/^network_hostname_suffix:/ {print $2}' \
    inventory/group_vars/all.yml 2>/dev/null | awk '{print $1}')"
  short="$(hostname -s 2>/dev/null || hostname)"
  fqdn="$(hostname -f 2>/dev/null || true)"
  for cand in "$fqdn" "${short}.${suffix}" "$short"; do
    [ -n "$cand" ] || continue
    if host_in_inventory "$cand"; then INV_HOST="$cand"; break; fi
  done
fi

[ -n "$INV_HOST" ] || die "Could not match this node to an inventory host.
Add it to ansible/inventory/hosts.yml (under k3s_servers or k3s_agents) or pass
--host NAME. Detected names: short='$(hostname -s 2>/dev/null)' fqdn='$(hostname -f 2>/dev/null)'."

host_in_inventory "$INV_HOST" || die "Host '$INV_HOST' is not in the inventory."

# Role label for messaging only — the play's hosts: pattern does the real work.
ROLE="agent"
if ansible -i inventory/hosts.yml k3s_servers --list-hosts 2>/dev/null \
    | grep -qw "$INV_HOST"; then
  ROLE="server"
fi
log "Node '$INV_HOST' resolved as k3s ${ROLE}."

# ----------------------------------------------------------------------------
# Build and run the ansible-playbook command.
# ----------------------------------------------------------------------------
declare -a PLAY_ARGS=(-i inventory/hosts.yml -l "$INV_HOST" --connection=local)
[ "${#EXTRA_VARS[@]}" -gt 0 ] && for v in "${EXTRA_VARS[@]}"; do PLAY_ARGS+=(-e "$v"); done
[ -n "$K3S_TOKEN" ] && PLAY_ARGS+=(-e "k3s_token=$K3S_TOKEN")
[ -n "$ADMIN_PASSWORD_HASH" ] && PLAY_ARGS+=(-e "admin_password_hash=$ADMIN_PASSWORD_HASH")

case "$MODE" in
  check)
    PLAYBOOK="adopt.yml"
    PLAY_ARGS+=(--check --diff)
    log "Mode: read-only adopt (--check --diff). No changes will be made."
    ;;
  adopt)
    PLAYBOOK="adopt.yml"
    PLAY_ARGS+=(-e "allow_disruptive=true")
    warn "Mode: adopt with allow_disruptive=true. Convergence WILL change node state (no auto-reboot)."
    ;;
  provision)
    PLAYBOOK="provision.yml"
    if [ "$FORCE" -ne 1 ] && { [ -e /etc/systemd/system/k3s.service ] || [ -e /etc/systemd/system/k3s-agent.service ]; }; then
      die "Refusing to provision: this node already runs k3s. Use --adopt, or --force to override."
    fi
    if [ "$ROLE" = "agent" ] && [ -z "$K3S_TOKEN" ] && [ ! -e /etc/systemd/system/k3s-agent.service ]; then
      die "Fresh agent provisioning needs a join token. Pass --k3s-token or set K3S_TOKEN."
    fi
    warn "Mode: provision. Fresh-node convergence WILL change node state (no auto-reboot)."
    ;;
esac

if [ "$LIST_ONLY" -eq 1 ]; then
  log "Plays/role mapping for '$INV_HOST' ($PLAYBOOK):"
  ansible-playbook "$PLAYBOOK" "${PLAY_ARGS[@]}" --list-hosts
  exit 0
fi

log "Running: ansible-playbook $PLAYBOOK ${PLAY_ARGS[*]}"
set +e
ansible-playbook "$PLAYBOOK" "${PLAY_ARGS[@]}"
rc=$?
set -e

if [ "$DO_PURGE" -eq 1 ] && [ "$REPO_DIR" = "$DEST_DIR" ]; then
  log "Purging checkout at $DEST_DIR"
  rm -rf "$DEST_DIR"
fi

exit "$rc"

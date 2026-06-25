#!/usr/bin/env bash
set -euo pipefail

# Seed the 1Password "homelab" vault with the item/field structure that
# scripts/sync-secrets.sh expects. Every field is created CONCEALED with a
# placeholder value (REPLACE-ME); you then set the real values in the 1Password
# app or with `op item edit`. Re-running is safe: existing items are left
# untouched (never clobbered), only missing items/fields are added.
#
# This stores NO secrets in git — only field labels. The labels must match the
# Kubernetes Secret keys referenced by secrets/templates/*.yaml.
#
# Usage:
#   scripts/seed-1password.sh            # create vault + all items
#   OP_VAULT=homelab scripts/seed-1password.sh
#
# Env:
#   OP_VAULT    vault to create/use (default: homelab)
#   OP_ACCOUNT  1Password account shorthand/sign-in address (multi-account)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
# shellcheck disable=SC1091
source "${REPO_ROOT}/_shared/echo.sh"

VAULT="${OP_VAULT:-homelab}"
PLACEHOLDER="REPLACE-ME"

OP_ARGS=()
[[ -n "${OP_ACCOUNT:-}" ]] && OP_ARGS=(--account "${OP_ACCOUNT}")

command -v op >/dev/null 2>&1 || {
  echo "op (1Password CLI) is required. Install it and sign in." >&2
  exit 1
}

section "Seeding 1Password vault: ${VAULT}"
if ! op "${OP_ARGS[@]}" account get >/dev/null 2>&1; then
  echo "No usable 1Password session. Run 'eval \$(op signin)' (or approve the" >&2
  echo "desktop app integration prompt), then retry. Set OP_ACCOUNT if needed." >&2
  exit 1
fi

# --- vault -------------------------------------------------------------------
if op "${OP_ARGS[@]}" vault get "${VAULT}" >/dev/null 2>&1; then
  log "Vault '${VAULT}' already exists."
else
  log "Creating vault '${VAULT}'."
  op "${OP_ARGS[@]}" vault create "${VAULT}" >/dev/null
fi

# --- items -------------------------------------------------------------------
# Each entry: "<item-title>" followed by one or more field labels. Field labels
# MUST equal the Secret keys in secrets/templates/<item>.yaml.
create_item() {
  local title=$1
  shift
  if op "${OP_ARGS[@]}" item get "${title}" --vault "${VAULT}" >/dev/null 2>&1; then
    log "Item '${title}' exists — leaving its values untouched."
    return 0
  fi
  local assignments=()
  local field
  for field in "$@"; do
    assignments+=("${field}[password]=${PLACEHOLDER}")
  done
  log "Creating item '${title}' with fields: $*"
  op "${OP_ARGS[@]}" item create \
    --vault "${VAULT}" \
    --category "Secure Note" \
    --title "${title}" \
    "${assignments[@]}" >/dev/null
}

create_item shlink       SHLINK_SERVER_API_KEY GEOLITE_LICENSE_KEY
create_item keycloak     KEYCLOAK_ADMIN_PASSWORD
create_item meal-planner DATABASE_URL JWT_SECRET GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
create_item nebulasync   PRIMARY REPLICAS
create_item pihole       FTLCONF_webserver_api_password
create_item pikaraoke    PIKARAOKE_ADMIN_PASSWORD
create_item postgres     password
create_item grafana      admin-password
create_item traefik      basicauth
create_item uptime       UPTIME_USERNAME UPTIME_PASSWORD

section "Done. Set the real values next:"
cat <<EOF
  op item edit <item> '<FIELD>=<real-value>' --vault ${VAULT}

  e.g. op item edit postgres 'password=<live-db-password>' --vault ${VAULT}

Notes:
  - traefik/basicauth must be a full htpasswd line, e.g.:
      htpasswd -nbB admin '<password>'
  - meal-planner/DATABASE_URL is the full connection string (or switch the
    template to compose it from postgres/password — see docs/secrets.md).
  - Then run: scripts/sync-secrets.sh --dry-run  (verify every ref resolves)
              scripts/sync-secrets.sh            (push to the cluster)
EOF

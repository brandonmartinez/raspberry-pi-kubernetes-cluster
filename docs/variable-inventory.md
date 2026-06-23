# Variable Inventory

This document is the **source of truth** for every `${VAR}` the legacy
`deploy.sh`/`envsubst` pipeline substituted, where each value comes from today,
and where it is going under the GitOps + ESO model. It exists so the migration
never silently drops or mistypes a value.

> Legend for **Target mechanism**:
>
> - **cluster-config** — non‑secret, cluster‑specific value committed once in the
>   per‑cluster overlay (`clusters/rpi/cluster-config.env` + literals in
>   manifests). Changing clusters = edit one place.
> - **app `.env`** — non‑secret, app‑specific config already consumed by a
>   Kustomize `configMapGenerator` (works under plain `kustomize build`; no
>   change needed).
> - **ESO** — secret, sourced from 1Password via an `ExternalSecret` that
>   renders a fixed‑name `Secret`. Never committed in plaintext.
> - **Ansible** — host/cluster facts that belong in the Ansible inventory, not in
>   manifests.
> - **Argo Application** — value that parameterizes a Helm chart version/release.

---

## 1. Secrets → External Secrets Operator (1Password)

These must **never** be committed. Each maps to a 1Password item/field referenced
by an `ExternalSecret`. The rendered `Secret` keeps the **same name** the app
already mounts so workload references don't change.

| Variable | Used by (today) | Rendered Secret (name/key) | 1Password ref (suggested) |
| --- | --- | --- | --- |
| `POSTGRES_PASSWORD` | `data/.env.secret`, `shlink/.env.secret`, `keycloak/helm-values.yml` | `data-secret/POSTGRES_PASSWORD`, `shlink-secret/DB_PASSWORD` | `vault:homelab/postgres/password` |
| `SHLINK_API_KEY` | `shlink/.env.secret` → `SHLINK_SERVER_API_KEY` | `shlink-secret/SHLINK_SERVER_API_KEY` | `homelab/shlink/api-key` |
| `SHLINK_GEOIP_LICENSE_KEY` | `shlink/.env` (GeoIP) | `shlink-secret/...` (move out of `.env`) | `homelab/shlink/geoip-license` |
| `SECURITY_BASICAUTH` | `security/secrets.yml` (`basicauth-user`) | `basicauth-user/users` | `homelab/traefik/basicauth` |
| `WEBPASSWORD` | `pihole/.env.secret` | `pihole-secret/WEBPASSWORD` | `homelab/pihole/web-password` |
| `GRAFANA_PASSWORD` | `monitoring/helm-values.yml` (admin) | Grafana `existingSecret` | `homelab/grafana/admin-password` |
| `PIKARAOKE_ADMIN_PASSWORD` | `pikaraoke/.env` | `pikaraoke-secret/...` | `homelab/pikaraoke/admin-password` |
| `UPTIME_USERNAME` / `UPTIME_PASSWORD` | `monitoring/helm-values.yml` (scrape basic‑auth), `uptime` | ESO secret consumed by Prometheus `basicAuth` | `homelab/uptime/scrape-credentials` |
| `MEALPLANNER_JWT_SECRET` | `meal-planner/.env.secret` | `meal-planner-secret/...` | `homelab/meal-planner/jwt` |
| `MEALPLANNER_GOOGLE_CLIENT_ID` | `meal-planner/.env.secret` | `meal-planner-secret/...` | `homelab/meal-planner/google-client-id` |
| `MEALPLANNER_GOOGLE_CLIENT_SECRET` | `meal-planner/.env.secret` | `meal-planner-secret/...` | `homelab/meal-planner/google-client-secret` |
| `POSTGRES_USER` | `data`, `keycloak`, init SQL | see note below — **config, not secret** | n/a |

> **`POSTGRES_USER` is configuration, not a secret** (today `rpi`). Keep it in
> cluster-config/app `.env`. Only the password goes to ESO. But note the
> **runtime‑vs‑deploy‑time** caveat in §4.

### ⚠ Committed secrets to rotate during migration

- `.env.sample` line `UPTIME_PASSWORD=trumpet-hedgehog-iceberg1!` is a
  **real‑looking credential committed to git**. Rotate it and move to ESO; the
  sample should contain only a placeholder.
- `docker/scrypted.yml` hardcodes
  `SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION` / `WATCHTOWER_HTTP_API_TOKEN`
  (`balance-propane-epitaph-denier`). Local‑only token, but it is in git —
  rotate and parameterize.

---

## 2. Non‑secret cluster‑specific values → cluster-config

One value, one place. These are committed literals in the per‑cluster overlay.

| Variable | Used by (manifest fields) | Notes |
| --- | --- | --- |
| `NETWORK_HOSTNAME_SUFFIX` | ingress hosts in **changedetection, longhorn, meal-planner, monitoring, pihole, pikaraoke, portainer, shlink, uptime, localproxy(×4)**; `localproxy/config.yml`; `monitoring/helm-values.yml` | The dominant cross‑cutting value. Kustomize cannot interpolate a substring, so each ingress commits a **full literal host** (`<svc>.<suffix>`). Centralize the suffix decision here; CI checks all hosts share the suffix. |
| `CLUSTER_HOSTNETWORKINGIPADDRESS` | LoadBalancer services: **pihole, minecraft, chrony, data(postgres)** | ⚠ Verify each is set on `spec.loadBalancerIP` (OK to commit) and **not** committed under `status:` (desired status must never be committed — see §4). |
| `ADMIN_EMAIL` | `security/clusterissuer-letsencrypt.yml` | Let's Encrypt ACME contact. |
| `SHLINK_DEFAULT_DOMAIN` | `shlink/ingress.yml`, `shlink/.env` | Public domain (e.g. bmtn.us). Config, not secret. |
| `TZ` | many deployment env vars | Could stay per‑app `.env`; recommended to centralize. |
| `PGID` / `PUID` | container env (linuxserver‑style images) | Centralize; rarely changes. |
| `WMI_IP_ADDRESS` | `monitoring` (windows‑exporter scrape) | Static scrape target. |
| `UPTIME_NODE` | `uptime/deployment.yml` (`nodeSelector`/host pin) | Node hostname; could also be Ansible‑managed label. |
| `UPTIME_BACKUP_SCHEDULE` / `UPTIME_BACKUP_RETENTION_DAYS` | `uptime/backup-cronjob.yml` | Plain config. |
| `LAN_REV_SERVERS` | `pihole/.env` | Quirky `;`/`#` syntax — validate rendered output matches live exactly. |

---

## 3. Longhorn / storage values → Argo Application + literals

| Variable | Used by | Target |
| --- | --- | --- |
| `LONGHORN_CHART_VERSION` (`1.10.0`) | `deploy.sh` Helm install | **Freeze** to the *currently deployed* version in `platform/longhorn` Application. Confirm with `helm list -n longhorn-system` before committing. |
| `LONGHORN_REPLICACOUNT` (`3`) | `longhorn/helm-values.yml` | Committed literal in `platform/longhorn` values. **Do not change during adoption.** |
| `LONGHORN_BACKUPTARGET` | `longhorn/helm-values.yml` | Committed literal. ⚠ Sample value points at a `longhorn-test-nfs-svc` — confirm the **real** backup target before adoption; a wrong target risks backup loss. |
| `MOUNT_USB_MOUNT_PATH` | `longhorn/helm-values.yml` (`defaultDataPath`), local‑path config | ⚠ **Never change** during adoption — changing `defaultDataPath` orphans existing volumes. Ansible owns the mount; manifest commits the literal. |

---

## 4. Correctness caveats (do not migrate casually)

- **Runtime vs deploy‑time `$VAR`.** In `data/postgres-init.yml` and
  `data/postgres-statefulset.yml`, `$POSTGRES_USER` / `$POSTGRES_DB` appear
  **inside container commands / SQL**. The legacy pipeline ran `envsubst` over
  everything, so these were substituted at *deploy* time. Under GitOps with no
  envsubst, decide per‑occurrence whether each should be (a) a literal, or (b) a
  genuine **runtime** shell expansion of a container env var (leave `$VAR`, ensure
  the env var is set from the ConfigMap/Secret). Getting this wrong breaks DB
  init. Verify rendered output against the live `compiled-data.yml`.
- **Desired `status` must not be committed.** Any service committing
  `status.loadBalancer.ingress[].ip` via `${CLUSTER_HOSTNETWORKINGIPADDRESS}`
  must drop the `status:` block; only `spec.loadBalancerIP` (or the k3s
  ServiceLB annotation) belongs in git.
- **`${DOLLAR}` disappears.** It exists only because `envsubst` ran over Grafana
  dashboards and Prometheus rules. Once envsubst is gone, commit dashboards/rules
  with literal `$`. CI must fail if `${DOLLAR}` reappears.
- **Secret rename trap.** Today `secretGenerator` produces **hash‑suffixed**
  Secret names (e.g. `shlink-secret-abc123`). ESO renders a **fixed** name. The
  cutover order is: render the ESO Secret first → confirm it exists → then point
  the workload at the fixed name (separate sync). See `docs/secrets.md`.

---

## 5. Values that move out of manifests entirely

| Variable | New home |
| --- | --- |
| `CLUSTER_HOSTNAME`, `CLUSTER_NODES`, `CLUSTER_NODES_HOSTNAMES` | Ansible inventory (`ansible/inventory/hosts.yml`) |
| `MOUNT_USB`, `MOUNT_USB_DRIVE_PATH`, `MOUNT_USB_DRIVE_FORMAT`, `MOUNT_USB_MOUNT_PATH` | Ansible `group_vars` (storage role) |
| `DEPLOY_*` toggles | Replaced by ArgoCD App enable/disable (presence of the Application) |

Every row above must be accounted for before the legacy `.env` is retired.

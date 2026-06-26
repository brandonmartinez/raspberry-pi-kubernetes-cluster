# Variable Inventory

This document is the **source of truth** for every `${VAR}` the legacy
`deploy.sh`/`envsubst` pipeline substituted, where each value comes from today,
and where it is going under the GitOps + push-sync secrets model. It exists so
the migration never silently drops or mistypes a value.

> Legend for **Target mechanism**:
>
> - **cluster-config** — non‑secret, cluster‑specific value defined once in the
>   `components/cluster-config` Kustomize component. Apps opt in via
>   `components:` + an annotation (`cluster-config/suffix-host`,
>   `cluster-config/lan-lb-ip`); the component replaces the value at build time.
>   Changing clusters = edit one file.
> - **app `.env`** — non‑secret, app‑specific config already consumed by a
>   Kustomize `configMapGenerator` (works under plain `kustomize build`; no
>   change needed).
> - **push-sync (template)** — secret, sourced from **one 1Password item per app**
>   via a committed Secret template in `secrets/templates/` whose values are
>   `op://` references. `scripts/sync-secrets.sh` resolves them with `op inject`
>   and `kubectl apply`s the Secret. Never committed in plaintext.
> - **push-sync (postgres fan-out)** — the shared postgres password, fanned by
>   `scripts/sync-secrets.sh` into every namespace labeled `postgres-client=true`
>   (`secrets/postgres-app.tpl.yaml`). Defined once.
> - **Ansible** — host/cluster facts that belong in the Ansible inventory, not in
>   manifests.
> - **Argo Application** — value that parameterizes a Helm chart version/release.

---

## 1. Secrets → push-sync from 1Password

These must **never** be committed. Each app maps to **one 1Password item** whose
field labels equal the Secret keys the app mounts; a committed template in
`secrets/templates/<app>.yaml` references those fields with `op://`, and
`scripts/sync-secrets.sh` pushes the rendered Secret (keeping the name the app
already references so workload references don't change). The shared PostgreSQL
password is the exception — it is fanned out by the same script into every
`postgres-client=true` namespace.

| Variable | Used by (today) | Rendered Secret (name/key) | Mechanism / 1Password ref |
| --- | --- | --- | --- |
| `POSTGRES_PASSWORD` | `data`, `shlink`, `keycloak`, monitoring (Grafana DB) | `postgres-app/password` (shared) | **postgres fan-out** → namespaces labeled `postgres-client=true`. Server (`data`) + templating consumers (monitoring, meal-planner) reference item `homelab/postgres` in their own templates. |
| `SHLINK_API_KEY` | `shlink/.env.secret` → `SHLINK_SERVER_API_KEY` | `shlink-secret/SHLINK_SERVER_API_KEY` | item `homelab/shlink` |
| `SHLINK_GEOIP_LICENSE_KEY` | `shlink/.env` (GeoIP) | `shlink-secret/...` (move out of `.env`) | item `homelab/shlink` |
| `SECURITY_BASICAUTH` | `security/secrets.yml` (`basicauth-user`) | `basicauth-user/users` | item `homelab/traefik` (stays in `security` ns only) |
| `WEBPASSWORD` | `pihole/.env.secret` | `pihole-secret/FTLCONF_webserver_api_password` | item `homelab/pihole` |
| `GRAFANA_PASSWORD` | `monitoring/helm-values.yml` (admin) | `monitoring-secret/admin-password` | item `homelab/grafana` |
| `PIKARAOKE_ADMIN_PASSWORD` | `pikaraoke/.env` | `pikaraoke-secret/...` | item `homelab/pikaraoke` |
| `UPTIME_USERNAME` / `UPTIME_PASSWORD` | `monitoring` (scrape basic‑auth) + `uptime` | `uptime-secret` + embedded in `monitoring-additional-scrape-configs` | item `homelab/uptime` (one item, two consumers) |
| `MEALPLANNER_JWT_SECRET` | `meal-planner/.env.secret` | `meal-planner-secret/...` | item `homelab/meal-planner` |
| `MEALPLANNER_GOOGLE_CLIENT_ID` | `meal-planner/.env.secret` | `meal-planner-secret/...` | item `homelab/meal-planner` |
| `MEALPLANNER_GOOGLE_CLIENT_SECRET` | `meal-planner/.env.secret` | `meal-planner-secret/...` | item `homelab/meal-planner` |
| `POSTGRES_USER` | `data`, `keycloak`, init SQL | see note below — **config, not secret** | n/a |

> **`POSTGRES_USER` is configuration, not a secret** (today `rpi`). Keep it in
> cluster-config/app `.env`. Only the password is pushed from 1Password. But note
> the **runtime‑vs‑deploy‑time** caveat in §4.
>
> **meal-planner `DATABASE_URL`** embeds the shared postgres password directly in
> `secrets/templates/meal-planner.yaml` so only the password is private (see
> `docs/secrets.md`).

### ⚠ Committed secrets to rotate during migration

- `.env.sample` previously contained a **real‑looking credential** for the
  `uptime` item, committed to git. Rotate it and ensure the sample holds only a
  placeholder; the value belongs in the 1Password `uptime` item. (Specific value
  redacted from this tracked doc — tracked privately as issue #23.)
- `docker/scrypted.yml` previously hardcoded the Scrypted/Watchtower webhook
  token (local‑only, but committed to git). Rotate and parameterize it via
  `docker/.env`. (Specific value redacted from this tracked doc — issue #23.)

---

## 2. Non‑secret cluster‑specific values → cluster-config

One value, one place. These are committed literals in the per‑cluster overlay.

| Variable | Used by (manifest fields) | Notes |
| --- | --- | --- |
| `NETWORK_HOSTNAME_SUFFIX` | ingress hosts in **changedetection, longhorn, meal-planner, monitoring, pihole, pikaraoke, portainer, shlink, uptime, localproxy(×4)**; `localproxy/config.yml`; `monitoring/helm-values.yml` | The dominant cross‑cutting value. Now `cluster-config` key `hostname_suffix`: write the host as `<prefix>.SUFFIX` and annotate the Ingress `cluster-config/suffix-host: "true"`; the component replaces the suffix segment at build time. CI checks all hosts share the suffix. |
| `CLUSTER_HOSTNETWORKINGIPADDRESS` | LoadBalancer services: **pihole, minecraft, chrony, data(postgres)** | Now `cluster-config` key `lan_lb_ip`: set `spec.loadBalancerIP: LAN_LB_IP` + annotate the Service `cluster-config/lan-lb-ip: "true"`. ⚠ Must **not** be committed under `status:` (desired status must never be committed — see §4). |
| `ADMIN_EMAIL` | `security/clusterissuer-letsencrypt.yml` | `cluster-config` key `acme_email`. Let's Encrypt ACME contact. |
| `SHLINK_DEFAULT_DOMAIN` | `shlink/ingress.yml`, `shlink/.env` | Public domain (e.g. bmtn.us). Config, not secret. Left **literal/un‑annotated** (not suffixed). |
| `TZ` | many deployment env vars | `cluster-config` key `tz`; centralized. |
| `PGID` / `PUID` | container env (linuxserver‑style images) | `cluster-config` keys `pgid`/`puid`; rarely changes. |
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
  Secret names (e.g. `shlink-secret-abc123`). The pushed Secret has a **fixed**
  name. The cutover order is: push the Secret first with
  `scripts/sync-secrets.sh <app>` → confirm it exists → then point the workload
  at the fixed name (separate sync). See `docs/secrets.md`.

---

## 5. Values that move out of manifests entirely

| Variable | New home |
| --- | --- |
| `CLUSTER_HOSTNAME`, `CLUSTER_NODES`, `CLUSTER_NODES_HOSTNAMES` | Ansible inventory (`ansible/inventory/hosts.yml`) |
| `MOUNT_USB`, `MOUNT_USB_DRIVE_PATH`, `MOUNT_USB_DRIVE_FORMAT`, `MOUNT_USB_MOUNT_PATH` | Ansible `group_vars` (storage role) |
| `DEPLOY_*` toggles | Replaced by ArgoCD App enable/disable (presence of the Application) |

Every row above must be accounted for before the legacy `.env` is retired.

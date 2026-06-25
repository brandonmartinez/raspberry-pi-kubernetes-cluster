# ArgoCD (Helm-managed)

ArgoCD is installed and managed via the **`argo/argo-cd` Helm chart** (chart
`8.5.7`, appVersion `v3.1.7`). Its configuration lives in
[`helm-values.yaml`](./helm-values.yaml) like every other platform stack.
`bootstrap/00-argocd.sh` is the single entrypoint for installing, adopting, or
upgrading it (`helm upgrade --install`), and is the break-glass recovery path.

> **History:** ArgoCD was originally installed from the raw upstream
> `install.yaml`. It was migrated in place to the Helm chart with
> `helm upgrade --install --take-ownership --force-conflicts` (see
> [Migration / adoption notes](#migration--adoption-notes-raw--helm)). The 22
> Application CRs, admin credentials, and JWT signing key were preserved
> throughout.

## How it is installed

```bash
./bootstrap/00-argocd.sh
```

The script: creates the `argocd` namespace, applies the ArgoCD **CRDs
out-of-band** (pinned to the appVersion, server-side — they are intentionally
*not* Helm-managed), then runs `helm upgrade --install argocd argo/argo-cd`
with [`helm-values.yaml`](./helm-values.yaml), and finally applies the ingress
(`kubectl apply -k platform/argocd`). It is idempotent.

### Why these `helm-values.yaml` knobs exist

| Key | Why |
| --- | --- |
| `crds.install: false` | CRDs are applied out-of-band so a chart removal can never cascade-delete the Application/AppProject CRs that hold all GitOps state. |
| `configs.secret.createSecret` → `false` | Preserve the existing `argocd-secret` (admin bcrypt password, `passwordMtime`, and `server.secretkey` — the JWT signing key; regenerating it invalidates every session). On a fresh cluster, `argocd-server` bootstraps this secret itself. |
| `configs.cm.application.instanceLabelKey: app.kubernetes.io/instance` | The chart otherwise overrides ArgoCD's built-in default to `argocd.argoproj.io/instance`; every already-adopted resource is tracked by the built-in default, so changing it makes every Helm-rendered app show mass `OutOfSync`. |
| `redisSecretInit.enabled` → `false` | The `argocd-redis` auth secret already exists; the chart's redis-secret-init hook Job does not exit cleanly here and would block (and time out) every helm operation. |
| `redis.image` (pinned `7.2.7-alpine`) | Adoption must not bump the cache image version or change the registry host. |
| `configs.params.server.insecure: true` | Traefik terminates TLS; `argocd-server` runs plain HTTP behind the ingress. |
| `configs.cm.url` | Public UI URL used for links/notifications. |
| `dex.enabled: false` | No SSO. The raw install's `argocd-dex-server` was orphaned at migration and deleted. |

## Upgrading ArgoCD

Bump `ARGOCD_CHART_VERSION` (and the matching `ARGOCD_VERSION` appVersion) in
`bootstrap/00-argocd.sh`, reconcile any image pins in `helm-values.yaml`, then
re-run `./bootstrap/00-argocd.sh`. CRDs update via the pinned out-of-band apply;
the chart updates via `helm upgrade`.

## Web UI

The UI is exposed at `https://gitops.<NETWORK_HOSTNAME_SUFFIX>` (e.g.
`gitops.themartinez.cloud`):

- `ingress.yml` (applied via `kubectl apply -k platform/argocd`) follows the
  portainer/pihole convention — ArgoCD has its own `admin` login, so the ingress
  only enforces HTTPS (`security-redirect-https`), no basic-auth. The host suffix
  is resolved by the `cluster-config` component, and TLS is issued by cert-manager
  (`letsencrypt-prod`).
- Admin password (fresh install): `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
- Fallback if the ingress is down: `kubectl -n argocd port-forward svc/argocd-server 8080:443`.

## Migration / adoption notes (raw → Helm)

If you ever need to re-adopt a raw-manifest install (or understand what the
first migration did), the landmines were:

1. **Immutable selectors.** The raw install's component Deployments + the
   application-controller StatefulSet use selector `{app.kubernetes.io/name}`;
   the chart adds `app.kubernetes.io/instance: argocd`. Selectors are immutable,
   so `helm upgrade` cannot mutate them. **Delete the five workloads first**
   (`argocd-server`, `argocd-repo-server`, `argocd-applicationset-controller`,
   `argocd-notifications-controller`, and the `argocd-application-controller`
   StatefulSet) — they are stateless (no `volumeClaimTemplates`, redis is a
   cache) and the Application CRs in etcd are untouched. Helm recreates them with
   the new selectors. (`argocd-redis` adopts in place — its selector already
   matches.)
2. **Field-manager conflicts.** The raw install owns fields via
   `kubectl-client-side-apply`; `--force-conflicts --server-side=true` lets Helm
   take them over.
3. **`--force-conflicts` does not prune.** It only overwrites fields Helm *sets*;
   fields the Helm manifest omits but another manager still owns (e.g. a leftover
   redis `secret-init` initContainer) must be removed with an explicit
   `kubectl patch ... --type=json` `remove` op.
4. **Failed-install recovery.** A failed `helm upgrade --install` leaves a
   `sh.helm.release.v1.argocd.vN` secret. Delete *that secret* (it touches no
   workloads) and re-run. **Never `helm uninstall`** — it would delete the
   adopted resources.

## Self-management (opt-in, do LAST)

Letting ArgoCD GitOps-manage its own Helm release is **optional**. Because the
live install is already this exact chart + `helm-values.yaml`, the self-manage
Application ([`clusters/rpi/argocd-selfmanage.yml`](../../clusters/rpi/argocd-selfmanage.yml))
should diff as a near no-op. It is intentionally **not** wired into
`clusters/rpi/root.yml`, so it never syncs automatically.

- Pro: ArgoCD upgrades become a Git change like everything else.
- Con: a bad sync can take down the controller doing the syncing. Recovery is
  always `./bootstrap/00-argocd.sh` — keep it working.

To enable: apply it by hand (`kubectl apply -f clusters/rpi/argocd-selfmanage.yml`),
sync manually in the UI, confirm a no-op diff against the live release, and
**never** enable `prune`/`selfHeal` on it without a tested bootstrap recovery
path.

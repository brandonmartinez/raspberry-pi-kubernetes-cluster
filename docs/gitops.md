# GitOps model (ArgoCD)

How this cluster is deployed and how to change it. The legacy
`k8s/src/deploy.sh` (imperative Helm + `kubectl kustomize | envsubst`) is
replaced by **ArgoCD** reconciling this Git repo.

## Layout

```
clusters/rpi/         ArgoCD control plane for this cluster
  projects.yml        AppProjects (platform, apps) — applied by bootstrap
  root.yml            app-of-apps root (renders the two files below)
  platform-apps.yml   explicit, sync-wave-ordered platform Applications
  apps-appset.yml     ApplicationSet: one Application per apps/<dir>
platform/<component>/ shared stack (ESO, cert-manager, longhorn, security,
                      data, monitoring, descheduler)
apps/<app>/           one workload per folder (kustomize base)
```

`platform/` is the shared "platform" stack the whole cluster depends on. `apps/`
are leaf workloads. Two `AppProject`s separate their blast radius.

## Sync waves (ordering)

Applied via `argocd.argoproj.io/sync-wave` on each Application:

| Wave | Components | Why |
| --- | --- | --- |
| -2 | external-secrets (controller) | ExternalSecrets can't resolve without it |
| -1 | external-secrets-config (ClusterSecretStore), cert-manager, longhorn | stores/issuers/storage before consumers |
| 0  | security (middlewares, ClusterIssuer, basic-auth), data (PostgreSQL), descheduler | shared services |
| 1  | monitoring (kube-prometheus-stack) + monitoring-config | depends on data + ServiceMonitors |
| 2  | apps/* (ApplicationSet) | leaf workloads |

## Helm Applications (multi-source pattern)

Charts are pulled from upstream; values live in this repo. Use Argo's
multi-source `$values` ref so the values file is version-controlled here:

```yaml
sources:
  - repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: "vX.Y.Z"            # FROZEN to the live release
    helm:
      valueFiles:
        - $values/platform/cert-manager/helm-values.yaml
  - repoURL: https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git
    targetRevision: main
    ref: values
```

**Freeze `targetRevision` to the version already running** (`helm list -A`).
Placeholders `0.0.0-REPLACE-WITH-LIVE` in `platform-apps.yml` must be filled
before that Application is synced. Adopting ≠ upgrading.

## Adoption safety (non-negotiable)

This is a **live** cluster. Applications are committed with **no `automated`
syncPolicy** — every first sync is manual and observed. See
`docs/runbooks/bootstrap.md`.

Forbidden during adoption:
- `helm uninstall <release>` on cert-manager/longhorn/monitoring/descheduler/ESO
  — it deletes live resources. Keep `release name == Application metadata.name`
  and the same namespace.
- Enabling `prune`/`selfHeal` on CRDs, Longhorn, PostgreSQL (`data`), or Pi-hole
  before their runbook gate.
- Changing Longhorn `defaultDataPath`/`defaultReplicaCount`/backup target, or
  any StatefulSet selector/`volumeClaimTemplate` (immutable).

### Promotion gates (per Application)

1. **Observed** — manual sync, prune off, selfHeal off (committed default).
2. **Diff-clean** — `argocd app diff` shows no surprise changes vs live.
3. **Auto-sync** — add `syncPolicy.automated: {}` (still prune off).
4. **Self-heal** — `automated.selfHeal: true`.
5. **Prune** — `automated.prune: true` only for low-risk stateless apps. CRDs,
   Longhorn, Pi-hole, PostgreSQL require explicit manual approval.

## Adding / converting an app — worked recipe (shlink)

Each `apps/<app>/` is a plain Kustomize base. Non-secret config stays in the
committed `.env` (works under `kustomize build`); secrets come from ESO; the
`secretGenerator` is removed.

**1. Copy manifests** from `k8s/src/resources/shlink/` into `apps/shlink/`
(namespace, deployment, service, ingress, hpa, pdb) **unchanged**, except
ingress hosts (step 4).

**2. `apps/shlink/kustomization.yml`** — keep the configMap, drop the secret
generator, add the ExternalSecret:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shlink
labels:
  - pairs: { app: shlink }
    includeSelectors: true
configMapGenerator:
  - name: shlink-configmap
    envs: [.env]            # non-secret config — unchanged
resources:
  - namespace.yml
  - externalsecret.yml      # NEW (replaces secretGenerator)
  - deployment.yml
  - horizontalpodautoscaler.yml
  - service.yml
  - ingress.yml
  - pdb.yml
```

**3. `apps/shlink/externalsecret.yml`** — fixed Secret name = the base name the
deployment already references (`shlink-secret`), so no workload edits. Synced
before the workload via sync-wave; `Retain` so deleting it never deletes a live
Secret:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: shlink-secret
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # before the Deployment
spec:
  refreshInterval: 1h
  secretStoreRef: { name: onepassword, kind: ClusterSecretStore }
  target:
    name: shlink-secret
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: DB_PASSWORD
      remoteRef: { key: "postgres/password" }       # <item>/<field> in 1Password
    - secretKey: SHLINK_SERVER_API_KEY
      remoteRef: { key: "shlink/api-key" }
```

**4. Ingress hosts → literals.** Kustomize cannot interpolate a substring, so
replace `${NETWORK_HOSTNAME_SUFFIX}` / `$SHLINK_DEFAULT_DOMAIN` with the real
value and mark it:

```yaml
# cluster-specific: NETWORK_HOSTNAME_SUFFIX
- host: shlink.home.arpa
# cluster-specific: SHLINK_DEFAULT_DOMAIN
- host: bmtn.us
```

(`home.arpa` is the `.env.sample` default — replace with your real suffix.)

**5. The legacy live Secret is hash-suffixed** (`shlink-secret-abc123`). The new
deployment references the fixed `shlink-secret`. ESO must create it **first** —
the sync-wave above guarantees order within the app; on first cutover, sync the
ExternalSecret and confirm the Secret exists before syncing the workload. See
`docs/secrets.md`.

## Break-glass / push deploy

GitOps is the default, but you can still push (the Pi-hole diagnosis scenario):

- `scripts/apply.sh apps/<app>` → `kustomize build | kubectl apply -f -`
  (no envsubst needed now — literals + ESO).
- or `argocd app sync <app>` for a one-off reconcile.

Document any manual change and reconcile Git promptly so Argo doesn't revert it
(once selfHeal is on).

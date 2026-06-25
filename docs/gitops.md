# GitOps model (ArgoCD)

How this cluster is deployed and how to change it. The cluster was previously
deployed by an imperative Helm + `kubectl kustomize | envsubst` pipeline; it is
now reconciled from this Git repo by **ArgoCD**.

## Layout

```
clusters/rpi/         ArgoCD control plane for this cluster
  projects.yml        AppProjects (platform, apps) — applied by bootstrap
  root.yml            app-of-apps root (renders the two files below)
  platform-apps.yml   explicit, sync-wave-ordered platform Applications
  apps-appset.yml     ApplicationSet: one Application per apps/<dir>
platform/<component>/ shared stack (cert-manager, longhorn, security,
                      data, monitoring, descheduler)
components/           shared Kustomize components (cluster-config: non-secret
                      hostname/IP/TZ fan-out, opted into by apps)
apps/<app>/           one workload per folder (kustomize base)
```

`platform/` is the shared "platform" stack the whole cluster depends on. `apps/`
are leaf workloads. Two `AppProject`s separate their blast radius.

## Sync waves (ordering)

Applied via `argocd.argoproj.io/sync-wave` on each Application:

| Wave | Components | Why |
| --- | --- | --- |
| -1 | cert-manager, longhorn | issuers/storage before consumers |
| 0  | security (middlewares, ClusterIssuer, basic-auth), data (PostgreSQL), descheduler | shared services |
| 1  | monitoring (kube-prometheus-stack) + monitoring-config | depends on data + ServiceMonitors |
| 2  | apps/* (ApplicationSet) | leaf workloads |

> Secrets are **not** in this table. They are pushed from 1Password by
> `scripts/sync-secrets.sh` before the workloads that consume them, and are not
> reconciled by ArgoCD. See [secrets.md](secrets.md).

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
- `helm uninstall <release>` on cert-manager/longhorn/monitoring/descheduler
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
committed `.env` (works under `kustomize build`); secrets are pushed from
1Password by `scripts/sync-secrets.sh` (not part of the kustomization); the
`secretGenerator` is removed.

**1. Model the manifests** on an existing converted app (e.g. `apps/shlink/`):
namespace, deployment, service, ingress, hpa, pdb. Ingress hosts come from the
`cluster-config` component (step 4), so author them with the suffix annotations
rather than hardcoded hostnames.

**2. `apps/shlink/kustomization.yml`** — keep the configMap, drop the secret
generator, and pull in the `cluster-config` component (for host/IP fan-out,
step 4). The Secret is **not** a resource here — it is pushed out-of-band:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shlink
labels:
  - pairs: { app: shlink }
    includeSelectors: true
components:
  - ../../components/cluster-config   # NEW — non-secret cluster values
configMapGenerator:
  - name: shlink-configmap
    envs: [.env]            # non-secret config — unchanged
resources:
  - namespace.yml
  - deployment.yml
  - horizontalpodautoscaler.yml
  - service.yml
  - ingress.yml
  - pdb.yml
```

**3. `secrets/templates/shlink.yaml`** — a committed Kubernetes Secret manifest
whose values are 1Password references. Fixed Secret name = the name the
deployment already references (`shlink-secret`), so no workload edits. Name the
1Password **fields** to match the Secret keys the app consumes:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: shlink-secret
  namespace: shlink
type: Opaque
stringData:
  SHLINK_SERVER_API_KEY: "{{ op://$OP_VAULT/shlink/SHLINK_SERVER_API_KEY }}"
  GEOLITE_LICENSE_KEY: "{{ op://$OP_VAULT/shlink/GEOLITE_LICENSE_KEY }}"
```

Push it with `scripts/sync-secrets.sh shlink` before syncing the workload.

The **shared PostgreSQL password is not listed here** — it is fanned in as the
`postgres-app` Secret by `scripts/sync-secrets.sh` (`secrets/postgres-app.tpl.yaml`).
Label the namespace `postgres-client: "true"` and map it in the workload:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom: { secretKeyRef: { name: postgres-app, key: password } }
```

See [secrets.md](secrets.md) for the item model, shared-secret fan-out, and
outage resilience.

**4. Ingress hosts / LAN IPs → `cluster-config`.** Don't hardcode the suffix in
every file. Write the host as `<prefix>.SUFFIX` and annotate the Ingress; the
component replaces the suffix segment at build time from one source. Public,
non-suffixed hosts (e.g. `bmtn.us`) are simply left un-annotated:

```yaml
metadata:
  annotations:
    cluster-config/suffix-host: "true"   # opt in to suffix replacement
spec:
  rules:
    - host: shlink.SUFFIX                 # -> shlink.<hostname_suffix>
  tls:
    - hosts: [shlink.SUFFIX]
      secretName: shlink-web-tls
---
# public host needs no annotation and is left untouched
spec:
  rules:
    - host: bmtn.us
```

For a LoadBalancer Service, set `spec.loadBalancerIP: LAN_LB_IP` and annotate it
`cluster-config/lan-lb-ip: "true"`. Change the suffix or LAN IP once in
`components/cluster-config/kustomization.yml` and every opted-in resource updates.

**5. The legacy live Secret is hash-suffixed** (`shlink-secret-abc123`). The new
deployment references the fixed `shlink-secret`. Push it **first** with
`scripts/sync-secrets.sh shlink` and confirm the Secret exists before syncing
the workload. See `docs/secrets.md`.

## Non-secret fan-out (cluster-config)

Non-secret, cluster-specific values do **not** belong in 1Password. They live in
one Kustomize component, `components/cluster-config`, which apps opt into with
`components: [../../components/cluster-config]`. Change a value once; every
opted-in resource updates on the next build.

| Value | Key | How an app opts in |
| --- | --- | --- |
| Hostname suffix | `hostname_suffix` | host `<prefix>.SUFFIX` + Ingress annotation `cluster-config/suffix-host: "true"` |
| LAN LoadBalancer IP | `lan_lb_ip` | `spec.loadBalancerIP: LAN_LB_IP` + Service annotation `cluster-config/lan-lb-ip: "true"` |
| ACME email, TZ, PUID/PGID | `acme_email`, `tz`, `puid`, `pgid` | reference in the relevant field/Env and add a replacement target |

The component replaces the second dotted segment of annotated Ingress hosts, so a
single-prefix placeholder (`shlink.SUFFIX`) becomes `shlink.<hostname_suffix>`.
Public hosts (e.g. `bmtn.us`) are left un-annotated and untouched. A
`cluster-config` ConfigMap is emitted into each opting-in namespace as a
byproduct (harmless; handy for debugging).

## Break-glass / push deploy

GitOps is the default, but you can still push (the Pi-hole diagnosis scenario):

- `scripts/apply.sh apps/<app>` → `kustomize build | kubectl apply -f -`
  (no envsubst needed now — literals + pushed Secrets).
- or `argocd app sync <app>` for a one-off reconcile.

Document any manual change and reconcile Git promptly so Argo doesn't revert it
(once selfHeal is on).

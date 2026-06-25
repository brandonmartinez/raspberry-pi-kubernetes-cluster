# Runbook: cluster bootstrap

Goal: introduce ArgoCD without tearing down the live cluster. Everything is additive until a workload is explicitly cut over. Secrets are pushed from 1Password out-of-band (see [../secrets.md](../secrets.md)), not managed by ArgoCD.

## 0. Do not start unless

- You have kubeconfig access from the bootstrap host.
- DNS fallback is ready; do not depend solely on Pi-hole.
- Longhorn and PostgreSQL backups have been verified.
- Chart versions in `clusters/rpi/platform-apps.yml` are frozen to live releases.

## 1. Backups and export

```sh
# Longhorn: confirm scheduled backups and perform a restore test through the UI/CLI.

# PostgreSQL logical backup.
kubectl -n data exec statefulset/postgres -- pg_dumpall -U <postgres-user> > postgres-dump.sql

# Helm values for every adopted release.
helm list -A
helm get values <release> -n <namespace> --all > helm-values-<release>.yaml

# Legacy rendered manifests.
cp k8s/src/compiled.yml compiled.snapshot.yml
cp k8s/src/compiled-data.yml compiled-data.snapshot.yml
cp k8s/src/compiled-monitoring.yml compiled-monitoring.snapshot.yml
```

Store backup artifacts somewhere durable, not only on the cluster.

## 2. DNS fallback

- Point the bootstrap host at a public resolver independent of Pi-hole.
- Point nodes at a public resolver or router resolver that does not depend on Pi-hole.
- Configure router/DHCP secondary DNS before touching Pi-hole.
- Verify `github.com`, chart repos, and 1Password resolve while Pi-hole is stopped or bypassed.

## 3. Install ArgoCD imperatively

```sh
bootstrap/00-argocd.sh
```

ArgoCD is not self-managed yet. Keep it imperative until all child apps are visible and safe.

## 4. Push secrets from 1Password

Make sure `op` is signed in and `kubectl` targets the cluster, then push the
Secrets the workloads consume:

```sh
scripts/sync-secrets.sh --dry-run     # confirm every op:// reference resolves
scripts/sync-secrets.sh               # create namespaces + apply all Secrets
```

This writes durable Kubernetes Secrets into etcd. Nothing in the cluster
authenticates to 1Password — there is no secret zero and no External Secrets
Operator. The shared `postgres-app` Secret is fanned into every namespace
labeled `postgres-client=true`; re-run after new client namespaces appear.

Confirm:

```sh
kubectl get secret -A | grep -E 'shlink-secret|postgres-app|monitoring-secret'
```

## 6. Apply AppProjects and root app

```sh
kubectl apply -f clusters/rpi/projects.yml
kubectl apply -f clusters/rpi/root.yml
```

Sync only the root enough for child Applications/ApplicationSet to appear. Do not enable automated sync.

## 7. Confirm secrets exist before syncing workloads

Workloads reference fixed Secret names (e.g. `shlink-secret`, `postgres-app`).
Those Secrets were pushed in step 4. Confirm the ones a wave needs exist before
syncing it:

```sh
kubectl get secret -n <namespace> <target-secret>
```

If a Secret is missing, re-run `scripts/sync-secrets.sh <app>` rather than
syncing the workload against a missing Secret.

## 8. Sync platform by wave

Follow [../gitops.md](../gitops.md) for the wave table; do not duplicate or skip waves.

High-level order:

1. `cert-manager`, `longhorn`
2. `security`, `data`, `descheduler`
3. `monitoring`, `monitoring-config`
4. apps

Use manual sync, prune off, self-heal off.

## 9. Sync apps

Sync one app at a time. Verify health, Service endpoints, Ingress, and logs before moving on. Pi-hole is last; use [pihole-migration.md](pihole-migration.md).

## 10. Add ArgoCD self-management last

Only after platform and apps are stable should ArgoCD manage itself. Until then, preserve the imperative install as the recovery path.

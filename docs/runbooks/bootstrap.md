# Runbook: cluster bootstrap

Goal: introduce ArgoCD and ESO without tearing down the live cluster. Everything is additive until a workload is explicitly cut over.

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

## 4. Seed secret zero

```sh
bootstrap/10-secret-zero.sh
```

This creates `external-secrets/onepassword-token`. It is the only Kubernetes secret outside 1Password.

## 5. Install ESO and ClusterSecretStore

```sh
bootstrap/20-eso.sh
```

Confirm:

```sh
kubectl -n external-secrets get pods
kubectl get clustersecretstore onepassword
```

## 6. Apply AppProjects and root app

```sh
kubectl apply -f clusters/rpi/projects.yml
kubectl apply -f clusters/rpi/root.yml
```

Sync only the root enough for child Applications/ApplicationSet to appear. Do not enable automated sync.

## 7. Sync ExternalSecrets first

For each app/platform component with secrets:

1. Sync only the `ExternalSecret` resource, or sync the app wave that contains only ESO prerequisites.
2. Wait for `Ready=True`.
3. Confirm the target Kubernetes Secret exists with the expected keys.

```sh
kubectl get externalsecrets -A
kubectl get secret -n <namespace> <target-secret>
```

Do not sync workloads that reference fixed ESO Secret names until those Secrets exist.

## 8. Sync platform by wave

Follow [../gitops.md](../gitops.md) for the wave table; do not duplicate or skip waves.

High-level order:

1. `external-secrets`
2. `external-secrets-config`, `cert-manager`, `longhorn`
3. `security`, `data`, `descheduler`
4. `monitoring`, `monitoring-config`
5. apps

Use manual sync, prune off, self-heal off.

## 9. Sync apps

Sync one app at a time. Verify health, Service endpoints, Ingress, and logs before moving on. Pi-hole is last; use [pihole-migration.md](pihole-migration.md).

## 10. Add ArgoCD self-management last

Only after platform and apps are stable should ArgoCD manage itself. Until then, preserve the imperative install as the recovery path.

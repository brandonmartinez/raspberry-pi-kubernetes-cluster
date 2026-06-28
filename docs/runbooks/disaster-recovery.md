# Runbook: disaster recovery

This order rebuilds from significant cluster loss while preserving DNS and data safety.

## Back up regularly

- Longhorn backup target and restore-test evidence.
- PostgreSQL `pg_dump` / `pg_dumpall` exports.
- 1Password homelab vault contents and access recovery path.
- Secret-zero creation procedure, not the token in git.
- ArgoCD app manifests in Git.
- Helm release values for adopted platform charts.
- Legacy `compiled*.yml` snapshots until migration is complete.
- Router/DHCP/DNS configuration screenshots or exports (verify router supports export).

## Rebuild order

1. Provision nodes with Ansible:
   ```sh
   ansible-playbook -i ansible/inventory/hosts.yml ansible/provision.yml
   ```
2. Install/restore k3s control plane and join workers.
3. Install ArgoCD imperatively with `bootstrap/00-argocd.sh`.
4. Push secrets from 1Password with `scripts/sync-secrets.sh` (creates namespaces and applies all Secrets; nothing in the cluster authenticates to 1Password).
5. Restore Longhorn backup target access.
6. Restore required Longhorn volumes before workloads mount them.
7. Apply `clusters/rpi/projects.yml` and `clusters/rpi/root.yml`.
8. Sync platform prerequisites: cert-manager, Longhorn.
9. Sync `platform/data` enough to create PostgreSQL.
10. Restore PostgreSQL from `pg_dump`.
11. Sync remaining platform apps: security, descheduler, monitoring.
12. Sync leaf apps one at a time.
13. Restore/migrate Pi-hole last, following [pihole-migration.md](pihole-migration.md).
14. Add ArgoCD self-management last.

## ArgoCD cascade-delete safety

An ApplicationSet generator change can become a data-loss event if it deletes the
child `Application` and that Application does not preserve its resources. The
incident pattern is:

1. Remove an app from the `apps/*` generator, add an exclusion, or otherwise
   transfer ownership to an explicit ArgoCD `Application`.
2. The ApplicationSet controller deletes the generated `Application`.
3. Without `spec.syncPolicy.preserveResourcesOnDeletion: true`, ArgoCD
   cascade-deletes the application's managed resources, including its Namespace
   and PVCs.
4. If a PVC uses `local-path` with the default `Delete` reclaim behavior, the
   backing data is deleted permanently.

The repository now sets `preserveResourcesOnDeletion: true` on the apps
ApplicationSet. That means removing a generated Application leaves its live
resources running; any cleanup is a deliberate manual step after backup and
verification, not a side effect of a generator edit.

Lessons from the incident:

- Treat Application ownership transfers like data-plane changes, not harmless
  YAML reshuffling.
- Confirm stateful apps have a current, restorable backup before changing their
  Application source or generator membership. Use
  [backup-verification.md](backup-verification.md) as the pre-flight gate.
- Pushed Secrets are namespace-scoped. If a namespace is cascade-deleted and then
  recreated, those Secrets are gone too; re-run `scripts/sync-secrets.sh <app>`
  before expecting workloads to start.
- Longhorn-backed PVCs may be recoverable from Longhorn backups, but `local-path`
  PVCs with delete reclaim are not a backup strategy.

Before deleting, excluding, renaming, or transferring any generated Application:

```sh
kubectl -n argocd get applicationset apps -o jsonpath='{.spec.syncPolicy.preserveResourcesOnDeletion}{"\n"}'
kubectl -n argocd get app <app> -o jsonpath='{.spec.syncPolicy.preserveResourcesOnDeletion}{"\n"}'
kubectl -n <namespace> get pvc
```

If the first check is not `true`, stop and add the safety setting before syncing
the generator change. If the app is already explicit, set the same safety on that
Application before deleting or replacing it.

## PostgreSQL restore sketch

```sh
kubectl -n data cp postgres-dump.sql <postgres-pod>:/restore.sql
kubectl -n data exec -it <postgres-pod> -- psql -U <postgres-user> -f /restore.sql
```

Validate app-level database health before syncing dependent apps.

## Longhorn restore notes

- Confirm the backup target URL matches the live intended target before syncing Longhorn.
- Do not change `defaultDataPath`, replica count, or existing PVC names during restore.
- Restore volumes first, then let workloads attach them.

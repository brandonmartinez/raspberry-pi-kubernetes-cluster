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
4. Seed secret zero with `bootstrap/10-secret-zero.sh`.
5. Install ESO and the `onepassword` ClusterSecretStore with `bootstrap/20-eso.sh`.
6. Restore Longhorn backup target access.
7. Restore required Longhorn volumes before workloads mount them.
8. Apply `clusters/rpi/projects.yml` and `clusters/rpi/root.yml`.
9. Sync platform prerequisites: external-secrets, cert-manager, Longhorn.
10. Sync `platform/data` enough to create PostgreSQL.
11. Restore PostgreSQL from `pg_dump`.
12. Sync remaining platform apps: security, descheduler, monitoring.
13. Sync leaf apps one at a time.
14. Restore/migrate Pi-hole last, following [pihole-migration.md](pihole-migration.md).
15. Add ArgoCD self-management last.

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

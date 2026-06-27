# Runbook: backup verification

Use this before any operation that touches or could affect persisted data: PVCs,
StatefulSets, databases, Longhorn volumes, or anything with a reclaim consequence.
The uptime incident proved that an ApplicationSet ownership change without the
right safety flag can delete an app and its PVC. A hoped-for recovery path is not
a backup.

## Hard gate

Before ANY operation that touches or could affect persisted data — PVCs,
StatefulSets, databases, Longhorn volumes, anything with a reclaim consequence —
you MUST, in order:

1. Verify backups are configured for the affected data.
2. Verify at least one backup has actually completed.
3. Before a data-risking change, re-verify a fresh/current backup exists first.

No verified, current backup means stop. Trigger a backup, confirm it completed,
then proceed.

## Helper

Run the read-only helper from a workstation with the normal cluster `kubectl`
context:

```sh
# Check every PVC in a namespace.
scripts/verify-backup.sh <namespace>

# Check one PVC.
scripts/verify-backup.sh <namespace> <pvc>
```

The helper checks each target PVC by resolving the bound PV and storage class.
It fails loudly for non-Longhorn storage, then for Longhorn volumes confirms:

- the volume has a `recurring-job-group.longhorn.io/<group>: enabled` label;
- that group is used by a Longhorn `RecurringJob` with `task: backup`;
- at least one backup has completed, using the job `executionCount` and/or the
  volume `lastBackup` status.

## Longhorn model

Longhorn is the backup system for durable Kubernetes volumes in this cluster.
The committed recurring jobs are:

- `backup-default`: daily at 08:00 UTC, retain 10, group `default`;
- `snapshot-default`: daily at 02:00 UTC, retain 7, group `default`.

A PVC is covered only when its Longhorn volume is labeled into a backup group,
for example:

```yaml
metadata:
  labels:
    recurring-job-group.longhorn.io/default: enabled
spec:
  storageClassName: longhorn
```

Snapshots are useful rollback points, but the data-safety gate requires backups
that leave the cluster through Longhorn's configured backup target.

## What is not covered

- `local-path` PVCs, especially with `Delete` reclaim, are not covered by
  Longhorn backups. Treat them as fragile and migrate important state to
  Longhorn before risky work.
- Pushed Kubernetes Secrets are not Longhorn data. They persist in etcd and are
  recreated from 1Password with `scripts/sync-secrets.sh`, so verify the
  1Password source and workstation access instead.
- Files outside Kubernetes volumes, router config, and workstation-only data need
  their own backup evidence.

## If no current backup exists

1. Stop the data-risking change.
2. In Longhorn, trigger an on-demand backup for the affected volume, or wait for
   the appropriate `backup-default` run if the maintenance window allows it.
3. Watch Longhorn until the backup is complete and healthy.
4. Re-run `scripts/verify-backup.sh <namespace> [pvc]` and confirm it passes with
   a current `lastBackup` or completed backup execution.
5. Continue only after the backup evidence is recorded in the change notes or PR
   description.

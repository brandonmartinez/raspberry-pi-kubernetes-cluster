# Runbook: credential rotation

Use this when a credential may have been exposed in git history or another public place. This runbook covers the old Uptime Kuma UI credential and the old Scrypted UI credential. Brandon performs the actual rotation because it requires 1Password and live service access.

Assume any value that reached a public repo was already harvested. Rotation is the real fix. Git-history scrubbing is follow-up hygiene that may reduce future accidental discovery, but it does not make the old value safe again.

## Scope and safety

- Do not paste real credential values into tickets, commits, chat, or shell history.
- Use placeholders such as `<old-uptime-ui-credential>`, `<new-uptime-ui-credential>`, and `<new-scrypted-ui-credential>` in notes.
- Keep the cluster pull-free for secrets. Secrets are pushed from the 1Password `homelab` vault with `scripts/sync-secrets.sh`.
- Do not use External Secrets Operator for this repo.

## Rotate Uptime Kuma

1. Open the 1Password `homelab` vault item that stores the Uptime Kuma UI credential.
2. Generate a new value in 1Password and save it in the correct field. Record only `field` → `<new-uptime-ui-credential>` in notes.
3. Sign in to Uptime Kuma with the current credential and rotate the UI credential inside the service.
4. If Uptime Kuma reads any value from a pushed Kubernetes Secret, re-push only that target:
   ```sh
   scripts/sync-secrets.sh uptime
   ```
5. Verify the old UI credential no longer works and the new value from 1Password does work.
6. Verify Uptime Kuma monitors are still running and alert delivery still works.

## Rotate Scrypted

1. Open the 1Password `homelab` vault item that stores the Scrypted UI credential.
2. Generate a new value in 1Password and save it in the correct field. Record only `field` → `<new-scrypted-ui-credential>` in notes.
3. Sign in to Scrypted with the current credential and rotate the UI credential inside the service.
4. If Scrypted is later moved to Kubernetes and reads from a pushed Secret, re-push that service target with `scripts/sync-secrets.sh <target>`.
5. Verify the old UI credential no longer works and the new value from 1Password does work.
6. Verify cameras, plugins, and automations still connect after the change.

## Re-push and reconcile pushed Secrets

After any namespace recreation, app migration, or Secret-consuming service change:

```sh
scripts/sync-secrets.sh --verify <target>
scripts/sync-secrets.sh --reconcile <target>
```

Use `--verify` first when you only want a read-only presence check. Use `--reconcile` when the Secret is missing and should be pushed from 1Password.

For shared PostgreSQL clients, check the fan-out target:

```sh
scripts/sync-secrets.sh --verify postgres-app
scripts/sync-secrets.sh --reconcile postgres-app
```

## Decide whether to scrub git history

Rotate first, then decide whether a history scrub is worth the coordination cost.

Reasons to scrub:

- Reduce casual discovery of the old values in the public repo history.
- Lower the chance that future clones, mirrors, or searches continue to surface the old values.
- Demonstrate cleanup even though the exposed values are no longer valid.

Risks and impact:

- A scrub rewrites public git history and requires a force-push.
- Existing forks, clones, open branches, and pull requests will diverge.
- Contributors must coordinate fresh clones or hard resets after the rewrite.
- Tags and release references may need to be recreated or documented.
- Any cached copies, forks, package indexes, or search-engine snapshots can still retain the old values.

Common tools:

- `git filter-repo` for precise path, blob, or text replacement rewrites.
- BFG Repo-Cleaner for simpler large-object or literal text cleanup.

Decision framing:

1. Confirm both exposed UI credentials have been rotated in 1Password and in the services.
2. Confirm the old values fail against the live services.
3. List affected refs, forks, and collaborators that would need coordination.
4. If the coordination cost is acceptable, schedule a maintenance window for the rewrite and force-push.
5. If the cost is not acceptable, document that rotation is complete and the remaining public history is accepted hygiene debt.

## Verification checklist

- Uptime Kuma accepts only `<new-uptime-ui-credential>`.
- Scrypted accepts only `<new-scrypted-ui-credential>`.
- The old Uptime Kuma and Scrypted values fail.
- The relevant 1Password `homelab` items contain the new values.
- `scripts/sync-secrets.sh --verify <target>` reports all expected pushed Secrets present for any Kubernetes-backed target.
- Service health checks, monitors, cameras, and automations remain healthy.
- If a history scrub is chosen, all collaborators have acknowledged the force-push plan before it happens.

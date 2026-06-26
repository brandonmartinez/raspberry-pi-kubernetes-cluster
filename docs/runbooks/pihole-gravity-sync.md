# Runbook: Pi-hole gravity sync

Pi-hole's 3-replica StatefulSet uses independent per-pod PVCs. Without active
synchronization, blocklists (gravity), custom DNS records, whitelists, and
settings can diverge between pods. Because queries are load-balanced across all
three, a divergent replica means roughly one-third of DNS queries hit inconsistent
ad-blocking results.

A custom CronJob — `pihole-gravity-sync` — runs every 6 hours and exports the
full Teleporter backup from the primary replica (`pihole-0`) and restores it to
each secondary (`pihole-1`, `pihole-2`).

> **Background:** [Orbital Sync](https://github.com/mattwebbio/orbital-sync) was
> the preferred tool for this function but was archived in March 2025 without
> Pi-hole v6 support. This CronJob replicates that function directly against the
> Pi-hole v6 REST API using a Python stdlib script
> (`apps/pihole/gravity-sync.py`).

---

## Architecture

### Resources

| Resource | Name | Description |
|---|---|---|
| CronJob | `pihole-gravity-sync` | Runs the sync script on a schedule |
| ConfigMap | `pihole-gravity-sync-script` | Mounts `gravity-sync.py` at `/scripts/sync.py` |
| Image | `python:3.12-alpine3.21` | Multi-arch (linux/arm64 for RPi 4B), stdlib-only |

Source files: `apps/pihole/gravity-sync.yml`, `apps/pihole/gravity-sync.py`.

### Schedule

```
0 */6 * * *   (every 6 hours)
```

`concurrencyPolicy: Forbid` prevents overlapping runs. Up to 3 successful and 3
failed job records are retained.

### Teleporter API flow

The script uses the **Pi-hole v6 REST API** (Python stdlib only — no pip):

1. **Authenticate** to primary: `POST /api/auth` with the admin password →
   receives a session SID.
2. **Export**: `GET /api/teleporter` (with `sid` header) → tar.gz binary
   containing gravity DB, custom DNS records, whitelists, and settings.
3. **Logout** primary: `DELETE /api/auth`.
4. For **each secondary**, in sequence:
   a. Authenticate → SID.
   b. **Import**: `POST /api/teleporter` (multipart form) → restores from the
      tar.gz captured in step 2.
   c. Logout.
5. If any secondary import fails, the script exits non-zero (job retries up to 2
   times per `backoffLimit`).

### Primary / secondary model

| Role | Pod DNS name |
|---|---|
| Primary (export source) | `pihole-0.pihole.pihole.svc.cluster.local` |
| Secondary | `pihole-1.pihole.pihole.svc.cluster.local` |
| Secondary | `pihole-2.pihole.pihole.svc.cluster.local` |

`pihole-0` is always the source of truth. Changes made on a secondary pod's UI
will be overwritten on the next sync run.

### Authentication

The admin password is read from the environment variable `PIHOLE_PASSWORD`,
which is sourced from the `pihole-secret` Secret:

- Secret name: `pihole-secret`
- Secret key: `FTLCONF_webserver_api_password`

The Secret is pushed (never pulled at runtime) by `scripts/sync-secrets.sh`.
See [docs/secrets.md](../secrets.md) for the full push-sync model.

---

## Operator init / manual trigger

**When to run this:** After any of these events:

- A Pi-hole pod is recreated from scratch (PVC deleted or node failure with
  storage loss).
- Initial cluster bootstrap — the first time all three pods are running but
  have not yet synced.
- After manually restoring only `pihole-0` from a backup.

A freshly created pod starts with an empty gravity database. The readinessProbe
gates DNS traffic on FTL functioning, so the pod will not serve DNS until after
FTL reloads — which happens automatically after the Teleporter import completes.
This means the new pod is **safe** (it will not serve stale or empty results to
clients), but it will not block any ads until the sync finishes.

Run the CronJob as a one-off Job:

```sh
kubectl create job -n pihole gravity-sync-manual --from=cronjob/pihole-gravity-sync
kubectl wait -n pihole --for=condition=Complete job/gravity-sync-manual --timeout=120s
kubectl delete job -n pihole gravity-sync-manual
```

> If the Job fails (exit non-zero), the pod log will indicate which host failed.
> See Troubleshooting below before retrying.

---

## Troubleshooting

### View the most recent scheduled sync logs

```sh
# List recent jobs from the CronJob
kubectl get jobs -n pihole -l batch.kubernetes.io/controller-uid

# Stream logs from the latest job pod
kubectl logs -n pihole -l job-name=<job-name> --follow
```

Or use a label selector to find the pod:

```sh
kubectl get pods -n pihole -l app=pihole --show-labels
```

### What a failed authentication looks like

A failed `POST /api/auth` will raise an `urllib.error.HTTPError` (typically
`HTTP 401 Unauthorized`) and the pod logs will show:

```
ERROR: HTTP Error 401: Unauthorized
Sync FAILED for: ['pihole-1.pihole.pihole.svc.cluster.local']
```

Check that the `pihole-secret` Secret is present and holds the correct value:

```sh
kubectl get secret -n pihole pihole-secret -o jsonpath='{.data.FTLCONF_webserver_api_password}' | base64 -d
```

Re-push the Secret if it is missing or stale:

```sh
scripts/sync-secrets.sh pihole
```

### Verify gravity counts match across pods

After a successful sync all three pods should report the same gravity domain
count. Execute the Pi-hole CLI on each pod:

```sh
for pod in pihole-0 pihole-1 pihole-2; do
  echo -n "$pod: "
  kubectl exec -n pihole "$pod" -- pihole -q --all 2>/dev/null | grep -c '^' || \
  kubectl exec -n pihole "$pod" -- sqlite3 /etc/pihole/gravity.db \
    "SELECT COUNT(*) FROM gravity;" 2>/dev/null
done
```

> **Note:** the exact command to query gravity depends on the Pi-hole version
> installed in the pod image. Verify the correct invocation against the running
> image if the above returns an error.

Alternatively, visit the Pi-hole admin UI for each pod via port-forward and
compare the "Gravity last updated" timestamp and domain count on the dashboard:

```sh
kubectl port-forward -n pihole pihole-0 8080:80
kubectl port-forward -n pihole pihole-1 8081:80
kubectl port-forward -n pihole pihole-2 8082:80
```

### CronJob not running / missed schedule

```sh
kubectl describe cronjob -n pihole pihole-gravity-sync
```

Look for `FailedNeedsStart` or `TooManyMissedSchedules` events. The most common
causes are a suspended CronJob or clock skew on the controller node.

```sh
# Check if the CronJob is suspended
kubectl get cronjob -n pihole pihole-gravity-sync -o jsonpath='{.spec.suspend}'
```

---

## Related runbooks

- [Pi-hole migration](./pihole-migration.md) — safe deployment order, DNS
  cutover, and rollback.
- [Break-glass](./break-glass.md) — push a manifest directly when ArgoCD is
  unavailable.

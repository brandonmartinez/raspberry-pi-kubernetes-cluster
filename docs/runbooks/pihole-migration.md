# Runbook: Pi-hole migration

Pi-hole is the home network DNS path and must be migrated last. The safe goal is no simultaneous DNS outage and no uncontrolled Argo revert.

## Pre-stage fallback

- Configure router/DHCP with a secondary resolver that is not Pi-hole.
- Point the operator host and nodes at public or router DNS during the migration.
- Confirm name resolution works with Pi-hole bypassed.
- Lower DHCP/DNS cache risk where possible (verify router behavior).
- Confirm the current Pi-hole admin password is available in 1Password (item `pihole`, field `FTLCONF_webserver_api_password`) or as a manual fallback Secret.

## Prepare ArgoCD

- Keep auto-sync and self-heal disabled for Pi-hole.
- Ensure prune is disabled.
- Push the Pi-hole Secret first with `scripts/sync-secrets.sh pihole` and confirm `pihole-secret` exists before syncing the workload.
- Confirm the Service keeps the intended LoadBalancer IP.

## Unbound namespace cutover (do this BEFORE migrating Pi-hole)

Unbound is Pi-hole's primary upstream resolver. Live, it runs in the `pihole`
namespace as `Service/unbound-service` with the fixed `clusterIP: 10.43.100.20`
(Pi-hole config: `FTLCONF_dns_upstreams=10.43.100.20#53;1.1.1.1#53`). The GitOps
repo moves unbound to its own `unbound` namespace **but keeps the same fixed
ClusterIP**. A ClusterIP is unique cluster-wide, so the new Service cannot bind
`10.43.100.20` until the old one is deleted — syncing the unbound app blind will
fail with `provided IP is already allocated`.

Pi-hole's secondary upstream `1.1.1.1#53` carries DNS during the brief gap, so
there is no full outage — but keep the pre-staged fallback (above) active anyway.

Ordered cutover:

1. **Stage the new namespace without the Service.** Sync the `unbound` app's
   namespace, configmap, Deployment, HPA, and PDB, but NOT `service.yml` yet
   (e.g. selective sync, or temporarily drop `service.yml` from the app and add
   it back in step 4). Wait until the new Pods are Ready:
   ```sh
   kubectl -n unbound rollout status deploy/unbound
   kubectl -n unbound get pods -o wide   # confirm spread across nodes
   ```
2. **Confirm Pi-hole still resolves via the secondary upstream** (it is now
   answering from `1.1.1.1` because `10.43.100.20` still points at the old
   service, which we are about to remove):
   ```sh
   dig @<pihole-loadbalancer-ip> example.com A +short
   ```
3. **Free the ClusterIP** by deleting the OLD service in the `pihole` namespace:
   ```sh
   kubectl -n pihole delete svc unbound-service
   ```
   `10.43.100.20` is now unallocated; Pi-hole continues on `1.1.1.1`.
4. **Bind the new Service** in the `unbound` namespace (sync `service.yml`).
   Because the Pods are already Ready, endpoints populate immediately:
   ```sh
   kubectl -n unbound get svc unbound-service -o wide   # CLUSTER-IP 10.43.100.20
   kubectl -n unbound get endpoints unbound-service     # non-empty
   ```
5. **Verify unbound answers on the reclaimed IP** and that Pi-hole's primary
   upstream is healthy again:
   ```sh
   kubectl -n pihole exec deploy/pihole -- dig @10.43.100.20 example.com A +short
   ```
6. **Clean up the old workload** only after the new one is verified: remove the
   leftover unbound Deployment/HPA/PDB still running in the `pihole` namespace
   (the delete in step 3 only removed the Service). nebulasync moves to its own
   `nebulasync` namespace too; it has no fixed ClusterIP so it can be synced
   normally, but scale down the old copy in `pihole` once the new one is healthy
   to avoid two instances writing the same shared state.

Only after unbound is stable in its own namespace should you proceed to the
Pi-hole workload migration below. Pi-hole itself stays in the `pihole` namespace,
so its `10.43.100.20` upstream reference does not change.

## Migrate one change at a time

1. Apply/sync only the next smallest change.
2. Wait for Pods Ready and endpoints populated.
3. Test DNS from outside the cluster:
   ```sh
   dig @<pihole-loadbalancer-ip> example.com A
   dig @<pihole-loadbalancer-ip> example.com A +tcp
   nslookup example.com <pihole-loadbalancer-ip>
   ```
4. Check Pi-hole web UI and logs.
5. Move to the next change only after UDP and TCP 53 pass.

## Avoid all replicas restarting together

- Use a PDB with `minAvailable: 1` where supported.
- Use rolling update settings such as `maxUnavailable: 0` / `maxSurge: 1` when applicable (verify the workload kind supports them).
- Do not combine config, Secret, image, Service, and ingress changes in one sync.
- Avoid node drains during migration.

## Rollback

1. Stop Argo from self-healing the broken state.
2. Reapply the last known-good manifest via `scripts/apply.sh apps/pihole` or manually patch the single failing field.
3. Restore router/DHCP primary DNS to the previous working resolver if needed.
4. Verify UDP and TCP 53 externally.
5. Reconcile Git with the rollback before enabling automation.

Pi-hole should be promoted to auto-sync/self-heal only after multiple clean syncs and an explicit operator decision.

## Gravity sync after migration

Once all three Pi-hole replicas are running, trigger an initial gravity sync
immediately so all pods share the same blocklists and settings:

See [pihole-gravity-sync.md](./pihole-gravity-sync.md) for the manual trigger
procedure and full details of the CronJob architecture.

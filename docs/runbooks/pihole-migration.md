# Runbook: Pi-hole migration and per-ordinal health architecture

Pi-hole is the home network DNS path and must be migrated last. The safe goal is no simultaneous DNS outage and no uncontrolled Argo revert.

This runbook also covers the transition from the shared Pi-hole Service (10.43.100.30) to the **per-ordinal DNS Services architecture** where dnsdist directly health-checks three independent Services (`pihole-0-dns-svc`, `pihole-1-dns-svc`, `pihole-2-dns-svc` at 10.43.100.31–33). The per-ordinal design eliminates the conntrack flapping failure mode that amplified a single Pi-hole pod failure into shared VIP unavailability.

## Remedy Plan: Immediate, Later, Explicit Decisions

This plan is **prioritized by risk and urgency**. Complete in order to minimize DNS disruption.

### Immediate (gates all later work)

1. **Fresh Longhorn backup gate**
   - Confirm all three `pihole-pvc-pihole-0`, `pihole-pvc-pihole-1`, `pihole-pvc-pihole-2` PVCs are in the `default` Longhorn backup recurring job group.
   - Verify at least one completed backup exists for each PVC (not just scheduled).
   - Wait 1–2 minutes and confirm a fresh backup just completed: `kubectl -n longhorn-system get backup.longhorn.io | grep pihole`.
   - **Action if no backup:** Trigger manual backup and wait for completion before proceeding.

2. **Baseline DNS health check**
   - Verify all three Pi-hole pods are `Running 1/1`: `kubectl -n pihole get pods`.
   - Before the first rollout, verify the proposed static ClusterIPs are unused:
     ```sh
     kubectl get svc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.spec.clusterIP' \
       | grep -E '10\.43\.100\.(31|32|33)$'
     ```
     The command must return no Services. After the additive sync, verify each
     per-ordinal Service exists with exactly one endpoint.
   - Test DNS from a LAN client: `nslookup themartinez.cloud 192.168.52.53` (UDP).
   - Test TCP path: `dig @192.168.52.53 themartinez.cloud +tcp`.
   - Document baseline timestamp and query latencies.

3. **ArgoCD sync gates**
   - Confirm `apps/pihole` Application is set to `manual` sync (no auto-sync, no self-heal, no prune).
   - Confirm `apps/dnsdist` Application is set to `manual` sync (same guards).
   - Confirm `apps/unbound` Application is set to `manual` sync (same guards).

### Later (after per-ordinal architecture is stable)

1. **Pi-hole query-history retention policy** — Coordinate with Brandon on acceptable retention (storage/privacy trade-off); defer if not yet decided.
2. **Resource sizing review** — Ash to verify CPU/memory requests/limits are appropriate post-migration.
3. **CoreDNS HA** — Consider upstream resolver resilience if unbound is not meeting latency SLOs.
4. **Unbound probes / PDB** — Add health probes and PDB to unbound if not present.
5. **dnsdist security image** — Update base image and probe binaries once Dallas confirms strategy.
6. **Monitoring/exporter gaps** — Close remaining observability gaps per Ash's assessment.

### Explicit User Decisions (require Brandon's confirmation before proceeding)

1. **UDM-Pro secondary resolver verification** — After per-ordinal rollout completes, manually verify that the UDM-Pro secondary DNS resolver (the klipper node-IP fallback) is configured and working. See "Production verification checklist" section below.

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

## Per-ordinal Pi-hole Services rollout (new architecture)

This section covers the transition from a shared Pi-hole Service to the per-ordinal DNS Services (`pihole-0-dns-svc`, `pihole-1-dns-svc`, `pihole-2-dns-svc`) that dnsdist directly health-checks. This is a **single additive manifest sync** — no Pi-hole pod rolling restarts occur during Service creation.

### Rollout order (additive Services + dnsdist sync)

All three per-ordinal Services are applied in one manual ArgoCD sync. This is
safe only after the diff confirms the three Services are the sole Pi-hole
changes; additive Service creation does not restart Pi-hole pods.

1. **Verify baseline DNS health** before touching Services:
   ```sh
   kubectl -n pihole get pods -o wide
   kubectl -n pihole get svc pihole-dns-svc -o wide
   nslookup themartinez.cloud 192.168.52.53   # shared VIP should still work
   ```

2. **Manually sync the Pi-hole Application** with prune and self-heal still off.
   Review the ArgoCD diff first and confirm it only adds the three Services.
   For break-glass push deployment, use `scripts/apply.sh apps/pihole`; do not
   apply the raw source YAML because the app relies on Kustomize labels.

   This creates three new Services: `pihole-0-dns-svc`, `pihole-1-dns-svc`, `pihole-2-dns-svc`.
   No Pi-hole pods are restarted, no rolling updates occur. The shared Service remains unchanged.

3. **Verify all three per-ordinal Services are ready and have endpoints**:
   ```sh
   kubectl -n pihole get svc pihole-0-dns-svc pihole-1-dns-svc pihole-2-dns-svc -o wide
   kubectl -n pihole get endpoints pihole-0-dns-svc pihole-1-dns-svc pihole-2-dns-svc
   ```
   Each Service should show exactly one endpoint (the corresponding Pi-hole pod).

4. **Verify per-ordinal DNS answers independently** from a pod with `dig`:
   ```sh
   kubectl -n pihole exec pihole-0 -- dig @10.43.100.31 themartinez.cloud A +short
   kubectl -n pihole exec pihole-0 -- dig @10.43.100.32 themartinez.cloud A +short
   kubectl -n pihole exec pihole-0 -- dig @10.43.100.33 themartinez.cloud A +short
   kubectl -n pihole exec pihole-0 -- dig @10.43.100.31 themartinez.cloud A +tcp +short
   ```
   All three should answer. If any fails, investigate that pod's readiness probe and logs.

5. **Verify dnsdist is already configured** to health-check per-ordinal Services:
   - dnsdist ConfigMap or mounted config should have three `newServer()` blocks for `10.43.100.31`, `10.43.100.32`, `10.43.100.33`.
   - Confirm `apps/dnsdist/dnsdist.conf` (or the app's ConfigMap) lists all three ordinals as independent backends.

6. **Manually sync the dnsdist Application** to apply the generated ConfigMap
   and Deployment template update. Do not use `rollout restart` as a substitute
   for ArgoCD sync; restarting the old template does not apply the new config.
   ```sh
   kubectl -n dnsdist rollout status deploy/dnsdist
   ```

7. **Verify DNS still works** after dnsdist sync:
   ```sh
   nslookup themartinez.cloud 192.168.52.53   # VIP should still answer
   nslookup bmtn.us 192.168.52.53
   dig @192.168.52.53 themartinez.cloud +tcp
   ```

8. **Verify dnsdist is routing to per-ordinal Services**:
   ```sh
   kubectl -n dnsdist logs deploy/dnsdist --tail=100 | grep -E "pihole-[0-2]|down|up"
   # Startup should add/mark all three ordinals up with no repeated transitions.
   ```

All three per-ordinal Services are now live and dnsdist is independently health-checking each one. This completes the additive Services phase.

### Abort conditions (rollback immediately if any occur)

- **DNS latency jumps >500ms** consistently after dnsdist restart → rollback dnsdist to the previous config immediately.
- **Any dnsdist or Pi-hole pod restarts in a tight loop** (CrashLoopBackOff) → diagnose the crash before proceeding.
- **Per-ordinal Service endpoint is empty** for >30s → check the corresponding Pi-hole pod's readiness probe, logs, and storage.
- **Queries fall back to public resolvers** (Cloudflare/Google) → all three ordinals are marked down; stop and investigate.
- **UDM-Pro DHCP is disrupted** during rollout → pause the rollout and stabilize the network first.

### One-Pi-hole-at-a-time gate (for later config/image/data changes only)

After the additive per-ordinal Services sync is complete, the following gate applies to any **subsequent changes to Pi-hole pod config, image, or data** (e.g., configuration updates, image upgrades, Secret rotations). This gate does NOT apply to the Service creation above — all three Services are created at once.

- Apply only one Pi-hole pod change at a time (e.g., config change affecting pihole-0, then pihole-1, then pihole-2).
- Use rolling updates (`maxUnavailable: 1` via StatefulSet default) so at most one pod is down at a time.
- Verify DNS health between each pod change.
- Do not combine per-ordinal Service creation with Pod config/image changes.
- Do not combine Pi-hole changes with node maintenance, hardware changes, or network reconfiguration.

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

1. Apply/sync only the next smallest change (configuration, image, Secret, or manifests).
2. Wait for Pods Ready and endpoints populated: `kubectl -n pihole get pods,svc,endpoints -o wide`.
3. **UDP test** (primary protocol):
   ```sh
   dig @<pihole-service-ip> example.com A        # should see ANSWER section
   nslookup example.com <pihole-service-ip>       # should resolve
   ```
4. **TCP test** (verify fallback path):
   ```sh
   dig @<pihole-service-ip> example.com A +tcp   # should answer over TCP
   ```
5. Check Pi-hole web UI and logs for errors:
   ```sh
   kubectl -n pihole logs pihole-0 --tail=30 | grep -E "(ERROR|WARN|blocked|gravity)"
   ```
6. Move to the next change **only after both UDP and TCP pass and no error logs appear**.

## Avoid all replicas restarting together

- Use a PDB with `minAvailable: 1` where supported (Pi-hole has `minAvailable: 2`).
- Use rolling update settings such as `maxUnavailable: 0` / `maxSurge: 1` when applicable (StatefulSet uses RollingUpdate by default).
- Do not combine config, Secret, image, Service, and ingress changes in one sync.
- Avoid node drains during migration.

## Rollback

1. Keep the additive per-ordinal Services; they are harmless and avoiding their
   deletion removes unnecessary rollback risk.
2. Revert both `apps/dnsdist/dnsdist.conf` and
   `apps/dnsdist/deployment.yml` to the last known-good dnsdist revision in Git,
   then manually sync only the dnsdist Application. This restores both backend
   routing and probe behavior. Prune and self-heal remain off.
3. Observe the dnsdist rolling Deployment one pod at a time. Stop if `.53`
   loses UDP or TCP resolution.
4. Restore router/DHCP primary DNS to the previous working resolver if needed.
5. **Verify rollback immediately:**
   ```sh
   nslookup themartinez.cloud 192.168.52.53      # VIP must answer
   dig @192.168.52.53 bmtn.us +tcp                # TCP must work
   kubectl -n pihole exec pihole-0 -- \
     dig @10.43.100.30 themartinez.cloud A +short # shared backend must answer
   kubectl -n pihole get pods -o wide             # all pods must be Ready
   ```
6. Keep Pi-hole and dnsdist manual-sync with prune/self-heal off.

Do not promote Pi-hole to auto-sync/self-heal as part of this remediation.

## Production verification checklist

After the per-ordinal rollout is complete and DNS is stable for >24h, verify production readiness:

- [ ] Backup gate: All three pihole PVCs have recent Longhorn backups (completed within the last 1h).
- [ ] DNS from primary VIP works: `nslookup themartinez.cloud 192.168.52.53` and `dig @192.168.52.53 themartinez.cloud +tcp`.
- [ ] DNS from secondary fallback works: `nslookup themartinez.cloud 192.168.52.110` (or the configured klipper node IP).
- [ ] All three dnsdist pods `Ready 1/1`: `kubectl -n dnsdist get pods`.
- [ ] All three Pi-hole pods `Running 1/1`: `kubectl -n pihole get pods`.
- [ ] All three per-ordinal Services have endpoints: `kubectl -n pihole get endpoints pihole-0-dns-svc pihole-1-dns-svc pihole-2-dns-svc`.
- [ ] **UDM-Pro secondary resolver configured:** Manually verify in UDM-Pro UI that DHCP secondary DNS is set to the klipper fallback node IP (e.g., 192.168.52.110). Test with `nslookup themartinez.cloud 192.168.52.110` from a LAN client.
- [ ] dnsdist startup logs add/mark all ordinal backends up and show no repeated transitions: `kubectl -n dnsdist logs deploy/dnsdist --tail=100 | grep -E "pihole-[0-2]|down|up"`.
- [ ] No error logs in Pi-hole: `kubectl -n pihole logs statefulset/pihole --tail=100 | grep -i "error"` should be empty or benign.
- [ ] Gravity sync configured and passing: See [pihole-gravity-sync.md](./pihole-gravity-sync.md).
- [ ] ArgoCD Applications remain `manual` sync, `prune: OFF`, `selfHeal: OFF` until explicitly approved.

## Gravity sync after migration

Once all three Pi-hole replicas are running, trigger an initial gravity sync
immediately so all pods share the same blocklists and settings:

See [pihole-gravity-sync.md](./pihole-gravity-sync.md) for the manual trigger
procedure and full details of the CronJob architecture.

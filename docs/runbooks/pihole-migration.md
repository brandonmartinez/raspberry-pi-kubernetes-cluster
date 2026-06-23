# Runbook: Pi-hole migration

Pi-hole is the home network DNS path and must be migrated last. The safe goal is no simultaneous DNS outage and no uncontrolled Argo revert.

## Pre-stage fallback

- Configure router/DHCP with a secondary resolver that is not Pi-hole.
- Point the operator host and nodes at public or router DNS during the migration.
- Confirm name resolution works with Pi-hole bypassed.
- Lower DHCP/DNS cache risk where possible (verify router behavior).
- Confirm the current Pi-hole admin password is available through ESO or a manual fallback Secret.

## Prepare ArgoCD

- Keep auto-sync and self-heal disabled for Pi-hole.
- Ensure prune is disabled.
- Sync the Pi-hole ExternalSecret first and wait for the target Secret.
- Confirm the Service keeps the intended LoadBalancer IP.

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

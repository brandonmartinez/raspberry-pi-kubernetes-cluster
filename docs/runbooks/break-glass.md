# Runbook: break glass

Use this when GitOps is too slow or a service outage requires direct diagnosis, especially Pi-hole/DNS incidents. Prefer minimal, reversible changes and reconcile Git immediately after.

## Push apply path

```sh
# Render and apply one GitOps app path directly.
scripts/apply.sh apps/<app>
```

The helper is expected to run `kustomize build | kubectl apply -f -`. No legacy `envsubst` should be required for GitOps apps.

## ArgoCD one-off sync

```sh
argocd app diff <app>
argocd app sync <app>
argocd app wait <app> --health --sync
```

Use this when Git already contains the desired state but the app is not automated.

## Emergency manual change

1. Disable or avoid self-heal on the affected app if it would revert the fix.
2. Patch the smallest resource possible.
3. Record the command, reason, timestamp, and observed effect.
4. Commit the equivalent manifest change or revert the manual patch.
5. Run `argocd app diff <app>` until Git and live state agree.
6. Re-enable self-heal only after the diff is intentional and clean.

## DNS resolver fallback

The LAN's DNS path is a single MetalLB Layer-2 VIP by design:

```text
UDM-Pro DHCP --> 192.168.52.53 (DNS VIP) --> dnsdist (3 replicas, health-checked)
            --> Pi-hole --> unbound (split-horizon for themartinez.cloud)
```

One VIP is intentional. Node failure is already covered by MetalLB L2 failover
(~10s, the VIP migrates to a healthy node). A *second* cluster VIP would not add
resilience: it shares fate with the same dnsdist -> Pi-hole -> unbound stack, and
clients do not fail over cleanly between two resolvers (OS-dependent, timeout-based).
The ingress VIP `192.168.52.80` (Traefik) has the same single-VIP + MetalLB-failover
model across its 2 spread replicas.

If the entire cluster DNS path is down (or you are debugging it and need the LAN to
keep resolving), temporarily point the UDM-Pro's DHCP DNS at a public resolver:

1. UDM-Pro -> Settings -> Networks -> (LAN) -> DHCP -> DNS Server -> set `1.1.1.1`
   (and `8.8.8.8`). Clients pick it up on lease renewal; bounce a client's link to
   force it.
2. Trade-off while failed over: you lose **split-horizon** (`*.themartinez.cloud`
   resolves to the public IP, not the LAN ingress VIP) and **Pi-hole ad-blocking**.
3. Revert the DHCP DNS to `192.168.52.53` once dnsdist/Pi-hole/unbound are healthy,
   and bounce a client to confirm internal names resolve to `192.168.52.80` again.

Keep this a *temporary* break-glass step, not a standing secondary DNS entry — a
permanent public secondary would silently bypass split-horizon and ad-blocking for
any client that races it.

## Diagnosis checklist

```sh
kubectl get app -n argocd
argocd app get <app>
kubectl -n <namespace> get pods,svc,ingress,endpoints
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> logs <pod> --all-containers --tail=100
```

## Forbidden during adoption

- Do not run `helm uninstall` on adopted releases such as cert-manager, Longhorn, monitoring, or descheduler.
- Do not enable prune/self-heal for CRDs, Longhorn, PostgreSQL, or Pi-hole without the relevant runbook gate.
- Do not recreate StatefulSets, PVCs, or immutable selectors to make Argo diffs disappear.

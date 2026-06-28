# DNS architecture

This cluster intentionally teaches the full DNS path instead of hiding it behind
one appliance. The LAN resolver is a Kubernetes Service, but it is still operated
as production infrastructure: if DNS is down, almost everything else feels down.

## Request path

```text
LAN clients
  -> UDM-Pro DHCP advertises 192.168.52.53 as primary DNS
  -> MetalLB Layer-2 VIP 192.168.52.53 (dns-vip)
  -> dnsdist LoadBalancer Service in apps/dnsdist
  -> Pi-hole DNS Service
  -> unbound / upstream resolvers
```

`192.168.52.53` is the primary DNS address for the home LAN. The UDM-Pro hands
it out by DHCP, and clients send both UDP and TCP port 53 traffic there. MetalLB
announces that address on Layer 2 and sends traffic to the `dnsdist`
LoadBalancer Service.

`dnsdist` is the front door. It runs multiple replicas, uses
`externalTrafficPolicy: Local`, and is spread across nodes so MetalLB only
announces the VIP from a node with a ready local dnsdist endpoint. dnsdist then
forwards normal traffic to the Pi-hole cluster Service. If every Pi-hole backend
is unhealthy, dnsdist has a last-ditch public resolver pool so the LAN can still
resolve names while Pi-hole is repaired; normal operation should be 100% Pi-hole.

Pi-hole remains the policy layer behind dnsdist: ad blocking, local DNS behavior,
and the handoff to unbound/upstream resolvers. Pi-hole is no longer the public
LoadBalancer entrypoint for the LAN.

## High availability and failure modes

The DNS design now has three distinct layers. They fail differently, so diagnose
them separately.

### MetalLB speaker: VIP announcement

The MetalLB speaker is the Layer-2 announcement plane. Speakers run on nodes and
use memberlist/L2 leader election so one node announces `192.168.52.53` at a
time. If that node disappears, another speaker can take over the VIP in seconds.
This part is already HA.

Once a LoadBalancer IP has been allocated, speakers can continue announcing it
even if the controller later goes down. The speaker is responsible for ARP/NDP
announcement, not allocation decisions.

### MetalLB controller: VIP allocation

The MetalLB controller allocates requested LoadBalancer IPs from the `dns-vip`
`IPAddressPool`. For DNS, the `dnsdist` Service explicitly requests
`192.168.52.53` and `loadBalancerClass: metallb.io/layer2`.

The controller is intentionally single-replica. MetalLB does not provide leader
election for multiple active controllers in this deployment model; running two
controllers risks duplicate or conflicting allocation decisions. DNS HA is not
achieved by adding a second controller. The correct controls are:

- keep the one controller from self-destructing under Raspberry Pi load;
- keep speakers healthy so already allocated VIPs keep being announced;
- provide an independent fallback path that does not require MetalLB allocation.

The 2026-06-28 outage exposed a controller self-destruct loop: a one-second
liveness probe on `GET /metrics` could time out on a slow or CPU-throttled Pi,
and the Burstable controller pod was then killed and restarted. The fix in
`platform/metallb/helm-values.yaml` relaxes the controller liveness behavior and
puts the controller in Guaranteed QoS so kubelet CPU pressure is less likely to
make the health check kill an otherwise working controller.

If `.53` is already allocated, a controller restart should not be on the hot path
for every query. If the Service loses its assignment or is created while the
controller is crash-looping, allocation is blocked until the controller recovers.
In the 2026-06-28 recovery, restarting the controller caused the VIP to be
reassigned and DNS returned in roughly 20 seconds.

### Klipper fallback: node-IP DNS without MetalLB

A separate fallback Service in `apps/dnsdist/service-fallback.yml` exposes DNS
through k3s ServiceLB/klipper on a node IP. This path has no MetalLB controller,
no MetalLB IPAddressPool allocation, and no `.53` VIP dependency.

The intended router configuration is primary/secondary DNS:

```text
UDM-Pro DHCP primary DNS   -> 192.168.52.53       (MetalLB VIP)
UDM-Pro DHCP secondary DNS -> 192.168.52.110      (example node-IP fallback)
```

Use a real node IP from the `192.168.52.0/22` LAN for the secondary. This is a
standing cluster-local fallback, not a public resolver fallback, so clients keep
Pi-hole policy and split-horizon behavior when they fail over.

| Failure | `.53` MetalLB VIP primary | klipper node-IP secondary |
| --- | --- | --- |
| One DNS backend pod fails | Survives through dnsdist/Pi-hole endpoints | Survives through dnsdist/Pi-hole endpoints |
| VIP leader node fails | Survives after speaker failover | Survives if the chosen fallback node is up |
| MetalLB speaker on one node fails | Survives if another speaker announces | Survives; no MetalLB dependency |
| MetalLB controller restarts after VIP is allocated | Usually survives; speakers keep announcing | Survives; no MetalLB dependency |
| MetalLB controller down during VIP allocation | Fails until allocation returns | Survives; no allocation dependency |
| Total MetalLB outage | Fails | Survives if k3s ServiceLB, kube-proxy, and dnsdist are healthy |
| Chosen fallback node down | Survives if MetalLB path is healthy | Fails until node returns or router secondary is changed |
| Cluster-wide DNS workload down | Fails | Fails; both paths need dnsdist/Pi-hole or dnsdist backup resolvers |
| UDM-Pro DHCP disruption only | Existing clients may keep old DNS until lease behavior changes | Same; node static IP work is covered in [network-resiliency.md](runbooks/network-resiliency.md) |

## If `192.168.52.53` stops resolving

Work from the outside inward. The goal is to tell whether the VIP, the MetalLB
control plane, the speaker announcement, or the DNS backends are broken.

### 1. Confirm the client path

```sh
nslookup themartinez.cloud 192.168.52.53
dig @192.168.52.53 themartinez.cloud
dig @192.168.52.110 themartinez.cloud
```

Replace `192.168.52.110` with the configured klipper fallback node IP. If the
fallback answers but `.53` does not, focus on MetalLB allocation or announcement.
If both fail, focus on dnsdist, Pi-hole, kube-proxy, or node networking.

### 2. Check MetalLB controller health and restarts

```sh
kubectl -n metallb-system get deploy,ds,pods -o wide
kubectl -n metallb-system describe deploy metallb-controller
kubectl -n metallb-system logs deploy/metallb-controller --tail=100
```

Look for a controller with zero available replicas, repeated restarts, probe
failures, or allocation errors. During the 2026-06-28 incident, restoring the
controller allowed MetalLB to reassign `.53` in about 20 seconds.

### 3. Check VIP assignment

```sh
kubectl -n dnsdist get svc dnsdist -o wide
kubectl -n metallb-system get ipaddresspool,l2advertisement
```

The `dnsdist` Service should show `192.168.52.53` as its external IP. If it does
not, the controller allocation path is the likely blocker.

### 4. Check speaker announcement

```sh
kubectl -n metallb-system logs ds/metallb-speaker --tail=100
kubectl -n metallb-system get pods -o wide
```

Look for speaker crashes, memberlist errors, or announcement errors. A healthy
speaker set should keep announcing an already allocated VIP even if the
controller is temporarily unavailable.

### 5. Check dnsdist and Pi-hole backends

```sh
kubectl -n dnsdist get pods,svc,endpoints -o wide
kubectl -n dnsdist logs deploy/dnsdist --tail=100
kubectl -n pihole get pods,svc,endpoints -o wide
kubectl -n pihole logs statefulset/pihole --tail=100
```

There should be ready dnsdist pods on more than one node. Because the primary
Service uses `externalTrafficPolicy: Local`, the VIP should land on a node with a
ready local dnsdist pod. If dnsdist is reachable but queries fail or fall back to
public resolvers, verify that Pi-hole endpoints exist and that Pi-hole can reach
unbound/upstream resolvers.

### 6. Verify recovery

```sh
nslookup themartinez.cloud 192.168.52.53
nslookup bmtn.us 192.168.52.53
dig @192.168.52.110 themartinez.cloud
kubectl -n dnsdist get svc dnsdist -o wide
kubectl -n metallb-system get pods -o wide
```

Once `.53` resolves reliably, keep the UDM-Pro on the intended primary/secondary
resolver design: `.53` as primary and the klipper node-IP fallback as secondary.
Do not replace the standing fallback with a public resolver except as a temporary
break-glass step documented in [break-glass.md](runbooks/break-glass.md).

## Source files

- `apps/dnsdist/` defines the dnsdist Deployment, config, PDB, VIP Service, and
  klipper fallback Service.
- `apps/pihole/` defines the Pi-hole workload behind dnsdist.
- `platform/metallb/` defines MetalLB values, the `dns-vip` pool, and Layer-2
  advertisement.
- `components/cluster-config/` fans the DNS VIP value into consumers that opt in.

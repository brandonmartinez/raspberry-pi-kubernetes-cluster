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
  -> dnsdist independently health-checks 3 per-ordinal Pi-hole Services:
     pihole-0-dns-svc: 10.43.100.31 (pihole-0)
     pihole-1-dns-svc: 10.43.100.32 (pihole-1)
     pihole-2-dns-svc: 10.43.100.33 (pihole-2)
  -> selected Pi-hole pod -> unbound / upstream resolvers
```

`192.168.52.53` is the primary DNS address for the home LAN. The UDM-Pro hands
it out by DHCP, and clients send both UDP and TCP port 53 traffic there. MetalLB
announces that address on Layer 2 and sends traffic to the `dnsdist`
LoadBalancer Service.

`dnsdist` is the front door. It runs multiple replicas, uses
`externalTrafficPolicy: Local`, and is spread across nodes so MetalLB only
announces the VIP from a node with a ready local dnsdist endpoint. **dnsdist
directly references three static per-ordinal Pi-hole Services via IP literals**
and **independently health-checks each ordinal via `version.bind.` TXT CHAOS DNS
query**. This avoids coupling dnsdist's availability to a single shared Service
VIP. dnsdist routes queries to **any Pi-hole ordinal that is healthy** (≥1
healthy); if all three are down, dnsdist falls back to its last-ditch public
resolver pool. Shared VIP 10.43.100.30 (pihole-dns-svc) remains for backward
compatibility with other consumers but is **not on dnsdist's HA boundary
anymore**.

Pi-hole remains the policy layer behind dnsdist: ad blocking, local DNS behavior,
and the handoff to unbound/upstream resolvers. Pi-hole is no longer the public
LoadBalancer entrypoint for the LAN.

## High availability and failure modes

The DNS design now has four distinct layers. They fail differently, so diagnose
them separately.

### 2026-07-24: Why the shared Pi-hole Service failed

**Old design (deprecated):** dnsdist used a single shared Pi-hole Service VIP at
10.43.100.30. This prevented dnsdist from distinguishing one unhealthy ordinal
from the healthy replicas behind the same logical downstream. During the
2026-07-24 incident, dnsdist repeatedly marked that one downstream down and up
while `pihole-2` was unresponsive. Client-side UDP loss was consistent with UDP
service/conntrack state continuing to target the failed endpoint. The incident
demonstrated:

- **Amplified endpoint failure into VIP unavailability:** The shared Service VIP
  created a single point of load-balancer state that coupled all three Pi-hole
  pods into one logical failure domain. A single pod failure (caused by the Pi-hole
  database corruption or other endpoint issues) triggered conntrack flapping across
  all queries routed through that VIP.
- **Observed service flapping and packet drops:** When a bad endpoint sat behind
  the fan-in Service, dnsdist's one logical downstream flapped as well. During
  the incident, `.53` dropped all UDP traffic and some TCP traffic even though
  two Pi-hole pods remained healthy.
- **Claim "one Pi-hole failure is harmless":** This was **disproven**. A single
  pod failure cascaded into client-visible query timeouts.

**Root cause:** The shared Service VIP created a single point of load-balancer
state that coupled all three Pi-hole pods into one logical failure domain. A
per-ordinal architecture avoids this by having dnsdist reference each ordinal
independently.

### Per-ordinal Pi-hole Services (current)

**New design:** dnsdist directly references three static, independently managed
per-ordinal Services with fixed ClusterIPs:

- `pihole-0-dns-svc` (pihole-0): 10.43.100.31
- `pihole-1-dns-svc` (pihole-1): 10.43.100.32
- `pihole-2-dns-svc` (pihole-2): 10.43.100.33

Each ordinal Service is health-checked independently by dnsdist via `version.bind.`
TXT CHAOS DNS query to the per-ordinal Service. Kubernetes readiness, startup, and
liveness probes exercise dnsdist's local UDP request/response handling (readiness)
and local TCP listener (startup/liveness). Readiness accepts any valid DNS response
so a WAN or upstream outage cannot withdraw the entire VIP; per-ordinal dnsdist
health checks and Prometheus rules report backend failures separately. Queries
route to **any ordinal that reports healthy**. If one ordinal fails:

1. That ordinal's Service loses its endpoint.
2. dnsdist marks that ordinal's health check as down.
3. Queries route to the remaining healthy ordinals; any stale service state is
   isolated to the failed ordinal instead of poisoning the complete Pi-hole pool.
4. Existing queries on the healthy ordinals continue uninterrupted.
5. If all three ordinals are down, dnsdist falls back to public resolvers.

The shared fan-in Service at 10.43.100.30 (pihole-dns-svc) remains for
backward compatibility with other consumers (e.g., gravity-sync, nebulasync),
but **dnsdist no longer depends on it**.

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

| Failure | `.53` MetalLB VIP primary | klipper node-IP secondary | Per-ordinal Pi-hole (dnsdist behavior) |
| --- | --- | --- | --- |
| One Pi-hole ordinal fails (e.g., pihole-1 down) | Survives; dnsdist routes to healthy ordinals | Survives; dnsdist routes to healthy ordinals | ✓ Survives immediately; no conntrack flapping; remaining ordinals unaffected |
| One dnsdist pod fails | Survives if another dnsdist is healthy | Survives if another dnsdist is healthy | Surviving dnsdist pod routes normally |
| VIP leader node fails | Survives after speaker failover | Survives if the chosen fallback node is up | Surviving dnsdist pod(s) on other nodes handle queries |
| MetalLB speaker on one node fails | Survives if another speaker announces | Survives; no MetalLB dependency | Survives; dnsdist on other nodes are healthy |
| MetalLB controller restarts after VIP is allocated | Usually survives; speakers keep announcing | Survives; no MetalLB dependency | Survives; per-ordinal checks are independent of VIP state |
| MetalLB controller down during VIP allocation | Fails until allocation returns | Survives; no allocation dependency | Survives; per-ordinal checks work without the VIP |
| Total MetalLB outage | Fails | Survives if k3s ServiceLB, kube-proxy, and dnsdist are healthy | Survives; per-ordinal Services don't depend on MetalLB |
| Chosen fallback node down | Survives if MetalLB path is healthy | Fails until node returns or router secondary is changed | Survives; queries route to other dnsdist replicas |
| All 3 Pi-hole ordinals down | Public DNS survives through dnsdist's backup pool; Pi-hole policy/local zones are unavailable | Same | Falls back to public resolvers (last ditch) |
| Cluster-wide DNS workload down | Fails | Fails | Fails; all ordinals and fallback exhausted |
| UDM-Pro DHCP disruption only | Existing clients may keep old DNS until lease behavior changes | Same | Same; node static IP work is covered in [network-resiliency.md](runbooks/network-resiliency.md) |

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

### 5. Check dnsdist backend health (per-ordinal ordinals)

```sh
kubectl -n dnsdist get pods,svc -o wide
kubectl -n dnsdist logs deploy/dnsdist --tail=50 | grep -E "(pihole|health|server)"
```

dnsdist independently health-checks each Pi-hole ordinal. Look for:
- All three dnsdist pods `Ready 1/1`.
- Startup logs showing each ordinal server was added and marked `up`.
- Repeated `down`/`up` transitions or an ordinal remaining `down`.

### 6. Check per-ordinal Pi-hole Services and Pods

```sh
kubectl -n pihole get sts,svc,endpoints -o wide
kubectl -n pihole describe svc pihole-0-dns-svc pihole-1-dns-svc pihole-2-dns-svc
kubectl -n pihole get pods -o wide
```

Confirm:
- Three StatefulSet replicas (`pihole-0`, `pihole-1`, `pihole-2`) are `Running 1/1`.
- Three per-ordinal Services (`pihole-0-dns-svc`, `pihole-1-dns-svc`, `pihole-2-dns-svc`) each have one endpoint.
- Each Service's ClusterIP is assigned (`10.43.100.31`, `10.43.100.32`, `10.43.100.33`).
- Shared fan-in Service `pihole-dns-svc` at `10.43.100.30` also has endpoints (for compatibility consumers).

### 7. Verify each backend from a pod with `dig`

```sh
# The dnsdist image has no dig/nslookup; Pi-hole does.
kubectl -n pihole exec pihole-0 -- dig @10.43.100.31 themartinez.cloud A +short
kubectl -n pihole exec pihole-0 -- dig @10.43.100.32 themartinez.cloud A +short
kubectl -n pihole exec pihole-0 -- dig @10.43.100.33 themartinez.cloud A +short
kubectl -n pihole exec pihole-0 -- dig @10.43.100.31 themartinez.cloud A +tcp +short
```

Each ordinal's DNS Service should respond independently. If one fails, queries should route to the healthy ones.

### 8. Verify recovery

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


## Why per-ordinal Services and IP literals avoid CoreDNS dependency

**Motivation:** If dnsdist resolved per-ordinal Service names via CoreDNS (e.g.,
`pihole-0-dns-svc.pihole.svc.cluster.local`), dnsdist startup/re-resolution
would depend on the currently single-replica CoreDNS Deployment. A CoreDNS
outage could then block dnsdist from resolving healthy Pi-hole backends.

**Solution:** dnsdist uses **static IP literals** (`10.43.100.31`, `10.43.100.32`,
`10.43.100.33`) that are pre-configured and never re-resolve. These IPs are bound
to fixed per-ordinal Services that persist independently:

- Service IP allocation is purely kube-apiserver + etcd (not CoreDNS).
- Health checks are direct IP connections (TCP/UDP port 53), not DNS lookups.
- No name resolution overhead or failure path.

If CoreDNS or any cluster DNS goes down, LAN clients using `192.168.52.53` still
reach dnsdist, which still reaches Pi-hole via static IPs, so DNS continues to
work. The cluster remains resilient to its own DNS control plane.

## Source files

- `apps/dnsdist/` defines the dnsdist Deployment, config, PDB, VIP Service, and
  klipper fallback Service.
- `apps/pihole/` defines the Pi-hole workload behind dnsdist.
- `platform/metallb/` defines MetalLB values, the `dns-vip` pool, and Layer-2
  advertisement.
- `components/cluster-config/` fans the DNS VIP value into consumers that opt in.

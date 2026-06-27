# DNS architecture

This cluster intentionally teaches the full DNS path instead of hiding it behind
one appliance. The LAN resolver is a Kubernetes Service, but it is still operated
as production infrastructure: if DNS is down, almost everything else feels down.

## Request path

```text
LAN clients
  -> UDM-Pro DHCP advertises 192.168.52.53 as DNS
  -> MetalLB Layer-2 VIP 192.168.52.53 (dns-vip)
  -> dnsdist LoadBalancer Service in apps/dnsdist
  -> Pi-hole DNS Service
  -> unbound / upstream resolvers
```

`192.168.52.53` is the single DNS address for the home LAN. The UDM-Pro hands it
out by DHCP, and clients send both UDP and TCP port 53 traffic there. MetalLB
announces that address on Layer 2 and sends traffic to the `dnsdist` LoadBalancer
Service.

`dnsdist` is the front door. It runs multiple replicas, uses
`externalTrafficPolicy: Local`, and is spread across nodes so MetalLB only
announces the VIP from a node with a ready local dnsdist endpoint. dnsdist then
forwards normal traffic to the Pi-hole cluster Service. If every Pi-hole backend
is unhealthy, dnsdist has a last-ditch public resolver pool so the LAN can still
resolve names while Pi-hole is repaired; normal operation should be 100% Pi-hole.

Pi-hole remains the policy layer behind dnsdist: ad blocking, local DNS behavior,
and the handoff to unbound/upstream resolvers. Pi-hole is no longer the public
LoadBalancer entrypoint for the LAN.

## MetalLB dependency

The DNS VIP depends on MetalLB being healthy:

- the MetalLB controller allocates the requested VIP from the `dns-vip`
  `IPAddressPool`;
- the MetalLB speakers announce the VIP with Layer-2 ARP;
- the `dnsdist` Service explicitly requests `192.168.52.53` and
  `loadBalancerClass: metallb.io/layer2`.

This is a hard dependency. During the DNS outage, the important lesson was that a
healthy Pi-hole pod is not enough if MetalLB cannot assign or announce `.53`.
The mitigation is to keep MetalLB admitted and alive under node pressure:
`platform/metallb/helm-values.yaml` gives the controller and speaker
`system-cluster-critical` priority, and the speaker memory limit was raised after
an OOM-kill incident. Node-resilience work complements this by reducing the odds
that the VIP leader or all dnsdist endpoints disappear at the same time.

## Retired klipper fallback

The old node-IP klipper Services `pihole-dns-tcp` and `pihole-dns-udp` have been
retired. They were useful during migration, but they created two DNS paths with
different failure modes and made drift cleanup harder. The steady-state design is
now one path:

```text
192.168.52.53 -> dnsdist -> Pi-hole -> unbound/upstream
```

Do not add a permanent public secondary resolver in DHCP. Client resolver
failover is OS-dependent and timeout-based, and a public secondary silently
bypasses split-horizon names and Pi-hole filtering whenever a client races it.
Use the temporary DHCP fallback in [runbooks/break-glass.md](runbooks/break-glass.md)
only during a DNS incident.

## Single point of failure analysis

The design has one LAN-facing VIP by choice. A second DNS VIP inside the same
cluster would share the same dnsdist, Pi-hole, unbound, kube-proxy, and MetalLB
failure domains while making client behavior less predictable. The useful HA
boundary is not multiple client-facing addresses; it is making the one address
move quickly to a healthy node.

Covered failures:

- one node dies: MetalLB can move `.53` to another node with a ready dnsdist pod;
- one dnsdist pod dies: endpoints and Local traffic policy keep the VIP on nodes
  with ready pods;
- one Pi-hole pod dies: kube-proxy sends dnsdist to remaining Pi-hole endpoints;
- all Pi-hole pods die: dnsdist can temporarily use its backup resolver pool.

Still serious failures:

- MetalLB controller or speakers unhealthy;
- no ready dnsdist endpoints;
- kube-proxy or CNI failure on the VIP leader;
- Pi-hole and backup resolver paths both unavailable;
- router DHCP still pointing clients somewhere stale.

## If `192.168.52.53` stops resolving

Work from the outside inward.

### 1. Confirm the client path

```sh
nslookup themartinez.cloud 192.168.52.53
dig @192.168.52.53 themartinez.cloud
```

If clients need immediate internet DNS while the cluster is repaired, use the
break-glass DHCP fallback in [runbooks/break-glass.md](runbooks/break-glass.md).
Revert DHCP to `192.168.52.53` after recovery.

### 2. Check VIP assignment and MetalLB

```sh
kubectl -n dnsdist get svc dnsdist -o wide
kubectl -n metallb-system get pods -o wide
kubectl -n metallb-system logs deploy/metallb-controller --tail=100
kubectl -n metallb-system logs ds/metallb-speaker --tail=100
kubectl -n metallb-system get ipaddresspool,l2advertisement
```

Look for `.53` on the Service, ready controller and speaker pods, speaker
restarts, and allocation or announcement errors. The real recovery path included
restoring MetalLB health so the speakers could announce the VIP again.

### 3. Check dnsdist

```sh
kubectl -n dnsdist get pods -o wide
kubectl -n dnsdist get endpoints dnsdist -o wide
kubectl -n dnsdist logs deploy/dnsdist --tail=100
```

There should be ready dnsdist pods on more than one node. Because the Service
uses `externalTrafficPolicy: Local`, a node without a ready local dnsdist pod
should not be the place MetalLB sends the VIP.

### 4. Check Pi-hole behind dnsdist

```sh
kubectl -n pihole get pods,svc,endpoints -o wide
kubectl -n pihole logs statefulset/pihole --tail=100
```

If dnsdist is reachable but queries fail or fall back to public resolvers, verify
that Pi-hole endpoints exist and that Pi-hole can reach unbound/upstream
resolvers.

### 5. Verify recovery

```sh
nslookup themartinez.cloud 192.168.52.53
nslookup bmtn.us 192.168.52.53
kubectl -n dnsdist get svc dnsdist -o wide
kubectl -n metallb-system get pods -o wide
```

Once `.53` resolves reliably, remove any temporary DHCP fallback and confirm a
client receives `192.168.52.53` again on lease renewal.

## Source files

- `apps/dnsdist/` defines the dnsdist Deployment, config, PDB, and VIP Service.
- `apps/pihole/` defines the Pi-hole workload behind dnsdist.
- `platform/metallb/` defines MetalLB values, the `dns-vip` pool, and Layer-2
  advertisement.
- `components/cluster-config/` fans the DNS VIP value into consumers that opt in.

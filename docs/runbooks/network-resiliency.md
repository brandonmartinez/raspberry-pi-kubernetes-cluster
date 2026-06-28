# Runbook: network resiliency

Use this when a node goes `NotReady`, SSH stops responding, or DNS/LAN behavior
suggests a Raspberry Pi lost its network configuration. Treat the cluster as
production: diagnose first, change one node at a time, and keep a PoE or console
recovery path ready.

## 2026-06-28 failure mode

Two worker nodes, `rpi003` and `rpi004`, went `NotReady` about eight hours apart
after `dhcpcd` lost its DHCP lease during a UDM-Pro DHCP disruption. The Pis were
not thermally or electrically unhealthy. The network stack removed the address
and default route from `eth0`, leaving the node with messages like `network is
unreachable` and no path back to the gateway or API server.

A manual PoE reboot fixed each node because boot forced a fresh network bring-up:
`eth0` received its LAN address again, the default route returned, kubelet could
reach the control plane, and the node became schedulable.

## Defense layers

Network resiliency is intentionally layered. No single control is trusted as the
only way a node keeps its address.

1. **UDM-Pro DHCP reservations.** Existing reservations keep node addresses
   stable on the `192.168.52.0/22` LAN.
2. **Static node IPs on the Pis.** The Ansible base role configures the expected
   address on each Pi as a belt-and-suspenders layer, so a router DHCP incident
   does not have to remove the node address.
3. **`dhcpcd` persistent mode.** `dhcpcd` is configured to keep the current
   address and route when a lease expires instead of tearing down networking and
   isolating the node.
4. **Network self-healing watchdog.** A systemd-managed watchdog checks sustained
   gateway reachability and can rebind networking or reboot when the node cannot
   recover on its own.
5. **Optional hardware watchdog.** The base role can enable the Pi hardware
   watchdog as a final recovery layer for a wedged OS.

These changes live in the Ansible base role and are gated. Use them to converge
live nodes carefully; do not hand-edit the live cluster from this runbook.

## Critical DNS rule for nodes

Node-level DNS must not point at the cluster DNS VIP `192.168.52.53`.

That would create a circular dependency: a node would need cluster DNS to boot,
join k3s, pull images, run CNI, and host the same DNS stack it depends on. Nodes
should use the UDM-Pro and/or public resolvers for their own OS DNS so they can
boot and recover when Kubernetes DNS, MetalLB, dnsdist, or Pi-hole is down.

LAN clients can use the cluster DNS design from
[dns-architecture.md](../dns-architecture.md): `192.168.52.53` primary plus the
klipper node-IP fallback secondary. Cluster nodes themselves should not.

## Safe apply procedure

Apply node-network changes one node at a time.

1. Pick one node and confirm the rest of the cluster is healthy enough to absorb
   a temporary loss:
   ```sh
   kubectl get nodes -o wide
   kubectl -n metallb-system get pods -o wide
   kubectl -n dnsdist get pods -o wide
   ```
2. Run the gated Ansible adoption path in check mode first:
   ```sh
   ansible-playbook -i ansible/inventory/hosts.yml ansible/adopt.yml \
    --limit <node> \
    --check --diff
   ```
3. Review the diff. Confirm it only changes the intended node-network, watchdog,
   or base-role configuration for the selected node.
4. Apply to the same single node when ready:
   ```sh
   ansible-playbook -i ansible/inventory/hosts.yml ansible/adopt.yml \
    --limit <node>
   ```
5. Expect that restarting or rebinding `dhcpcd` can drop the SSH session. Have
   console access, the UDM-Pro port view, and PoE reboot control ready before the
   apply.
6. Wait for the node to return healthy before touching another node:
   ```sh
   kubectl get node <node> -o wide
   kubectl describe node <node>
   ```
7. Repeat for the next node only after workload and DNS health look normal.

Do not combine these changes with heavy rollouts, MetalLB changes, or DNS
application changes. If DNS is already degraded, stabilize DNS first.

## Diagnosis cheatsheet

### DHCP lease loss or route teardown

Common signs:

- `kubectl get nodes -o wide` shows the node `NotReady` and the old internal IP
  may stop responding.
- SSH to the node fails, but the UDM-Pro still shows power/link on the switch
  port.
- Node journal contains `network is unreachable`, DHCP lease expiry, carrier,
  route removal, or `dhcpcd` rebind messages.
- On console, `ip addr show eth0` has no expected `192.168.52.x` address.
- On console, `ip route` has no default route through `192.168.52.1`.
- `ping 192.168.52.1` fails from the node.

Useful commands from console or an existing SSH session:

```sh
journalctl -u dhcpcd --since "2 hours ago"
journalctl -u kubelet --since "2 hours ago"
ip addr show eth0
ip route
ping -c 3 192.168.52.1
```

If this matches, the immediate recovery is to restore node networking. A PoE
reboot is acceptable when the node is otherwise unreachable and you have already
confirmed this is a network-isolated worker, not an in-progress storage or
control-plane operation.

### Other common `NotReady` causes

If `eth0` still has the expected address and the default route is present, look
elsewhere before rebooting:

- kubelet or container runtime unhealthy:
  ```sh
  systemctl status k3s-agent
  journalctl -u k3s-agent --since "30 minutes ago"
  ```
- disk, memory, PID, or image pressure:
  ```sh
  kubectl describe node <node>
  df -h
  free -m
  ```
- CNI or kube-proxy issues:
  ```sh
  kubectl -n kube-system get pods -o wide
  kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=100
  ```
- storage attachment or Longhorn pressure:
  ```sh
  kubectl -n longhorn-system get pods -o wide
  kubectl get volumes.longhorn.io -A
  ```

Only classify the incident as DHCP lease loss when the address/default route
symptoms are present. Otherwise follow the runbook for the failing subsystem.

## After recovery

- Confirm the node is `Ready` and has the expected internal IP.
- Confirm DNS through both resolver paths:
  ```sh
  dig @192.168.52.53 example.com A +short
  dig @192.168.52.110 example.com A +short
  ```
  Replace `192.168.52.110` with the configured klipper fallback node IP.
- Confirm MetalLB speakers and dnsdist pods are healthy.
- Record the timestamp, affected node, suspected DHCP event, recovery action, and
  whether watchdog automation intervened.

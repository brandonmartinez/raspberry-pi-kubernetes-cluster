# Runbook: heavy rollouts

Use this for storage-heavy or CPU-heavy changes on the Raspberry Pi cluster:
large image pulls, database cold starts, InnoDB initialization, Longhorn rebuilds,
and any rollout that can saturate a 4GB worker. The uptime-MariaDB rollout
overloaded a node hard enough that DNS dropped when MetalLB speaker health was
impacted; treat that as the failure mode to avoid.

## Before the rollout

- Schedule a maintenance window for anything that can cold-start databases or
  pull multi-GB images.
- Keep Pi-hole/dnsdist/MetalLB stable: do not combine DNS changes with heavy
  application rollouts.
- Confirm the target app has resource requests/limits, probes, and a PDB where
  possible.
- Check nodes before starting:
  ```sh
  kubectl top nodes
  kubectl -n metallb-system get pods -o wide
  kubectl get nodes
  ```
- Watch the rollout from another terminal:
  ```sh
  kubectl get nodes -w
  kubectl -n metallb-system get pods -w
  kubectl -n <namespace> get pods -o wide -w
  ```

## Pre-pull large images

Pre-pull large images one node at a time so kubelet/containerd and the USB SSDs
do not all spike during the Deployment rollout.

```sh
# Pick one node, then use a short-lived pod pinned to that node.
kubectl run prepull-<node> \
  --image=<image>:<tag> \
  --restart=Never \
  --overrides='{"spec":{"nodeName":"<node>","tolerations":[{"operator":"Exists"}],"containers":[{"name":"prepull","image":"<image>:<tag>","command":["/bin/sh","-c","sleep 5"]}]}}'

kubectl wait --for=condition=Ready pod/prepull-<node> --timeout=5m || true
kubectl delete pod/prepull-<node>
```

Repeat for the next worker only after node load and MetalLB speakers look normal.

## Roll out slowly

1. Sync or apply one workload at a time.
2. Avoid concurrent cold starts on the same worker. If multiple Pods schedule on
   one node, pause and let the first become Ready before continuing.
3. For StatefulSets/databases, wait for storage initialization to finish before
   allowing the next Pod to start.
4. Watch MetalLB while the heavy workload starts:
   ```sh
   kubectl -n metallb-system get deploy,ds,pods -o wide
   kubectl -n metallb-system logs deploy/metallb-controller --tail=50
   ```
5. Check DNS externally during the rollout:
   ```sh
   dig @192.168.52.53 example.com A +short
   ```

## Stop conditions

Stop the rollout and let the cluster recover if any of these happen:

- A node reports MemoryPressure, DiskPressure, PIDPressure, or NotReady.
- MetalLB controller has zero available replicas.
- Any MetalLB speaker is unavailable or repeatedly restarting.
- DNS queries through `192.168.52.53` fail.
- Load average stays above CPU count for more than a few minutes.

If DNS is impacted, use [break-glass.md](break-glass.md) for the router/DHCP
fallback and keep changes minimal until MetalLB and the DNS path are stable.

## After the rollout

- Confirm all Pods are Ready and spread across nodes where expected.
- Confirm MetalLB controller and speakers are healthy.
- Confirm DNS through `192.168.52.53` and ingress through `192.168.52.80`.
- Record any image, database, or storage step that caused pressure so the next
  rollout can pre-pull or schedule around it.

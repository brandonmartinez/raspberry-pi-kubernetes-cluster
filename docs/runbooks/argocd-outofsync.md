# Runbook: ArgoCD OutOfSync troubleshooting

Use this when an Application stays `OutOfSync` after the desired Git change has
landed. Start by identifying the drift class before changing live resources.

## Decision tree

- **Sync succeeds, then the app immediately drifts again** -> suspect a
  controller-enforced field. Check `managedFields` to see which controller owns
  the field.
- **`kubectl diff` is clean, but ArgoCD still reports `OutOfSync`** -> suspect
  immutable-field drift. Confirm the live immutable field differs from Git.
- **A resource exists live but is not rendered from Git** -> suspect an orphan
  left behind while prune is off. Confirm it is absent from `kustomize build`,
  then delete it by hand.

## Orphan resources under prune-off

### Symptom

The Application remains `OutOfSync` forever, and another sync does not remove the
extra object. ArgoCD shows a live resource that no longer exists in Git.

Examples from this cycle:

- uptime's old sqlite backup CronJob after the workload moved away from that
  backup path.
- Pi-hole's legacy klipper `pihole-dns-tcp` and `pihole-dns-udp` LoadBalancer
  Services after DNS moved to the dnsdist MetalLB VIP.

### Diagnose

```sh
kubectl -n argocd get app <app> -o jsonpath='{.status.sync.status}{"\n"}'
kubectl -n argocd get app <app> -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.status}{"\n"}{end}'

# Render Git and confirm the resource name is not present.
kustomize build apps/<app> | grep '<resource-name>' || true

# Confirm the object still exists live.
kubectl -n <namespace> get <kind> <resource-name>
```

Useful concrete checks:

```sh
kustomize build apps/uptime | grep sqlite-backup || true
kubectl -n uptime get cronjob

kustomize build apps/pihole | grep -E 'pihole-dns-(tcp|udp)' || true
kubectl -n pihole get svc pihole-dns-tcp pihole-dns-udp
```

### Root cause

Prune is deliberately off for most Applications. That is safe for production,
but it also means removing an object from Git does not remove the live object.
Manual sync only applies rendered objects; it does not delete extras.

### Fix

1. Confirm the object is no longer rendered by `kustomize build`.
2. Confirm the object is not required by any current client or migration path.
3. Delete the live orphan explicitly:

```sh
kubectl -n <namespace> delete <kind> <resource-name>
```

Then re-check the Application resource list. Do not enable prune just to clean up
one known orphan on a stateful or protected app.

## Immutable-field drift

### Symptom

ArgoCD stays `OutOfSync`, but a normal apply or diff may not show a pending
change. Sync cannot converge because Kubernetes will never mutate the field in
place.

Example from this cycle: moving chrony's LoadBalancer from klipper to MetalLB at
`192.168.52.54` required adding `spec.loadBalancerClass: metallb.io/layer2`.
`Service.spec.loadBalancerClass` is immutable after the Service is created.

### Diagnose

```sh
# Render the desired Service from Git.
kustomize build apps/chrony | grep -A40 '^kind: Service'

# Check the live immutable field.
kubectl -n chrony get svc chrony-ntp-udp -o jsonpath='{.spec.loadBalancerClass}{"\n"}'
kubectl -n chrony get svc chrony-ntp-udp -o jsonpath='{.spec.loadBalancerIP}{"\n"}'
kubectl -n chrony get svc chrony-ntp-udp -o jsonpath='{.metadata.annotations.metallb\.universe\.tf/loadBalancerIPs}{"\n"}'

# Server-side diff can appear clean even though ArgoCD still cannot make the
# immutable field match on the existing object.
kustomize build apps/chrony | kubectl diff --server-side -f -
```

For a generic Service, inspect the immutable field directly:

```sh
kubectl -n <namespace> get svc <service> -o jsonpath='{.spec.loadBalancerClass}{"\n"}'
```

### Root cause

Kubernetes rejects updates to immutable fields. ArgoCD can keep retrying, but the
existing object cannot be transformed from the old class to the new class. The
live object must be replaced.

### Fix

Plan a brief interruption for the Service address, then delete and recreate the
resource from Git:

```sh
kubectl -n <namespace> delete svc <service>
kustomize build apps/<app> | kubectl apply --server-side -f -
```

After recreation, verify the immutable field and the LoadBalancer address:

```sh
kubectl -n <namespace> get svc <service> -o wide
kubectl -n <namespace> get svc <service> -o jsonpath='{.spec.loadBalancerClass}{"\n"}'
```

Do not delete StatefulSets, PVCs, or selectors to silence a diff. This pattern is
for resources whose immutable field is intentionally changing and whose
interruption has been accepted.

## Controller-enforced fields

### Symptom

ArgoCD syncs successfully, then the app immediately returns to `OutOfSync`. The
same field keeps changing back after each sync.

Example from this cycle: Longhorn forces `retain: 0` on `filesystem-trim`
RecurringJobs. Git previously asked for a different value, so ArgoCD and the
Longhorn controller fought over the same field.

### Diagnose

```sh
# Compare desired and live values.
kustomize build platform/longhorn | grep -A30 'filesystem-trim'
kubectl -n longhorn-system get recurringjob filesystem-trim-weekly -o yaml

# Identify which manager last wrote the field.
kubectl -n longhorn-system get recurringjob filesystem-trim-weekly -o jsonpath='{range .metadata.managedFields[*]}{.manager}{"\t"}{.operation}{"\t"}{.time}{"\n"}{end}'

# If needed, inspect managedFields with jq to find the manager that owns spec fields.
kubectl -n longhorn-system get recurringjob filesystem-trim-weekly -o json \
  | jq '.metadata.managedFields[] | {manager, operation, fieldsV1}'
```

If the live value changes back shortly after a sync and the controller appears in
`managedFields`, treat the controller as the source of truth unless the
controller documentation says otherwise.

### Root cause

Some controllers normalize or enforce parts of their custom resources. ArgoCD
can apply Git, but the controller reconciles the field back to the value it
requires.

### Fix

Prefer making Git match the controller-enforced value:

```yaml
spec:
  task: filesystem-trim
  retain: 0
```

Use `ignoreDifferences` only when the controller-owned field is noisy and not
meaningful to GitOps intent. Do not hide fields that represent real desired
state without documenting why the controller must own them.

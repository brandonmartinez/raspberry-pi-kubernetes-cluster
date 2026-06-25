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

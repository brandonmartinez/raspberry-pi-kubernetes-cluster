# ArgoCD (self-management — opt-in, do LAST)

ArgoCD is installed **imperatively** by `bootstrap/00-argocd.sh` (pinned upstream
install manifest, `ARGOCD_VERSION`, default `v3.1.7`). That script remains the
source of truth for installing/upgrading ArgoCD itself.

Letting ArgoCD manage itself ("self-management") is **optional** and should only
be enabled once the rest of the platform + apps are healthy under GitOps. It is
intentionally **not** wired into `clusters/rpi/root.yml`, so it is never synced
automatically.

## Tradeoffs

- Pro: ArgoCD upgrades become a Git change like everything else.
- Con: a bad sync can take down the very controller doing the syncing. Recovery
  is via `bootstrap/00-argocd.sh` (re-apply the pinned manifest) — keep it.

## How to enable (manual, last step)

1. Confirm the running version: `kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}'`.
2. In `clusters/rpi/argocd-selfmanage.yml`, set `targetRevision` to the argo-cd
   **Helm chart** version whose `appVersion` matches the installed ArgoCD
   (replace `REPLACE-WITH-LIVE`). Adopting via Helm must match the live version
   or Helm will try to mutate live resources.
3. Review `helm-values.yaml` (keep it minimal; it must not fight the imperative
   install).
4. Apply it by hand (not through root): `kubectl apply -f clusters/rpi/argocd-selfmanage.yml`.
5. Sync manually in the UI and watch closely. Never enable `prune`/`selfHeal`
   on this Application without a tested `bootstrap/00-argocd.sh` recovery path.

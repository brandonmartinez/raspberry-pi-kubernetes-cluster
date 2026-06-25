# ArgoCD (self-management — opt-in, do LAST)

ArgoCD is installed **imperatively** by `bootstrap/00-argocd.sh` (pinned upstream
install manifest, `ARGOCD_VERSION`, default `v3.1.7`). That script remains the
source of truth for installing/upgrading ArgoCD itself.

## Web UI

`bootstrap/00-argocd.sh` also exposes the ArgoCD web UI at
`https://gitops.<NETWORK_HOSTNAME_SUFFIX>` (e.g. `gitops.themartinez.cloud`):

- `ingress.yml` (applied via `kubectl apply -k platform/argocd`) follows the
  portainer/pihole convention — ArgoCD has its own `admin` login, so the ingress
  only enforces HTTPS (`security-redirect-https`), no basic-auth. The host suffix
  is resolved by the `cluster-config` component, and TLS is issued by cert-manager
  (`letsencrypt-prod`).
- `argocd-server` is run with `--insecure` (set via `argocd-cmd-params-cm`) so
  Traefik terminates TLS and talks plain HTTP to the service. The bootstrap
  re-applies this each run because re-applying the upstream manifest resets it.
- Admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
- Fallback if the ingress is down: `kubectl -n argocd port-forward svc/argocd-server 8080:443`.

## Self-management (opt-in, do LAST)

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

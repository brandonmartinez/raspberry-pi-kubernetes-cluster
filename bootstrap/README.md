# Bootstrap

Run these one-time, push-based scripts in order from the repository root:

1. `bootstrap/00-argocd.sh`
2. `bootstrap/10-secret-zero.sh`
3. `bootstrap/20-eso.sh`

They are additive and idempotent, but they target a live cluster. The authoritative sequence and adoption gates live in `docs/runbooks/bootstrap.md`.

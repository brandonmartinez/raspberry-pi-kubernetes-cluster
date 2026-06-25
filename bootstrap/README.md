# Bootstrap

Run this one-time, push-based script from the repository root to stand up the
GitOps control plane on a live cluster:

1. `bootstrap/00-argocd.sh` — imperative ArgoCD install (not self-managed yet).

It is additive and idempotent, but it targets a live cluster. The authoritative
sequence and adoption gates live in `docs/runbooks/bootstrap.md`.

## Secrets

Secrets are **not** bootstrapped here and are **not** managed by ArgoCD. They are
pushed from 1Password by `scripts/sync-secrets.sh` once the target namespaces
exist. There is no secret zero and no External Secrets Operator. See
[`../docs/secrets.md`](../docs/secrets.md).

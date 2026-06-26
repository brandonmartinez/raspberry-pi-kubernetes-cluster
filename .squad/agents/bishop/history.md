# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Security and privacy matter: it's exposed to the world.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Secrets are referenced, never committed. Values live in 1Password (a Family account — no External Secrets Operator). `secrets/templates/*.yaml` hold `op://` references; `scripts/sync-secrets.sh` resolves them with `op inject` and `kubectl apply` upserts them — a workstation push, never a cluster pull. TLS is cert-manager + `letsencrypt-prod`. `scripts/validate.sh` runs a secret scan and a prune/selfHeal guard (protecting CRDs, Longhorn, PostgreSQL, Pi-hole). Never commit a real value; only `op://` refs / `${VAR}` placeholders.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Full sensitive-information sweep. Working tree clean; all `secrets/templates/*.yaml` use `op://` references (sound). **Critical findings:** Two real credential values were found in git history (already cleared from the working tree). Specific identifiers (variable names + commit SHAs) are kept out of tracked files and held only in untracked review notes; both must be rotated immediately (P1, issue #23); git-history scrub deferred to Brandon (P1, requires force-push). **Scanner bug:** validate.sh produces 13 false positives from `.copilot/` and `.squad/templates/` paths; fix: add to path-skip list (P2, issue #32).

Output: `files/review/bishop-security.md`. Security decisions + rotation actions merged into `decisions.md`. GitHub milestone #1 now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Credentials rotation required before next production push.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** Security findings documented. Credentials rotation P1 for next session. validator.sh false-positive fix (issue #32) completed; `.copilot/` and `.squad/` added to path-skip.

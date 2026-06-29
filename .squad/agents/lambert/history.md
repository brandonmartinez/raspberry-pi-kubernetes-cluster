# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Open source so others can learn from it — documentation is a first-class deliverable.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor (scripts → Ansible for provisioning, scripted pipeline → ArgoCD GitOps). Docs must catch up and stay current. I own `docs/` (architecture, gitops, secrets, provisioning, variable-inventory, runbooks/) and `README.md`. Markdown must pass the secret scanner: use `` `key` → `value` `` form, never `key: value` for password/token/secret-like keys. The old `k8s/src` + `envsubst` + `deploy.sh` pipeline is gone — never reference `${DOLLAR}`/`envsubst`/`DEPLOY_*` in docs.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Assembled committed review documents from ripley, parker, dallas, bishop + coordinator. Created `docs/reviews/2026-06-26-repo-and-apps-review.md` (consolidated findings + 45 follow-ups, P1: 10, P2: 21, P3: 14) and `docs/hardware-inventory.md` (learner-friendly reference). Applied security redaction: no credential names, specific env vars from historical leaks, commit SHAs, or public IPs; RFC1918 LAN IPs retained as appropriate for public homelab repo. Rai privacy audit: 🟢 GREEN.

Output: Two committed docs + consolidated follow-up list. Review completion merged into `decisions.md`. GitHub milestone #1 now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Docs delivery complete; ready for next session sprint on platform/app hardening.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** Documentation complete: `docs/reviews/` + `docs/hardware-inventory.md` shipped (security-redacted, privacy audit: GREEN). .env.sample rewrite coordinated (issue #47); bootstrap.md ServerSideApply final step documented (issue #47). Review findings consolidated; 45 follow-ups tracked in decisions.md. Ready for next session hardening sprint.


---

### 2026-06-29T10:28:25Z — Issue Closure Verification Session (Cross-Agent Coordination)

**Session:** Verified closure of triage-flagged issues  
**Role:** Documentation verification

- Re-verified & closed #69 with concrete evidence (ArgoCD out-of-sync + disaster-recovery runbooks, both substantive)
- Read-only verification only (gh-issue-API); no working-tree mutations
- Coordination: 5-agent parallel triage
2026-06-29T11:05:06-04:00 checked gitops.md — no explicit app enumeration, no change needed for #46

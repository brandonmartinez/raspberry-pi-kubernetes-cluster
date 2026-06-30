---
updated_at: 2026-06-30T12:40:53-04:00
focus_area: Maintain & evolve the homelab cluster (GitOps + Ansible) with detailed docs and strict secret hygiene
active_issues:
  - ✅ "#91 nebulasync Deployment→CronJob — DEPLOYED & VERIFIED clean (no 429); ready for close"
  - ✅ "#93 Pi-hole session-TTL 86400→300s — DEPLOYED + VERIFIED 2026-06-30 (all 3 pihole at session_timeout=300, no 429); PR #94 open, pending merge to main"
---

# What We're Focused On

Post-refactor maintenance: keep shipping ArgoCD GitOps and Ansible provisioning changes, document in detail for open-source learners, and keep all secrets referenced (1Password) — never committed. Updated by coordinator at session start.

## Recently shipped (2026-06-30)

- ✅ **#91 nebulasync Deployment→CronJob** — deployed to the live cluster (kustomize|apply break-glass; ArgoCD CLI unavailable) and verified: manual + scheduled `*/10` runs both Completed cleanly, no 429, Pi-hole 3/3 healthy, DNS unaffected. CronJob is now the sole nebulasync workload; both old Deployments (ns `nebulasync` + 470-day orphan in ns `pihole`) deleted. Acceptance met. Ready for close.
- ✅ **#93 Pi-hole session-TTL 86400→300s (durable follow-up to #91)** — reduced `FTLCONF_webserver_session_timeout` in `apps/pihole/.env` via gated resume + one-pod-at-a-time roll. Backup verified (executionCount=271), health verified (3/3 Ready), partition=0 roll completed cleanly (~135s, no PDB violations). nebulasync verify Job: Completed 1/1, no 429. All 3 pihole replicas now at TTL=300. PR #94 open on branch `squad/93-pihole-session-ttl-300`, pending merge to main.

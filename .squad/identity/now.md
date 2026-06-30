---
updated_at: 2026-06-30T10:16:53-04:00
focus_area: Maintain & evolve the homelab cluster (GitOps + Ansible) with detailed docs and strict secret hygiene
active_issues:
  - "#91 nebulasync Deployment→CronJob — deployed & verified clean (no 429); pending close confirmation"
  - "#93 Pi-hole session-TTL 86400→300s — GATED, awaiting Brandon's explicit approval + one-pod-at-a-time roll"
---

# What We're Focused On

Post-refactor maintenance: keep shipping ArgoCD GitOps and Ansible provisioning changes, document in detail for open-source learners, and keep all secrets referenced (1Password) — never committed. Updated by coordinator at session start.

## Recently shipped (2026-06-30)

- **#91 nebulasync Deployment→CronJob** — deployed to the live cluster (kustomize|apply break-glass; ArgoCD CLI unavailable) and verified: manual + scheduled `*/10` runs both Completed cleanly, no 429, Pi-hole 3/3 healthy, DNS unaffected. CronJob is now the sole nebulasync workload; both old Deployments (ns `nebulasync` + 470-day orphan in ns `pihole`) deleted. Acceptance met → recommended close.
- **#93 (durable follow-up)** — reduce `FTLCONF_webserver_session_timeout` 86400→300s in `apps/pihole/.env` to bound the upstream session-leak vector (lovelaze/nebula-sync#226, still present in pinned v0.11.2). GATED: needs Brandon's explicit go/no-go, backup-verify, DNS health before/after, and a one-pod-at-a-time StatefulSet roll (Ripley coordinates the pihole control-plane sync). **Do not touch Pi-hole without approval.**

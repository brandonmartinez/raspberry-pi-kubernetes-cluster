# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. I own `apps/<app>/` Kustomize bases and `platform/<stack>/` Helm values. Every workload is production: probes, resource limits, PDBs, topology spread, and HPAs where load varies. Model new apps on `apps/shlink/`. The apps ApplicationSet auto-discovers app folders — no per-app Application file.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Deep Longhorn, MetalLB, Pi-hole DNS stack review. Longhorn config is Pi-tuned; **gap:** no recurring backup/trim jobs (RPO = "never") — need daily-backup (02:00, 7-day retention) + weekly-trim (Sun 03:00). MetalLB layer2 + klipper coexistence correct; legacy pihole klipper LB services should be removed post-UDM-Pro DHCP confirmation. **Critical:** pin pihole and unbound-rpi to semver tags (v5/v6 incompatibility is silent failure); add Orbital Sync CronJob for pihole gravity sync; add TLS to pihole admin ingresses.

Output: `files/review/dallas-services.md` (P1: 4, P2: 7, P3: 4). All findings merged into `decisions.md`. GitHub milestone #1 now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Coordination point with Parker (storage) on Longhorn volume health gating for ansible adoption.


## Session: Existing-Issue Triage Follow-On (2026-06-26)

Existing-issue triage completed and results merged into decisions.md. Coordinator (previous phase) closed #3, #10, #19. Your assigned backlog queue: 5 issues now enriched and moved to Feature Backlog milestone #2:
- **#11** pihole-exporter / Prometheus metrics (P3)
- **#13** Unpoller / UDM-Pro metrics (P3)
- **#15** UniFi API Browser (P3)
- **#18** Diun image update notifications (P3)

Coordination point: also owns `.env.sample` rewrite decision (decision #4, P1 — coordinate with Lambert). No sprint contention on Feature Backlog.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** DNS/storage/networking review complete. Longhorn: backup/trim jobs gap identified (daily-backup + weekly-trim needed); default config (replicas=3, Retain) correct. Pi-hole: critical findings: pin versions (pihole v5/v6 incompatibility), add Orbital Sync CronJob, add TLS to admin ingresses; dnsdist PDB minAvailable raised to 2 (issues #26, #33–#36, #39). Feature Backlog: 5 issues promoted (#11, #13, #15, #18 + existing). .env.sample rewrite coordination point with Lambert. Ready for next platform hardening sprint.

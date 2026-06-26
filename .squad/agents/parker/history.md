# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: OS + package management moved from custom scripts to Ansible. I own `ansible/` — `provision.yml` (fresh nodes), `adopt.yml` (read-mostly convergence for live nodes, gated by `_apply`/`allow_disruptive`), and roles `base`, `storage`, `k3s_server`, `k3s_agent`, `node_docker`. Lead with `ansible-playbook adopt.yml --check --diff --limit <host>`. Never auto-reboot or touch `/boot/cmdline.txt`, DNS, fstab, or USB mounts on a live node without explicit approval.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Hardware inventory extraction + ansible/infra review. Inventory ~70% from repo; gaps require Brandon (RAM, USB drive model/capacity, mount device, k3s/OS versions). Identified critical gap: live cluster Longhorn uses `/media/data_ext/longhorn` but ansible storage role still has `/media/data`. Documented as hard constraint: do NOT run `adopt.yml --allow_disruptive` for storage role until mount path is aligned and verified.

Output: `files/review/parker-hardware-infra.md`. Storage role decision merged into `decisions.md`. GitHub milestone #1 now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Coordination point with Dallas (Longhorn) and Lambert (docs) on infra alignment before adopt.yml promotion.


## Session: Existing-Issue Triage Follow-On (2026-06-26)

Existing-issue triage completed and results merged into decisions.md. Coordinator (previous phase) closed #3, #10, #19. Your assigned backlog queue: 2 issues now enriched and moved to Feature Backlog milestone #2:
- **#16** Plex Media Server (P3)
- **#17** Jamulus Server (P3)

Coordination point: storage role path alignment (decision #3, P1) is a hard gate for `adopt.yml` promotion — validate with Brandon + Dallas before proceeding. Feature Backlog issues are post-hardening scope.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** Hardware inventory extraction complete (rpi001–rpi004 live specs captured). **Critical findings:** rpi003 thermal throttling (78.4 °C, active events) — requires heatsink/fan; rpi001 USB mount undocumented in Ansible. Storage role path-mismatch constraint documented (hard gate: must align `/media/data_ext` + validate before `adopt.yml --allow_disruptive`). Ansible roles OS-conditional cgroup path (Bullseye/Bookworm, issues #50, #51) deployed. Ready for next coordination gate.

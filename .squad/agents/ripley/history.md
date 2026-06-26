# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: OS + package management moved from custom scripts to Ansible; k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. The old `k8s/src` + `envsubst` + `deploy.sh` pipeline is removed — do not reintroduce it. My focus as Lead is keeping the GitOps control plane coherent, gating promotions, and reviewing changes for production safety.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Comprehensive global repo-structure and GitOps review. Identified 5 refactor orphans (.env.sample legacy toggles, variable-inventory.md stale refs, apps/speedtest stub, apps/kube-system misclassified, bootstrap old env vars) and 9 structural improvements. Key decisions: .env.sample rewrite (P1), kube-system relocation (P1), apps appset sync-wave annotation (P2), Traefik CRD API group verification (P1), CRD Applications prerequisite (P1).

Output: `files/review/ripley-global-gitops.md`. All findings merged into `decisions.md`. GitHub milestone #1 "Post-Refactor Review & Hardening" now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Ready for next session sprint on structural cleanups.


## Session: Existing-Issue Triage Follow-On (2026-06-26)

Existing-issue triage completed and results merged into decisions.md. Coordinator (previous phase) closed #3 (k3sup, superseded), #10 (MetalLB, done), #19 (ArgoCD, done). Your assigned backlog queue: 3 issues now enriched and moved to Feature Backlog milestone #2:
- **#7** kured automatic node reboots (P3)
- **#14** Dashy homelab dashboard (P3)
- **#20** k3s system-upgrade-controller (P3)

No sprint contention; all Feature Backlog issues are post-hardening scope. Ready for pickup when milestone #1 wind-down begins.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** Global GitOps review complete; sync-wave annotation applied to apps ApplicationSet (#25). Triage results recorded. Feature Backlog milestone created; 9 enriched issues promoted (#7, #11, #13–#18, #20). Next: .env.sample rewrite coordination + Traefik CRD verification (decisions #1, #4).

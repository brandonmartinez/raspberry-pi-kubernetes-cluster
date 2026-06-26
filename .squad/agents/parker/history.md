# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: OS + package management moved from custom scripts to Ansible. I own `ansible/` — `provision.yml` (fresh nodes), `adopt.yml` (read-mostly convergence for live nodes, gated by `_apply`/`allow_disruptive`), and roles `base`, `storage`, `k3s_server`, `k3s_agent`, `node_docker`. Lead with `ansible-playbook adopt.yml --check --diff --limit <host>`. Never auto-reboot or touch `/boot/cmdline.txt`, DNS, fstab, or USB mounts on a live node without explicit approval.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

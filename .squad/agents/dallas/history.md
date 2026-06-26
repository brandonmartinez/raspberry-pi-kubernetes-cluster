# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. I own `apps/<app>/` Kustomize bases and `platform/<stack>/` Helm values. Every workload is production: probes, resource limits, PDBs, topology spread, and HPAs where load varies. Model new apps on `apps/shlink/`. The apps ApplicationSet auto-discovers app folders — no per-app Application file.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

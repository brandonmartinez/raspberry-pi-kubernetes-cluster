# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: OS + package management moved from custom scripts to Ansible; k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. The old `k8s/src` + `envsubst` + `deploy.sh` pipeline is removed — do not reintroduce it. My focus as Lead is keeping the GitOps control plane coherent, gating promotions, and reviewing changes for production safety.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

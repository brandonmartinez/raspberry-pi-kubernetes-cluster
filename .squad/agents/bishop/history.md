# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Security and privacy matter: it's exposed to the world.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Secrets are referenced, never committed. Values live in 1Password (a Family account — no External Secrets Operator). `secrets/templates/*.yaml` hold `op://` references; `scripts/sync-secrets.sh` resolves them with `op inject` and `kubectl apply` upserts them — a workstation push, never a cluster pull. TLS is cert-manager + `letsencrypt-prod`. `scripts/validate.sh` runs a secret scan and a prune/selfHeal guard (protecting CRDs, Longhorn, PostgreSQL, Pi-hole). Never commit a real value; only `op://` refs / `${VAR}` placeholders.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

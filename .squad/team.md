# Squad Team

> raspberry-pi-kubernetes-cluster

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Ripley | Lead / Platform Architect | .squad/agents/ripley/charter.md | 🏗️ active |
| Dallas | GitOps / Kubernetes Engineer | .squad/agents/dallas/charter.md | ⚙️ active |
| Parker | Infra / Ansible Engineer | .squad/agents/parker/charter.md | 🔧 active |
| Bishop | Security & Secrets Engineer | .squad/agents/bishop/charter.md | 🔒 active |
| Lambert | Docs / Technical Writer | .squad/agents/lambert/charter.md | 📝 active |
| Ash | Observability / Monitoring Engineer | .squad/agents/ash/charter.md | 📡 active |
| Scribe | Session Logger / Memory | .squad/agents/scribe/charter.md | 📋 silent |
| Ralph | Work Monitor | .squad/agents/ralph/charter.md | 🔄 monitor |
| Rai | RAI Reviewer | .squad/agents/Rai/charter.md | 🛡️ background |

## Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible, Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Universe:** Alien
- **Created:** 2026-06-26

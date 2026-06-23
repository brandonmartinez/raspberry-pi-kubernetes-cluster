# Raspberry Pi Kubernetes Cluster

Production homelab Kubernetes on Raspberry Pi 4B nodes, running k3s for home-network infrastructure (Pi-hole DNS, chrony NTP, PostgreSQL) and public services such as the bmtn.us Shlink URL shortener. This repo is being overhauled from imperative provisioning/deploy scripts to GitOps: Ansible prepares nodes, ArgoCD reconciles cluster state from Git, and External Secrets Operator pulls runtime secrets from 1Password.

## Repository map

| Path | Role |
| --- | --- |
| `ansible/` | Node provisioning and adoption automation; replaces the legacy numbered `rpi/src/*.sh` flow. |
| `platform/` | Shared GitOps platform stack: external-secrets, cert-manager, longhorn, security, data, monitoring, descheduler. |
| `apps/` | Leaf workloads; one app per folder, discovered by the ArgoCD ApplicationSet. |
| `clusters/` | Per-cluster ArgoCD control plane (`clusters/rpi/root.yml` app-of-apps). |
| `bootstrap/` | Imperative bootstrap scripts for ArgoCD, secret zero, ESO, and first root app handoff. |
| `scripts/` | Operator helpers: `validate.sh` (CI checks), `apply.sh` (push/break-glass), `backup.sh` (pre-migration capture). |
| `docs/` | Architecture, GitOps, secrets, provisioning, variable inventory, and runbooks. |
| `docker/` | Standalone Docker Compose services not yet in k3s/GitOps (secrets via `docker/.env`). |
| `.github/workflows/` | CI: runs `scripts/validate.sh` (kustomize build, helm template, secret scan, prune-policy guard) on PRs. |
| `renovate.json` | Automated dependency-update PRs for images, Helm charts, and Actions (replaces Watchtower; stateful components gated). |
| `rpi/` | Legacy Raspberry Pi shell provisioning scripts; retained for reference, being retired. |
| `k8s/` | Legacy Kustomize/Helm deployment pipeline; `k8s/src/deploy.sh` is being retired. |

## Deployment model

```mermaid
flowchart LR
  dev[Developer / operator] --> git[Git repository]
  git --> argocd[ArgoCD app-of-apps]
  argocd --> platform[Platform stack]
  argocd --> apps[apps/* workloads]
  platform --> cluster[(k3s cluster on Raspberry Pi)]
  apps --> cluster
  ansible[Ansible] --> nodes[Pi nodes]
  nodes --> cluster
  eso[External Secrets Operator] --> op[1Password vault]
  eso --> cluster
```

ArgoCD starts observed-only: no automated sync is committed initially. See [docs/gitops.md](docs/gitops.md) for sync waves and promotion gates.

## Start here

- Architecture: [docs/architecture.md](docs/architecture.md)
- Provisioning and adoption: [docs/provisioning.md](docs/provisioning.md)
- Secrets model: [docs/secrets.md](docs/secrets.md)
- Bootstrap order: [docs/runbooks/bootstrap.md](docs/runbooks/bootstrap.md)
- Break-glass operations: [docs/runbooks/break-glass.md](docs/runbooks/break-glass.md)
- Pi-hole migration: [docs/runbooks/pihole-migration.md](docs/runbooks/pihole-migration.md)
- Disaster recovery: [docs/runbooks/disaster-recovery.md](docs/runbooks/disaster-recovery.md)

Do not use `k8s/src/deploy.sh` for new GitOps-managed changes except as legacy context.

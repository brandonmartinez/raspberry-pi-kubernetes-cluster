# GitHub Copilot Instructions

These instructions apply to all AI models and agents working on this repository
(GPT Codex, Claude Opus, Claude Sonnet, and others). Follow them precisely.

## Project overview

This repository provisions and operates a **production-grade home lab Kubernetes
cluster** running on Raspberry Pi 4B devices using [k3s](https://k3s.io). It
serves real traffic for home network services (DNS, NTP, databases) and
public-facing applications (e.g., the bmtn.us URL shortener). **Treat the
cluster as live production at all times — changes must be additive and
non-disruptive.**

The cluster is **GitOps-managed by [ArgoCD](https://argo-cd.readthedocs.io)**:
ArgoCD reconciles this Git repo into the cluster. Node provisioning is moving
from shell scripts to **Ansible**. Secrets are **pushed** from 1Password by a
workstation script (the cluster never pulls secrets at runtime).

### Repository areas

| Area | Path | Purpose |
| --- | --- | --- |
| **GitOps control plane** | `clusters/rpi/` | ArgoCD entrypoints: AppProjects, app-of-apps root, platform Applications, and the apps ApplicationSet. |
| **Platform (shared) stack** | `platform/<stack>/` | Cluster-wide dependencies every app relies on: cert-manager, longhorn, monitoring, data (PostgreSQL/pgbouncer), security, traefik-config, descheduler, argocd, crds. |
| **Applications** | `apps/<app>/` | One folder per leaf workload. Auto-discovered by the apps ApplicationSet (directory generator). |
| **Kustomize components** | `components/cluster-config/` | Reusable cluster values (hostname suffix, ACME email) fanned into apps via Kustomize replacements. |
| **Bootstrap** | `bootstrap/` | One-time, push-based control-plane install (`00-argocd.sh`). Not GitOps-managed. |
| **Secrets** | `secrets/` | Committed Kubernetes Secret templates whose values are 1Password `op://` references. Pushed by `scripts/sync-secrets.sh`. |
| **Provisioning** | `ansible/` | Node provisioning/adoption. `provision.yml` (fresh nodes), `adopt.yml` (read-mostly live convergence), `bootstrap-node.sh` (node-local entrypoint). |
| **Scripts** | `scripts/` | `validate.sh` (local CI), `sync-secrets.sh` (1Password push), `apply.sh` (break-glass kustomize apply), `backup.sh` (read-only capture), `seed-1password.sh`. |
| **Docs** | `docs/` | Architecture, gitops, secrets, provisioning, variable-inventory, and `runbooks/`. |
| **Docker** | `docker/` | Standalone Docker Compose for services not in k3s (e.g., scrypted). |
| **Shared utilities** | `_shared/echo.sh` | Logging helpers (`section`, `log`) sourced by every script. |

> The old `k8s/src` Kustomize + `envsubst` + `deploy.sh` pipeline has been
> **removed**. The `${DOLLAR}`/`envsubst`/`DEPLOY_*`-toggle conventions are gone.
> Do not reintroduce them.

## GitOps model (ArgoCD)

Read `docs/gitops.md` for the full model. Essentials:

- **App-of-apps + ApplicationSet.** `clusters/rpi/root.yml` is the root
  Application. It renders `platform-apps.yml` (explicit, sync-wave-ordered
  platform Applications) and `apps-appset.yml` (an ApplicationSet whose
  directory generator creates one Application per `apps/*` folder).
- **AppProjects gate sources.** `clusters/rpi/projects.yml` defines the
  `platform` and `apps` projects. An Application is **rejected**
  (`InvalidSpecError`) if its `repoURL` is not listed in the target project's
  `sourceRepos`. When you add an Application that pulls a new Helm repo, add that
  repo to the project's `sourceRepos`. `projects.yml` is applied **imperatively**
  (the root app's `directory.include` deliberately excludes it).
- **Manual sync by default — no auto-pilot.** No Application enables `automated`
  sync, `prune`, or `selfHeal` by default. First sync of anything is manual and
  observed-only. Promotion to auto-sync/prune is per-app and gated (see
  `docs/gitops.md` "Promotion gates").
- **Sync waves** order platform stacks (cert-manager/longhorn first, etc.) via
  the `argocd.argoproj.io/sync-wave` annotation.
- **ServerSideApply** is required for large CRDs/charts. The app specs set it,
  but a **manually triggered** sync operation does not inherit
  `spec.syncPolicy.syncOptions` — pass `ServerSideApply=true` explicitly when
  hand-running an operation on CRD-heavy apps (kube-prometheus-stack, etc.).

### Self-repo Argo refs

All self-repo Argo refs (`targetRevision`, the appset generator `revision`,
`argocd-selfmanage.yml`) track **`main`**. Keep them on `main`; only point a
ref at a feature branch for a temporary trial, and flip it back to `main`
before merging.

## How a platform stack is structured

Most platform stacks are **Helm charts adopted in place** with frozen versions:

- The Application in `platform-apps.yml` uses a **multi-source** pattern: source
  1 is the upstream chart pinned to the **live deployed version**; source 2 is
  this repo as a `ref: values` so `valueFiles` can point at
  `$values/platform/<stack>/helm-values.yaml`.
- Edit `platform/<stack>/helm-values.yaml` to change a stack — never inline Helm
  flags. **Never `helm uninstall`** an adopted release. Keep the Application name
  == release name == live namespace.
- `platform/data/` (PostgreSQL + pgbouncer) and `platform/security/` are plain
  Kustomize bases, not Helm.
- CRDs live in their own apps under `platform/crds/` with **prune off** and
  server-side apply so controller upgrades never delete CRs.

## How an application is structured

Each `apps/<app>/` is a **plain Kustomize base** (works under `kustomize build`):

- `kustomization.yml` with the `labels` transformer (`app: <name>`,
  `includeSelectors: true`), a `configMapGenerator` over a committed **non-secret**
  `.env`, the `components/cluster-config` component (for host/IP fan-out), and a
  `resources:` list of the manifests.
- Manifests: `namespace.yml`, `deployment.yml` (or statefulset), `service.yml`,
  `ingress.yml`, `pdb.yml`, and `horizontalpodautoscaler.yml` where relevant.
- The apps ApplicationSet auto-discovers the folder — **no per-app Application
  file is needed** (the `keycloak` placeholder is the one explicit exclusion).
- **HPA + ArgoCD:** for HPA-managed Deployments, do **not** commit a hard-coded
  `replicas`; the appset sets `ignoreDifferences` on `/spec/replicas` with
  `RespectIgnoreDifferences=true`.

### Adding an application

1. Create `apps/<app>/` with the Kustomize base above (model it on an existing
   app like `apps/shlink/`).
2. If it needs a Secret, add `secrets/templates/<app>.yaml` (a Secret manifest
   with `op://` field references) using the fixed Secret name the workload
   already references, then push it with `scripts/sync-secrets.sh <app>`.
3. If it needs the shared PostgreSQL, label its namespace
   `postgres-client=true` and run `scripts/sync-secrets.sh postgres-app` to fan
   out the shared DB Secret.
4. Run `scripts/validate.sh`, commit. The ApplicationSet generates the
   Application; **sync it manually** and verify before promoting.

## Secrets (1Password push-sync)

Read `docs/secrets.md`. The homelab uses a **1Password Family** account (no
Business service account), so there is **no External Secrets Operator**.

- `secrets/templates/*.yaml` are committed Kubernetes Secret manifests whose
  values are 1Password references (`{{ op://$OP_VAULT/item/field }}`). They are
  **not** ArgoCD resources.
- `scripts/sync-secrets.sh` runs on a workstation with a signed-in `op` session:
  `op inject` resolves references → `kubectl apply` upserts the Secret. The
  cluster never authenticates to 1Password, so a 1Password/DNS/internet outage
  has **zero** effect on running workloads (Secrets persist in etcd).
- Never commit real secret values — only `op://` references / `${VAR}`
  placeholders.

## Break-glass / push path

A pull-only GitOps loop must never block live debugging (the Pi-hole diagnosis
scenario). Keep both paths available and documented in
`docs/runbooks/break-glass.md`:

- **ArgoCD manual sync** of a single app (prune/selfHeal stay off).
- **`scripts/apply.sh <kustomize-dir>`** — `kustomize build | kubectl apply`
  (supports `--dry-run`) to push a directory directly, bypassing ArgoCD.

## Provisioning (Ansible)

Read `docs/provisioning.md`. Provisioning is `ansible/`.

- `provision.yml`: fresh-node setup (always applies). `adopt.yml`:
  **read-mostly** convergence for live nodes — every role is gated by an
  `_apply` var defaulting to `allow_disruptive` (false), so
  `ansible-playbook adopt.yml --check --diff --limit <host>` is genuinely
  read-only.
- Roles: `base`, `storage`, `k3s_server` (control-plane), `k3s_agent` (worker),
  `node_docker`. The `k3s_server` vs `k3s_agent` split is where master/worker
  config diverges.
- Never auto-reboot, change `/boot/cmdline.txt`, DNS, fstab, or USB mounts on a
  live node without explicit approval. Secrets (`admin_password_hash`,
  `k3s_token`) are empty placeholders supplied via Vault or `-e` at runtime.

## Bash and scripting conventions

- Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Source the logging helpers and resolve the repo root relative to the script:
  ```bash
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
  source "${REPO_ROOT}/_shared/echo.sh"
  ```
- Log with `section "Title"` for major steps and `log "message"` for detail.
  Never redefine these — always source `_shared/echo.sh`.
- Scripts must be **non-interactive** and **idempotent** where possible.

## Validation

`scripts/validate.sh` is local CI (also run by a GitHub Action). It runs
`kustomize build` on every base, `helm template` with committed values,
`kubeconform` (if installed), a **secret scan** (blocks plaintext secrets in
committed `.md`/manifests), and a **prune/selfHeal guard** (blocks prune/selfHeal
on protected apps: CRDs, Longhorn, PostgreSQL, Pi-hole). Run it before every
commit. Note the secret scanner flags `key: value` patterns in Markdown for
keys containing password/token/secret/etc. — use `` `key` → `value` `` form in
docs instead of colon assignment.

## High availability (HA)

Treat every workload as production and implement HA wherever possible.

### Required for every service

- **Health probes** — Every container should have `startupProbe`,
  `readinessProbe`, and `livenessProbe`. Use HTTP health endpoints when
  available (e.g., `/rest/health` for Shlink, `/` for static frontends). Fall
  back to `tcpSocket` or `exec` probes when no HTTP endpoint exists (e.g.,
  Minecraft Bedrock is UDP-only → `exec` probe).
- **Resource requests and limits** — Every container must specify
  `resources.requests` and `resources.limits` for both `memory` and `cpu`.

### Required for services that support multiple replicas

- **Multiple replicas** — Run 2+ replicas for stateless services; use an HPA
  when load varies (do not also commit a static `replicas` — see HPA note above).
- **PodDisruptionBudget (PDB)** — `pdb.yml` with `minAvailable: 1` (or
  appropriate) to survive node drains / rolling updates.
- **Topology spread constraints** — Use `topologySpreadConstraints` with
  `whenUnsatisfiable: ScheduleAnyway` (not `DoNotSchedule`) so pods spread across
  nodes but still schedule when nodes are limited:
  ```yaml
  topologySpreadConstraints:
    - labelSelector:
        matchLabels:
          app: <name>
      maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
  ```

### Services that cannot run multiple replicas

For databases or services with exclusive file locks:

- Still add health probes and resource limits.
- Still add a PDB (`minAvailable: 1`) to prevent accidental eviction.
- Document the HA limitation in a comment in the manifest.
- Consider alternatives (e.g., PgBouncer connection pooling for PostgreSQL).

## SSL and TLS

- SSL/TLS is managed by [cert-manager](https://cert-manager.io) using the
  `letsencrypt-prod` ClusterIssuer.
- Every Ingress should include:
  ```yaml
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.middlewares: security-redirect-https@kubernetescrd
  spec:
    ingressClassName: traefik
    tls:
      - secretName: <service>-tls
        hosts:
          - <hostname>
  ```
- Apply HTTPS everywhere for externally exposed services. Internal
  service-to-service traffic uses ClusterIP without TLS (trusted cluster
  networking). Hostnames are composed from `components/cluster-config` (the
  `themartinez.cloud` suffix) rather than hardcoded.

## Service networking patterns

- **ClusterIP** — Default for internal services. Static `clusterIP` (e.g.,
  PostgreSQL) only when other services need a stable address; prefer DNS names
  (e.g., `postgres-direct.data.svc.cluster.local`).
- **LoadBalancer** — For LAN-reachable services (Pi-hole DNS, chrony NTP,
  PostgreSQL external). Use `externalTrafficPolicy: Local` when source IP
  preservation matters.
- **Ingress** — HTTP/HTTPS via Traefik, always with TLS (see above).

## Critical do-nots

- **Never** `helm uninstall` an adopted release (cert-manager, Longhorn,
  monitoring, descheduler, argocd).
- **Never** enable prune/selfHeal on CRDs, Longhorn, PostgreSQL, or Pi-hole
  without the relevant runbook gate.
- **Never** recreate StatefulSets, PVCs, or immutable selectors just to make an
  ArgoCD diff disappear — investigate the diff instead.
- **Never** tear down or interrupt the running cluster. Everything is additive.

## Editing guidance

- Make incremental changes under the correct `apps/<app>/` or
  `platform/<stack>/` folder. There are no generated/compiled manifests to edit.
- Preserve 2-space YAML indentation and existing Bash style.
- **Tests are manual** — this cluster is validated by deploying. Favor small,
  reviewable changes; document verification steps in PR descriptions.
- Run `scripts/validate.sh` before committing.

## Documentation expectations

- Root `README.md` is the top-level map of the repo areas and getting-started
  flow.
- `docs/` holds architecture, gitops, secrets, provisioning, variable-inventory,
  and `runbooks/` (bootstrap, break-glass, pihole-migration, disaster-recovery).
- When adding a service, provisioning step, or platform stack, update the
  relevant doc(s) and keep paths accurate.

# GitHub Copilot Instructions

These instructions apply to all AI models and agents working on this repository
(GPT Codex, Claude Opus, Claude Sonnet, and others). Follow them precisely.

## Project overview

This repository provisions and operates a **production-grade home lab Kubernetes
cluster** running on Raspberry Pi 4B devices using [k3s](https://k3s.io). It
serves real traffic for home network services and public-facing applications
(e.g., the bmtn.us URL shortener).

The repo has two distinct areas:

| Area                    | Path                             | Purpose                                                                                                                             |
| ----------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **RPi provisioning**    | `rpi/src/001.sh` → `005.sh`      | One-time Bash scripts that prepare a fresh Raspbian install as a k3s master or worker node. Run manually with `sudo` on the device. |
| **Kubernetes services** | `k8s/src/resources/<namespace>/` | Long-lived Kustomize manifests, Helm value files, and deployment scripts for all cluster workloads.                                 |
| **Shared utilities**    | `_shared/echo.sh`                | Logging helpers (`section`, `log`) sourced by all scripts.                                                                          |
| **Docker**              | `docker/`                        | Standalone Docker Compose files for services not running in k3s.                                                                    |

## Bash and scripting conventions

- Start every script with `#!/usr/bin/env bash` and `set -e`.
- Source environment with
  `set -o allexport; source ../../.env; source ../../_shared/echo.sh; set +o allexport`
  (adjust relative path as needed).
- Scripts must be **non-interactive** and **idempotent** where possible.
- Log progress with `section "Title"` for major steps and `log "message"` for
  details. Never redefine these — always source `_shared/echo.sh`.
- RPi provisioning scripts use numeric prefixes (`001.sh`, `002.sh`, …). Add new
  steps at the end with the next sequential number.
- When modifying `_shared/` helpers, verify all downstream scripts remain
  compatible. Do not introduce package dependencies that may not exist on a
  fresh Raspbian install.

## Kubernetes project structure

### Directory layout

```
k8s/src/resources/<namespace>/
├── kustomization.yml      # Required — defines namespace, labels, generators, resources
├── .env                   # Non-secret config (consumed by configMapGenerator)
├── .env.secret            # Secret template with ${VAR} placeholders (consumed by secretGenerator)
├── deployment.yml         # Workload manifests
├── service.yml
├── ingress.yml
├── pdb.yml                # PodDisruptionBudget
└── ...
```

Each folder represents a Kubernetes namespace. There is no nested
`<namespace>/<app>/` hierarchy — all resources for a namespace live in one
folder.

### Kustomize conventions

**Labels and selectors** — Every `kustomization.yml` must use the `labels`
transformer with `includeSelectors: true`:

```yaml
labels:
  - pairs:
      app: <namespace-name>
    includeSelectors: true
```

This auto-injects `app: <name>` into all resource metadata and selectors.
Because of this:

- Resources that only need the namespace-level label should use **empty**
  `labels: {}` and `matchLabels: {}` in their manifests, letting Kustomize
  handle injection (see `data/postgres-statefulset.yml` as the reference
  pattern).
- Resources that need **additional** distinguishing labels (e.g.,
  `component: shortener` vs `component: web` within the same namespace) should
  explicitly declare those extra labels. The base `app` label from Kustomize
  will be added on top.

**Config and secrets** — Use `configMapGenerator` with `envs:` for `.env` files
and `secretGenerator` with `envs:` for `.env.secret.temp` files. Never create
ConfigMaps or Secrets manually when a generator can be used.

**Resources** — List all manifest files in the `resources:` array. When adding a
new manifest, add it here.

### Deployment pipeline

`k8s/src/deploy.sh` is the canonical deployment entrypoint. It:

1. Loads the root `.env` to read `DEPLOY_*` toggles.
2. Deploys Helm-managed stacks (Longhorn, cert-manager, Prometheus, Descheduler)
   via the `deploy_helm` helper.
3. Deploys Kustomize-managed stacks (PostgreSQL/data, then all service stacks)
   via the `deploy_kustomize` helper.
4. Dynamically assembles a top-level `kustomization.yml` referencing only the
   enabled service resource folders.
5. Renders manifests with `kubectl kustomize | envsubst` → writes `compiled.yml`
   → runs `kubectl apply -f`.

`k8s/src/deploy-from-local.sh` wraps `deploy.sh` for workstation-driven deploys.
It fetches `kubeconfig.yml` from the master node via SCP and exports
`KUBECONFIG`.

**CRITICAL:** NEVER use `kubectl apply -k` directly on kustomize resources.
ALWAYS use `./deploy-from-local.sh` or `./deploy.sh`. Direct `kubectl apply -k`
skips `envsubst` and deploys resources with unsubstituted placeholders like
`${POSTGRES_USER}`.

### The `${DOLLAR}` convention

`deploy.sh` exports `DOLLAR='$'` so that `envsubst` can process manifests
without destroying literal `$` characters (common in Prometheus rules and
Grafana dashboards). In committed manifest files, write `${DOLLAR}` wherever a
literal `$` is needed in the rendered output. Never replace `${DOLLAR}` with `$`
in source files.

### `.env.secret` files

Templates under `k8s/src/resources/**/.env.secret` contain `${VAR}` placeholders
that are rendered to `.env.secret.temp` at deploy time via `envsubst`. The
`.temp` files are consumed by Kustomize `secretGenerator`. Never commit real
secret values — use placeholders and document required variables in
`.env.sample`.

### Compiled output

`compiled.yml`, `compiled-data.yml`, and `compiled-monitoring.yml` are runtime
artifacts generated by the deploy pipeline. Do not commit them.

## Environment and deployment toggles

The root `.env` file (copied from `.env.sample`) controls the entire cluster.
Key patterns:

- **`DEPLOY_*` flags** — Each service has a boolean toggle (e.g.,
  `DEPLOY_SHLINK=true`). To deploy only specific services, set the relevant
  flags to `true` and all others to `false`.
- **Cluster config** — `CLUSTER_HOSTNETWORKINGIPADDRESS`, `CLUSTER_NODES`,
  `NETWORK_HOSTNAME_SUFFIX`, etc.
- **Service config** — Per-service variables (e.g., `SHLINK_DEFAULT_DOMAIN`,
  `POSTGRES_USER`).

When adding a new service:

1. Add a `DEPLOY_<NAME>=true` toggle to `.env.sample`.
2. Add a conditional block in `deploy.sh` to include the resource folder.
3. Document any new environment variables in `.env.sample` with comments.

Never hardcode secrets or IPs in manifests — always use environment variables
processed by `envsubst`.

## Working with Helm charts

- Helm releases are defined through value files at
  `k8s/src/resources/<namespace>/helm-values.yml`.
- Update these YAML files rather than embedding inline Helm flags.
- Use the `deploy_helm` helper in `deploy.sh`. It handles repo add,
  install-or-upgrade logic, version pinning, and `envsubst` on the values file.
- Pin chart versions via environment variables (e.g., `LONGHORN_CHART_VERSION`,
  `PROMETHEUS_CHART_VERSION`).

## High availability (HA)

This cluster runs production home services. Treat every workload as production
and implement HA wherever possible:

### Required for every service

- **Health probes** — Every container must have `startupProbe`,
  `readinessProbe`, and `livenessProbe`. Use HTTP health endpoints when
  available (e.g., `/rest/health` for Shlink, `/` for static frontends). Fall
  back to `tcpSocket` or `exec` probes when no HTTP endpoint exists.
- **Resource requests and limits** — Every container must specify
  `resources.requests` and `resources.limits` for both `memory` and `cpu`.

### Required for services that support multiple replicas

- **Multiple replicas** — Run 2+ replicas for stateless services. Use a
  `HorizontalPodAutoscaler` (HPA) when load varies.
- **PodDisruptionBudget (PDB)** — Create a `pdb.yml` with `minAvailable: 1` (or
  appropriate value) to survive voluntary disruptions (node drains, rolling
  updates).
- **Topology spread constraints** — Use `topologySpreadConstraints` with
  `whenUnsatisfiable: ScheduleAnyway` (not `DoNotSchedule`) to distribute pods
  across nodes while still allowing scheduling when nodes are limited:
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

Some services (e.g., databases, services with exclusive file locks) cannot scale
horizontally. For these:

- Still add health probes and resource limits.
- Still add a PDB (`minAvailable: 1`) to prevent accidental eviction.
- Document the HA limitation in a comment in the deployment manifest.
- Consider creative alternatives (e.g., connection pooling via PgBouncer for
  PostgreSQL, leader election for services that support it).

## SSL and TLS

- SSL/TLS is managed by [cert-manager](https://cert-manager.io) using the
  `letsencrypt-prod` ClusterIssuer.
- Every Ingress must include:
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
- Apply HTTPS everywhere. Do not create unencrypted Ingress routes for
  production services.
- Internal service-to-service communication within the cluster uses ClusterIP
  services without TLS (Kubernetes internal networking is trusted).

## Service networking patterns

- **ClusterIP** — Default for internal services. Use static `clusterIP` values
  (e.g., `10.43.100.50` for PostgreSQL) when other services need a stable
  address.
- **ClusterIP with named service** — Preferred over static IPs when possible.
  Reference services by DNS name (e.g.,
  `postgres-direct.data.svc.cluster.local`).
- **LoadBalancer** — For services that need to be accessible from the home
  network (e.g., Pi-hole DNS, PostgreSQL external access). Use
  `externalTrafficPolicy: Local` when source IP preservation matters.
- **Ingress** — For HTTP/HTTPS services exposed externally via Traefik. Always
  use TLS (see SSL section above).

## Editing guidance

- Make **incremental manifest changes** under the correct namespace folder.
  Never edit `compiled*.yml` or other generated files.
- Preserve **2-space YAML indentation** and existing Bash style.
- **Tests are manual** — this cluster is tested by deploying. Favor small,
  reviewable changes. Document verification steps in comments or PR
  descriptions.
- When referencing deploy scripts, use the full path `k8s/src/deploy.sh` (not
  the repo root) to avoid confusion.
- When deploying changes, update the root `.env` to set only the relevant
  `DEPLOY_*` flags to `true` and all others to `false`, then run
  `k8s/src/deploy-from-local.sh`.

## Documentation expectations

- The root `README.md` describes the project purpose, prerequisites, and getting
  started flow.
- `rpi/README.md` documents the provisioning script sequence and per-node setup.
- `k8s/README.md` catalogs all deployed services with links to their manifests.
- When adding new services or provisioning steps, update the relevant README(s).
- Keep script paths accurate: provisioning scripts are at `rpi/src/`, not
  `src/rpi/`.

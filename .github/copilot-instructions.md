# GitHub Copilot Instructions

## Repository overview
- The repo has two active surfaces:
  - `rpi/` contains single-run Bash scripts (`rpi/src/001.sh` → `005.sh`) that prepare Raspberry Pi hosts as k3s master or worker nodes. They are executed manually with `sudo` on the device.
  - `k8s/` holds the long-lived Kubernetes (k3s) application definitions and deployment tooling for the home lab cluster.
- Shared helpers live under `_shared/` (for example, `echo.sh` for logging utilities). Prefer reusing these helpers instead of redefining log utilities.

## Bash & scripting conventions
- Keep scripts POSIX-friendly Bash with `#!/usr/bin/env bash`, `set -e`, and `set -o allexport` patterns seen in existing files.
- Scripts should stay non-interactive and idempotent where possible; they are invoked manually in order and often require reboot between runs.
- Respect the numeric prefixes in `rpi/src/*.sh`; add new provisioning steps at the end with the next sequential number.
- When touching `_shared` helpers, ensure downstream scripts remain compatible; avoid introducing dependencies on missing packages.

## Kubernetes project structure
- `k8s/src/resources/<namespace>/<app>/` follows a workload/namespace/app layout that is Kustomize-ready. Each app folder usually contains its `kustomization.yml` plus manifests.
- `k8s/src/deploy.sh` is the canonical entrypoint for applying everything. It:
  1. Loads `.env` from the repository root to determine which stacks to deploy.
  2. Builds Helm releases (Longhorn, cert-manager, etc.) via the `deploy_helm` helper.
  3. Dynamically assembles a top-level `kustomization.yml` referencing the enabled resource folders.
  4. Runs `kubectl kustomize | envsubst` to render manifests, writing `compiled.yml`, then `kubectl apply`.
- **Important:** The script relies on `envsubst` while still allowing literal `$` values in output. It exports `DOLLAR='$'` and templates should escape `$` by writing `${DOLLAR}`. Preserve this convention; do not replace `${DOLLAR}` placeholders with `$` in committed files.
- `.env.secret` files under `k8s/src/resources/**` are rendered with `envsubst` at deploy time. Do not commit real secrets; keep placeholders and document required environment variables in `.env.sample`.
- `k8s/src/deploy-from-local.sh` wraps `deploy.sh` for workstation-driven deploys, fetching `kubeconfig.yml` from the master node. Ensure any new tooling respects the exported `KUBECONFIG` path.
- Avoid committing `compiled.yml` or machine-generated artifacts; they are runtime outputs.

## Working with Helm charts
- Helm releases are defined through value files in `k8s/src/resources/<workload>/helm-values.yml`. Update these YAMLs rather than embedding inline Helm flags.
- If you introduce a new Helm-managed stack, add a `DEPLOY_<NAME>` toggle to `.env.sample` and extend the conditional blocks in `deploy.sh`. Reuse the `deploy_helm` helper.

## Environment management
- `.env.sample` documents the full set of toggles and cluster settings. When adding variables, update this sample file and consume them via `set -o allexport` in scripts.
- Never hardcode secrets or IPs directly in manifests; rely on environment variables and secret templates processed at deploy time.

## Editing guidance for Copilot
- Prefer incremental manifest updates under the correct namespace/app folder instead of editing generated files.
- When suggesting changes, mention the `k8s/src/deploy.sh` location (not the repo root) to avoid confusion.
- In Bash scripts, log progress with `section`/`log` from `_shared/echo.sh` for consistency.
- Preserve YAML indentation (2 spaces) and Bash style used in existing files.
- Tests are manual (cluster deployment). Favor small, reviewable changes and document manual verification steps in comments or READMEs.

## Documentation expectations
- The root `README.md` introduces the two project areas. If new workflows are added (e.g., extra provisioning steps or deploy flags), update that README and any subfolder READMEs accordingly.
- Keep instructions for running scripts accurate with current paths (e.g., `rpi/src` vs. `src/rpi`).

Following these guidelines will keep Copilot aligned with the repository's deployment pipeline and prevent accidental breakage of the Raspberry Pi cluster automation.

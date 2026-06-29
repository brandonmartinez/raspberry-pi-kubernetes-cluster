# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

I own observability: the kube-prometheus-stack under `platform/monitoring/` (Prometheus, Alertmanager, Grafana on PostgreSQL, node-exporter, kube-state-metrics) and external/synthetic monitoring via the live Uptime Kuma instance at `uptime.themartinez.cloud`. The whole stack runs on 4GB RPi workers, so retention and resource budgets are tuned to observed usage — Prometheus is held at a 1536Mi limit with 21d/12GB retention + WAL compression; Grafana ~384Mi/1024Mi. kube-prometheus-stack CRDs are managed out-of-band (server-side apply, never pruned). I right-size the watchers and collaborate with Dallas on the watched so nothing tanks.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **The Uptime Kuma app IS in Git (`apps/uptime/` — Deployment + dedicated MariaDB StatefulSet); only the monitor inventory is runtime MariaDB state, not Git.** Monitors are managed against the running instance via the socket.io API (username/password). The `uk1_` API key authenticates **only** the Prometheus `/metrics` endpoint — it cannot create or edit monitors, and is effectively redundant here because Prometheus scrapes `/metrics` via **basic auth** using the same `UPTIME_USERNAME`/`UPTIME_PASSWORD`. A DB loss means restoring from a JSON backup via socket.io; keep a written inventory so recovery is fast.
- **API credentials already live in 1Password** — `op://$OP_VAULT/uptime/UPTIME_USERNAME` + `UPTIME_PASSWORD` (vault default `homelab`). Any API tooling pulls them at runtime via `op read`/`op inject` (same push-sync pattern as `scripts/sync-secrets.sh`) — no new key, nothing committed. The `uptime` item is shared by `secrets/templates/uptime.yaml`, `secrets/templates/monitoring.yaml` (scrape basic-auth), and `apps/uptime`.
- **Uptime Kuma `/metrics` → Prometheus (additionalScrapeConfigs, basic auth, 300s) → Grafana `uptime.json`.** The synthetic-check results surface in the cluster dashboards, so external and in-cluster monitoring are two ends of one pipeline.
- **MetalLB VIP map (monitor targets):** DNS VIP `192.168.52.53` (dnsdist), Ingress VIP `192.168.52.80` (Traefik 443), NTP VIP `192.168.52.54` (chrony — not synthetically monitorable: UDP/123, ping answered by MetalLB node regardless of chrony health), Minecraft VIP `192.168.52.81` (Bedrock UDP/19132, gamedig game key `mbe`).
- **DNS architecture:** Clients → dnsdist VIP `.53` (`externalTrafficPolicy: Local` → only answers on nodes running a ready dnsdist pod) → pihole → unbound. Legacy per-node `.52.110-113` resolver checks now flap and were retired in favor of the single VIP check.
- **Monitoring resource baselines live in comments** in `platform/monitoring/helm-values.yaml` — update them whenever a request/limit moves, with the observed number behind the change.
- **Uptime Kuma API tooling is ad-hoc by team decision** — not committed to the repo. Assemble it per task (1Password creds via `op read` + a throwaway `uptime-kuma-api` venv). The full reproducible recipe and library gotchas live in my charter under "Uptime Kuma API tooling." If a repeatable process emerges, formalize it as a **skill** + repo tool then — not before.

## Session: Onboarding + Uptime Kuma Restore & Tuning (2026-06-26)

Joined the squad as Observability / Monitoring Engineer. First task completed against the live Uptime Kuma instance after a database loss:

- **Restored** 29 monitors + 2 tags + the Discord notification from a JSON backup via the socket.io API (the `uk1_` key was insufficient — `/metrics` only).
- **Reconciled to current architecture:** deleted the 4 legacy per-node Pi-hole DNS monitors (`.52.110-113`) and added a single **DNS VIP** check (`192.168.52.53`, dns). Added **Ingress VIP** (`192.168.52.80`, TCP/443) and **Minecraft Bedrock** (`192.168.52.81`, gamedig `mbe`) monitors. All three verified **UP**.
- **Tuned per service type:** infra/HTTP retries=2 + 30s timeout; public canaries (Facebook, Google, Reddit, Cloudflare DNS, Google DNS) interval=300s, retries=1 — less noise, less data for endpoints that only validate internet connectivity.
- **Cut global retention 180d → 60d** (excess history wasn't earning its keep, especially for canaries).
- NTP VIP intentionally **not** monitored (no reliable synthetic check).

Continuity: Coordination point with Dallas on whether to bring Uptime Kuma into the repo as an `apps/uptime-kuma` base, and with Bishop on storing the Uptime Kuma credentials/API key in 1Password push-sync. Next watch item: confirm the new VIP monitors and retention change are reflected in the Grafana `uptime.json` dashboard.


## Session: Observability Stack Assessment & ServiceMonitor Gaps (2026-06-28)

**Mode:** Sync (Primary) | **Cross-Team:** Rai (secret-scan), Ripley (code-review)

Comprehensive review of `platform/monitoring/` kube-prometheus-stack health and ServiceMonitor coverage gaps:

- **Dashboard Health:** Identified root cause of 5 dead dashboards (control-plane Prometheus scrape jobs disabled). 2 dashboards working (kubelet, uptime probes). All recoverable once jobs re-enabled.
- **ServiceMonitor Gaps:** Documented 6 recommended ServiceMonitors for incremental deployment: node-exporter (ID1860, immediate priority), cluster metrics (ID15757), Longhorn, Traefik, cert-manager, MetalLB. Prioritized by observability ROI and memory budget.
- **Memory Budget:** Recommended retention 21d → 10d (~-300Mi), Grafana 1Gi → 512Mi feasible. Net +60–150Mi headroom available within current rpi004 budget (107% → 90–95% post-capacity-diet-#83 sync).

**Validation:** Rai confirmed secret-scan override (gitignored docs, `op://` refs only). Ripley approved analysis (minor MetalLB citation polish, non-blocking).

**Integration:** All findings staged in decisions.md § 11 for Coordinator prioritization. Review-only; no manifests changed. Recommendations ready to integrate with capacity diet #83 sync window. Node-exporter deployment (ID1860) recommended as immediate first step.

**Continuity:** Coordinate ServiceMonitor + retention optimization follow-up post-capacity-diet sync. Node-exporter addition should populate dead dashboards immediately (validate in live Grafana).

## 2026-06-28T21:10:50-04:00 — Observability implementation

Cross-agent handoff recorded by Scribe for Brandon Martinez. Ash removed 6 dead Grafana dashboards and entries, added lean dashboards for node-exporter 13978, cluster 15757, CoreDNS 5926, Longhorn 13032, and cert-manager 20842 using datasource `${DS_PROMETHEUS}`. Ash also added Longhorn and cert-manager ServiceMonitors (`release: monitoring`) and wired kustomization. Dallas fixed kubelet Endpoints to node IPs `192.168.52.110-113` in `apps+platform/kube-system/metrics-service.yml` and enabled the MetalLB ServiceMonitor. Ripley is reviewing. Edit-only; Brandon owns commits and `scripts/validate.sh`.

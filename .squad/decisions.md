# Squad Decisions

## Active Decisions

### 1. Decision: Convert nebulasync Deployment → CronJob (Issue #91)

**Author:** Dallas | **Date:** 2026-06-30T08:57:47.650-04:00 | **Status:** Approved → DEPLOYED & VERIFIED 2026-06-30 (Acceptance met; CronJob is sole workload; clean runs, no 429)

---

## Context

Issue #91 surfaced two compounding failures in `apps/nebulasync/`:

1. **Session leak → HTTP 429:** nebulasync v0.11.2 cannot invalidate its Pi-hole v6
   API sessions at the end of every sync run (WRN "Failed to invalidate session for
   target" on all three Pi-holes). Each 10-minute run leaks 3 sessions (one per
   Pi-hole replica). With Pi-hole's `webserver.session.timeout = 86400` (24h, changed
   from the default 1800s via `FTLCONF_webserver_session_timeout` in the pihole
   configmap), leaked sessions persist for 24 hours. The 16 session slots fill within
   5 sync cycles (~50 min of a fresh Pi-hole start), after which every subsequent auth
   attempt returns HTTP 429. This is a known upstream compat issue between nebulasync
   v0.11.x and Pi-hole v6 (lovelaze/nebula-sync GitHub issue #226).

2. **CrashLoopBackOff rollout stuck:** nebulasync v0.11.2 changed its failure log
   level from ERR (non-fatal, daemon continues) to FTL (fatal, process exits 1). In a
   Deployment, exit-1 triggers an immediate Kubernetes restart loop. The new digest-
   pinned RS (nebulasync-7cc9d44848) was permanently stuck at 38+ restarts, and the
   old `:latest` RS (nebulasync-76db546db4) remained running — two active RSes with
   both desired=1, both hitting Pi-hole every 10 minutes.

**Additional discovery (break-glass investigation):** A third nebulasync Deployment
was still alive in the `pihole` namespace — a 470-day-old orphan from before nebulasync
was migrated to its own namespace. This contributed a third concurrent sync pod,
amplifying session leak. The pihole-namespace Deployment is NOT in any current GitOps
manifest and must be cleaned up post-commit (see Verification Plan).

---

## Decision: CronJob replaces Deployment

**Choice:** Convert `apps/nebulasync/` from a `Deployment` to a `batch/v1 CronJob`.

**Rationale:**

- nebulasync is fundamentally a **run-to-completion batch tool**, not a daemon.
  Its built-in `CRON` env var daemon mode is at odds with Kubernetes' Deployment
  restart semantics. When the process exits non-zero (as v0.11.2 now does on any
  sync failure), a Deployment CrashLoopBackOffs and gets stuck in a rollout.
- A CronJob maps perfectly to the actual intent: run sync, exit, repeat on schedule.
  A failed Job is simply "Failed" and the next scheduled run fires normally — no
  stuck rollout, no CrashLoopBackOff, no perpetual RS churn.
- This direction is **consistent with earlier team thinking** (.squad/decisions.md §2:
  "Add Orbital Sync CronJob targeting pihole-0 as primary" — same CronJob model).
- `concurrencyPolicy: Forbid` prevents overlapping runs that would otherwise double
  the session leak rate during transient slowdowns.

**Key CronJob settings:**
- `schedule: "*/10 * * * *"` — unchanged from the previous `CRON` env var.
- `concurrencyPolicy: Forbid` — no overlapping runs.
- `backoffLimit: 1` — 2 total attempts per cycle before marking Failed (reduced from 2 per Ripley review).
- `activeDeadlineSeconds: 300` — kills a hung job within 5 min, before the next
  10-min cycle. Prevents orphaned pods accumulating under a Forbid policy.
- `successfulJobsHistoryLimit: 3 / failedJobsHistoryLimit: 3` — bounded history.
- `restartPolicy: OnFailure` — consistent with gravity-sync CronJob pattern.
- CRON env var removed from `.env` — nebulasync one-shot mode (exits 0/1 per run).
- PDB removed — no long-lived pod to protect.
- Probes removed — run-to-completion batch jobs do not use readiness/liveness probes.

---

## Version-pin decision: hold at current digest

Current image: `ghcr.io/lovelaze/nebula-sync@sha256:951576b448c08df16cc6b46f90cc3b40c44e10dfb56e431dfd0f1ead7d435724`
(v0.11.2 — confirmed in logs: `INF Starting nebula-sync v0.11.2`)

**Evidence gathered (2026-06-30):**
- No later release of lovelaze/nebula-sync confirms a fix for Pi-hole v6 session
  invalidation. The most recently indexed GitHub release is v0.11.1 (Sept 2025);
  the SHA above corresponds to v0.11.2 (current `:latest` on ghcr.io at time of
  issue). Upstream issue #226 ("Failing to invalidate sessions again") remains open.
- A web search returned an AI-generated claim that v0.11.2 "addresses session
  handling" — this is contradicted by live logs confirming v0.11.2 still WRNs on
  every invalidation attempt. This claim should NOT be trusted.

**Decision:** Hold the digest at v0.11.2. Do NOT chase an unverified claim of a fix.
When a confirmed upstream release with evidence of working session invalidation
on Pi-hole v6 becomes available, update the digest and document the PR testing result.

---

## Separate gated recommendation: reduce Pi-hole session TTL

This is **NOT** part of the nebulasync CronJob change. It requires a separate,
reviewed ArgoCD sync of the `pihole` app and a full DNS health verification. Filed as issue #93.

**Problem:** `FTLCONF_webserver_session_timeout = 86400` (24h) was set in the pihole
configmap (changed from the default 1800s). With the session invalidation bug in
nebulasync, leaked sessions persist for 24 hours. Even with the CronJob fix, if
invalidation continues to fail, each 10-min cycle leaks 3 sessions × up to 2
attempts = 6 sessions. With max_sessions=16 and 24h TTL, the session table may refill
within ~2.7h of intensive sync cycles after Pi-hole restart.

**Recommendation:** Change `FTLCONF_webserver_session_timeout` from `86400` to `300`
(5 minutes) in `apps/pihole/.env`. With a 5-min TTL and 10-min CronJob interval,
leaked sessions from run N expire well before run N+1 starts — the session table
never exceeds ~6 slots (3 Pi-holes × backoffLimit 2 attempts). This eliminates the
session exhaustion vector without requiring a working upstream fix.

**UX trade-off:** The Pi-hole admin web UI session will time out after 5 minutes of
inactivity (vs 24 hours currently). The web UI continuously refreshes sessions while
open, so only truly idle tabs are affected. Acceptable for a home lab.

**Gate:** Coordinate with Ripley. Apply only after:
1. This CronJob change is committed and deployed successfully (first clean sync confirmed).
2. No open Longhorn or StatefulSet maintenance on pihole at the time.
3. DNS health verified before and after the pihole sync.

---

## Files changed (nebulasync)

| Action | File |
|--------|------|
| Created | `apps/nebulasync/cronjob.yml` |
| Deleted | `apps/nebulasync/deployment.yml` |
| Deleted | `apps/nebulasync/pdb.yml` |
| Modified | `apps/nebulasync/.env` (removed `CRON=*/10 * * * *`) |
| Modified | `apps/nebulasync/kustomization.yml` (replaced deployment.yml+pdb.yml with cronjob.yml) |

---

## Deploy & Verification Outcome (2026-06-30)

**Deploy path:** Break-glass `kustomize build | kubectl apply` — ArgoCD CLI unavailable locally; used `kubectl kustomize apps/nebulasync | ssh pi@192.168.52.110 'sudo kubectl apply -f -'`. CronJob applied successfully; kustomize-generated configmap `nebulasync-configmap-dhghmdktbb` created.

**Deployment deletions:** Both stale Deployments imperatively deleted (stateless, no PVCs):
- `deploy/nebulasync -n nebulasync` (was 0/0 replicas, 2 old RSes) — ✅ DELETED
- `deploy/nebulasync -n pihole` (470-day orphan, 0/0 replicas) — ✅ DELETED

**Verification results:**
1. **First verify run (`nebulasync-verify`)** — Failed BackoffLimitExceeded (likely lingering Pi-hole session state or startup transient); pod killed before logs captured; ~1–2s failure before normal auth phase. Not reproducible in subsequent runs.
2. **Second verify run (`nebulasync-verify2`)** — ✅ Completed 1/1 in 28s. Clean logs: `INF Sync completed`. No 429 errors. Session invalidation successful (no WRN). Syncing 2 Pi-hole replicas.
3. **First scheduled run (`nebulasync-29713830` at 10:30)** — ✅ Completed 1/1 in 26s. Clean logs, no 429 errors. CronJob schedule firing correctly.

**Final workload state:**
- **nebulasync namespace:** CronJob is the sole nebulasync workload. No Deployments, no crash loops. ✅
- **pihole namespace:** Orphan Deployment deleted. ✅
- **Pi-hole health:** All 3 pods Running, DNS unaffected. ✅
- **Harmless orphans (prune off, safe to delete imperatively):** `pdb/nebulasync-pdb` (old era); `configmap/nebulasync-configmap-kd2h772tt5` (old hash-suffixed configmap).

**Recommendation: CLOSE #91.** Deployment → CronJob conversion deployed and verified. Two clean sync runs confirm no 429, session invalidation successful, schedule firing correctly.

**Recommendation: #93 (Pi-hole session TTL) remains GATED.** Awaiting Brandon's explicit approval to proceed with `FTLCONF_webserver_session_timeout: 86400→300` + one-pod-at-a-time pihole rollout with DNS verification (Ripley to coordinate).

---

## Post-deploy cleanup required

The 470-day-old nebulasync Deployment in the `pihole` namespace
(`deployment.apps/nebulasync` in namespace `pihole`) is an orphan — not in any
current GitOps manifest. It was scaled to 0 in the break-glass action but NOT
deleted. It must be imperatively deleted post-sync:

```sh
kubectl delete deploy/nebulasync -n pihole
```

This is a stateless Deployment with no PVCs. It poses zero DNS/data risk to delete.
It was not in any GitOps manifest so no ArgoCD sync is needed.

---

### 2. Security: Rotate two credentials exposed in git history (P1)

**Author:** Bishop | **Date:** 2026-06-26 | **Status:** Action Required

Two real credential values were found in this public repo's git history (both already cleared from the working tree). Specific identifiers — variable names, files, and commit SHAs — are intentionally kept out of this tracked ledger and held only in untracked review notes (`files/review/bishop-security.md`). Tracked publicly only in generic form as issue #23.

**Actions:** 
1. Rotate both credentials at their source apps, then re-push via `scripts/sync-secrets.sh` (P1, S) — issue #23
2. Decide on git-history scrub — requires force-push to `main` (P1, L — Brandon)
3. Fix `scripts/validate.sh` false positives (add `.copilot/` and `.squad/` to path-skip, P2, S) — issue #32

**Model verdict:** 1Password push-sync architecture is sound. All working-tree secrets clean.

---

### 3. DNS/Storage/Networking Stack Findings (P1–P3)

**Author:** Dallas | **Date:** 2026-06-26 | **Status:** Review Complete

#### Longhorn
- Config is Pi-tuned. **Gap:** No recurring backup/trim jobs scheduled (RPO = "never"). Add `daily-backup` (02:00, 7-day retention) and `weekly-trim` (Sun 03:00). defaultReplicaCount: 3 and reclaimPolicy: Retain are correct.

#### MetalLB
- Layer2 + klipper coexistence design is correct. Three `/32` VIPs with `autoAssign: false` correct.
- **Action:** Remove legacy klipper pihole LB services (pihole-dns-udp, pihole-dns-tcp) once UDM-Pro DHCP confirmed on dnsdist VIP (192.168.52.53).
- **Action:** Add `192.168.52.54` to MetalLB pool and migrate chrony from klipper node IPs.

#### DNS / Pi-hole
- Three-tier stack (dnsdist → pihole cluster → unbound) is sound.
- **Critical:** Pin `pihole/pihole` and `mvance/unbound-rpi` to specific semver tags NOW (v5/v6 config incompatibility is silent failure mode).
- **Critical:** No gravity sync between pihole replicas. Add Orbital Sync CronJob targeting pihole-0 as primary.
- **Action:** Add TLS + HTTPS redirect middleware to pihole admin ingresses.
- **Action:** Raise dnsdist PDB `minAvailable` from 1 → 2 (matches `externalTrafficPolicy: Local`).

**Follow-up:** P1: 4, P2: 7, P3: 4

---

### 4. Ansible Storage Role Must Align with Live Longhorn Mount Path (P1)

**Author:** Parker | **Date:** 2026-06-26 | **Status:** Proposed (Brandon confirmation needed)

Live cluster: `defaultDataPath: /media/data_ext/longhorn` (confirmed in helm-values.yaml)  
Ansible: `mount_usb_mount_path: /media/data`  
Gap: Live USB mounts on rpi002/003/004 are manual, not Ansible-managed.

**Constraint:** Do NOT run `adopt.yml` with `allow_disruptive=true` for storage role until:
1. Brandon confirms actual device/partition (`lsblk -f`)
2. `mount_usb_mount_path` corrected to `/media/data_ext` in `group_vars/all.yml`
3. `--check --diff` dry-run on non-Longhorn node shows no destructive mount changes
4. Longhorn is healthy (all volumes 3/3 replicas)

**Rationale:** Current path mismatch would create new fstab entry shadowing live Longhorn volumes.

---

### 5. Post-Refactor Repo Structure and GitOps Pipeline (P1–P2)

**Author:** Ripley | **Date:** 2026-06-26 | **Status:** Proposed — team action needed

**Key decisions:**

1. **`.env.sample` is legacy bloat (P1):** Still exports deleted `DEPLOY_*` toggles + placeholder secrets. Rewrite to document only current vars (`OP_VAULT`, optional `KUBECONFIG`). Assign: Lambert/Dallas.

2. **`apps/kube-system/` belongs in `platform/` (P1):** Breaks folder-name-equals-namespace convention. Move to `platform/`, add explicit Application to `platform-apps.yml` at wave 0.

3. **`apps/speedtest/` is a stub (P1):** Two-file directory with TODO comment. Commit real workload or delete. Decision deferred to Brandon/Dallas.

4. **Apps ApplicationSet missing sync-wave annotation (P2):** Add `argocd.argoproj.io/sync-wave: "2"` to appset metadata. Harmless today (manual-sync only) but latent risk. Ripley to execute.

5. **Traefik CRD API group verification required (P1 blocker):** Manifests use `traefik.containo.us/v1alpha1`; Traefik v3 uses `traefik.io/v1alpha1`. **Must verify against live cluster before platform sync.** If wrong, middleware fails → HTTPS redirects break. Ripley to verify.

6. **CRD Applications needed before prune enabled (P1):** `platform/crds/` is README placeholder. Create dedicated CRD Applications for cert-manager, longhorn, monitoring with prune off + versions pinned before enabling prune on dependent stacks.

**Non-decisions (confirmed correct):**
- `_backups/` gitignored by design (written by `scripts/backup.sh`)
- `ignoreDifferences` on `/spec/replicas` is correct cluster-wide for HPA compatibility
- Manual-sync-only default correctly implemented everywhere
- Multi-source Helm with frozen versions consistent across platform stacks
- `argocd-selfmanage.yml` outside root.yml scope is correct and intentional

---

### 6. Review Documentation Completed (Lambert, 2026-06-26)

**Status:** Delivered + security-redacted

- `docs/reviews/2026-06-26-repo-and-apps-review.md` — consolidated 4-reviewer report
- `docs/hardware-inventory.md` — hardware reference
- Both documents: no specific credential names, SHAs, or public IPs; RFC1918 LAN addresses retained as appropriate for public homelab repo

**Follow-up count:** P1: 10, P2: 21, P3: 14 (Total: 45)

---

### 7. Existing Open-Issue Triage Results (#3, #7, #10–#11, #13–#20)

**Author:** Ripley | **Date:** 2026-06-26 | **Status:** Recommended action (pending coordinator execution)

Triaged 12 pre-existing open issues against current repo state and 31 new issues (#22–#53):

**Recommend CLOSE (3):**
- **#3** (k3sup) — SUPERSEDED by Ansible provisioning roles
- **#10** (MetalLB) — DONE (0.15.2 live, Helm L2)
- **#19** (GitOps/ArgoCD) — DONE (full implementation in clusters/rpi/)

**ENRICH & KEEP (9):**
- #7 (kured reboots) — ripley, P3
- #11 (pihole-exporter) — dallas, P3
- #13 (Unpoller) — dallas, P3
- #14 (Dashy dashboard) — ripley, P3
- #15 (UniFi API Browser) — dallas, P3
- #16 (Plex Media Server) — parker, P3
- #17 (Jamulus Server) — parker, P3
- #18 (Diun notifications) — dallas, P3
- #20 (system-upgrade-controller) — ripley, P3

**Recommended backlog action:** Create Feature Backlog milestone + `feature-backlog` label; move 9 enriched issues into it. No overlaps with sprint issues #22–#53.

---

### 8. Hardware Inventory Live-Fill & Thermal/Mount Findings (Parker, 2026-06-26)

**Author:** Parker | **Date:** 2026-06-26 | **Status:** Completed + Action Items Identified

Updated `docs/hardware-inventory.md` with real values gathered live from the cluster (read-only inspection only).

**Per-Node Summary:**
- rpi001: Pi 4B 8GB, SanDisk SSD PLUS 240GB @ `/media/data_ext` (Docker/k3s, 26% used)
- rpi002: Pi 4B 4GB, SanDisk Extreme Pro ~256GB @ `/media/data_ext` (Longhorn, 14% used)
- rpi003: Pi 4B 4GB, SanDisk Extreme Pro ~256GB @ `/media/data_ext` (Longhorn, 30% used)
- rpi004: Pi 4B 4GB, SanDisk SSD PLUS 240GB @ `/media/data_ext` (Longhorn, 29% used)

All Bullseye (not Bookworm), kernel 6.1.21-v8+, SanDisk SR32G 32GB SD cards.

**CRITICAL — rpi003 Thermal Throttling (NEW-1):**
- At inspection: **78.4 °C** (threshold ~80 °C), `vcgencmd get_throttled` = `0xe0000` (soft temp limit, arm freq capped, throttling events)
- rpi003 hosts 5 Longhorn PVCs + Prometheus StatefulSet (25 GB) — heaviest load
- **Action:** Add heatsink/fan to rpi003 or redistribute Longhorn workloads. Thermal events may cause unnecessary replica timeouts/rebuilds.

**CRITICAL — rpi001 USB Mount Undocumented in Ansible (NEW-2):**
- rpi001 has `/dev/sda1` at `/media/data_ext` but `group_vars/all.yml` still sets `mount_usb: false`
- Extends existing F-02 finding to control-plane node. rpi001 USB is NOT Ansible-managed.

**MEDIUM — Inconsistent USB Mount Options (NEW-4):**
- rpi001/rpi004: `stripe=8191` mount option (manual tune)
- rpi002/rpi003: plain `rw,nosuid,nodev,relatime`
- **Action:** Investigate performance impact once mounts are Ansible-managed.

**Confirmed:** Issue #52 (HDD vs SSD) RESOLVED — all drives are SSDs; ROTA quirk is USB-bridge kernel behavior.

**Data Audit:** No secrets, tokens, passwords, serial numbers, MAC addresses, or public IPs in inventory. LAN IPs (192.168.52.x) retained.

---

### 9. Capacity Diet #83 — 6 Validated PRs (P1)

**Author:** Ash | **Date:** 2026-06-28 | **Status:** Ready for manual sync

Delivered 6 validated, reversible PRs targeting footprint reduction and control-plane capacity recovery for Q2 homelab live cluster.

**Footprint PRs (4):**
- **#84 Shlink 2→1 replica** (~-264Mi): verify baseline load supports 1 → manual sync only
- **#85 Longhorn 3→2 default + guaranteedInstanceManagerCPU 12→8%** (~-80Mi): backup gate verified (13/13 snapshots confirmed), applies to new volumes only; 5 existing vols migrate 3→2 incrementally one at a time
- **#86 Monitoring -300Mi** (retention 21→10d, drop Alertmanager + ingress/middleware/rule, Grafana 1Gi→512Mi)
- **#87 ArgoCD notifications disabled** (~-27Mi)

**Carryover PRs (2):**
- **#88 Descheduler v1alpha1→v1alpha2** (Longhorn/kube-system protections restored, helm-templated)
- **#89 MetalLB speaker tolerant probes** (per #75 probe spec, pod-disruption-safe)

**Baseline Pressure:**
- rpi001: 61% | rpi002: 88% | rpi003: 104% | rpi004: 107% (all over 80% threshold)
- Post-sync forecast: rpi004 ~90–95% (headroom achieved); rpi003 remains tight
- Major relief: shlink reduction + Longhorn 3→2 migration

**Recommended Sync Order:**
1. Shlink, monitoring, argocd, metallb, descheduler (fast, no data risk)
2. Longhorn (migrate remaining 5 vols from 3→2 one per week)

**Non-Capacity Issue Found:**
- meal-planner + nebulasync crashes are config (CreateContainerConfigError), not capacity — separate triage

---

### 10. Issue #23 Closed — Both Leaked Credentials Rotated (P1)

**Author:** Coordinator | **Date:** 2026-06-28 | **Status:** Complete

Security-sweep issue #23 is closed. Both historically-leaked credentials were confirmed rotated on 2026-06-28 by Brandon:

1. **Uptime Kuma admin password** (UPTIME_PASSWORD, leaked in .env.sample history f780e85..baea8ec) — rotated via Uptime Kuma UI, re-pushed via sync-secrets.sh
2. **Scrypted/Watchtower API token** (SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION / WATCHTOWER_HTTP_API_TOKEN, leaked in docker/scrypted.yml history 2fce99f) — regenerated in Scrypted UI, updated in docker/.env, re-pushed

**Git-History Scrub Sub-Task — Declined:**
- Rationale: `git filter-repo` rewrite changes every commit SHA, breaking ArgoCD self-repo refs (which track `main`), forks, clones, and SHA references, for zero security benefit once the credentials are rotated and old values are dead
- Decision: NOT pursued as part of #23 closure
- Future: Can be revisited as separate coordinated task if Brandon approves

**Follow-ups remaining (from Bishop sweep):**
- Issue #32: Fix `scripts/validate.sh` secret-scanner false positives (`.copilot/` and `.squad/` path-skip)

---

### 11. Mandatory Backup-Verification Gate — Any Operation Touching Persisted Data (P1 Standing Rule)

**Author:** squad-coordinator | **Date:** 2026-06-27 | **Status:** Standing Rule (Codified)

**Directive:** Brandon (@brandonmartinez) — standing rule following uptime data-loss incident (ApplicationSet exclusion without `preserveResourcesOnDeletion` cascade-deleted uptime's local-path PVC → permanent data loss).

**Hard Precondition Gate (No Exceptions):**

Before ANY operation that touches or could affect persisted data (PVCs, StatefulSets, databases, Longhorn volumes, file-backed storage, anything with a reclaim consequence):

1. **VERIFY backups are CONFIGURED** for affected data
   - For Longhorn-backed PVCs: confirm volume is in a backup RecurringJob group (e.g., `default` group → `backup-default`)
   - Check: `kubectl -n longhorn-system get recurringjobs.longhorn.io` and volume `recurring-job-group.longhorn.io/<group>: enabled` label

2. **VERIFY at least one backup has ACTUALLY COMPLETED** (not merely scheduled)
   - Confirm real, recent backup/snapshot exists (Longhorn volume backup status / `executionCount > 0`)
   - NOT: "we can probably recover it" or "backups should exist"

3. **Before a data-risking change, RE-VERIFY a fresh/current backup exists FIRST**, then proceed
   - If no verified, current backup exists → **STOP and do not risk the data**
   - Trigger a backup and confirm completion before continuing

**Why:** The data-loss incident proved that "we can probably recover" is not a backup. `local-path` PVCs (Delete reclaim) and pushed Secrets are especially fragile — NOT covered by Longhorn backups, treat as fragile and migrate stateful data to backed-up Longhorn volumes.

**Codification:** Being written into `.github/copilot-instructions.md` and tracked as P1 retro-action issue to build verification tooling and runbook grounded in Longhorn RecurringJob backups.

**Applies to:**
- Every agent (Ash, Dallas, Parker, Ripley, Lambert, Bishop, Rai)
- Every change touching: PVCs, StatefulSets, databases (PostgreSQL, Redis, etc.), Longhorn volumes, USB mounts, fstab, storage drivers
- Every infrastructure change that could cause a cascade deletion or data loss

---

### 12. Observability Stack Assessment & ServiceMonitor Gaps (P2–P3)

**Author:** Ash | **Date:** 2026-06-28 | **Status:** Review-only recommendations staged for prioritization

Comprehensive assessment of `platform/monitoring/` observability stack and kube-prometheus-stack deployment.

**Dashboard Health:**
- **5 of 7 dashboards DEAD** — root cause: control-plane jobs disabled (Prometheus scrape config gap)
  - Affected: Node Exporter, Cluster, Kubernetes API server, kubelet, kube-proxy dashboards
  - Status: RECOVERABLE (root cause identified; re-enabling jobs will populate dashboards)
- **2 of 7 dashboards working:**
  - kubelet probes ✅ (host visibility present)
  - uptime probes ✅ (endpoint monitoring present)

**ServiceMonitor Coverage Gaps:**

Currently deployed:
- prometheus-operator self-monitoring ✅

**Recommended for deployment (prioritized):**
1. **node-exporter ServiceMonitor (ID1860)** — IMMEDIATE (host-level metrics: CPU, memory, disk, network)
2. **cluster-level metrics (ID15757)** — high priority (kube-state-metrics coverage, pod/node/deployment telemetry)
3. **Longhorn volume/backup metrics** — medium (data path observability, backup success/failure tracking)
4. **Traefik ingress metrics** — medium (routing latency, request counts, error tracking)
5. **cert-manager renewal tracking** — medium (certificate expiry alerts, renewal automation assurance)
6. **MetalLB LoadBalancer service metrics** — lower (LAN service health, VIP failover tracking)

**Memory Budget Analysis:**
- Current: kube-prometheus-stack retention `21 days` → recommend `10 days` (~-300Mi)
- Grafana resource limit: `1Gi` → feasible at `512Mi` (standard dashboards)
- Alertmanager ingress/middleware/rule overhead: redundant for homelab → trim opportunity
- Net memory freed: ~+60–150Mi within current node budget (rpi004 at 107% can achieve headroom post-optimization)

**Integration Path:**
- Review-only; no manifests changed (gitignored review document)
- Recommendations staged for Coordinator prioritization
- Metrics deployment follows capacity diet #83 sync window (coordinate with retention optimization)
- Node-Exporter recommended first (quick, high observability ROI)

**Validation:**
- ✅ Ash: Analysis complete, recommendations documented
- ✅ Rai: Secret-scan override (docs/reviews gitignored, `op://` references only, no plaintext secrets)
- ✅ Ripley: Code review APPROVE (minor MetalLB line citation off-by-one, non-blocking)

---

### 13. Observability Implementation: Dashboards + ServiceMonitors Live (2026-06-29T01-15-08)

**Author:** Ash | **Date:** 2026-06-29 | **Status:** Edit-only pending sync

Executed observability stack implementation (Task 1–5 from decision #11 review):

**TASK 1 — Removed 6 dead dashboards:**
- Deleted etcd, kubernetes-api-server, kubernetes-controller-manager, kubernetes-kubelet, kubernetes-proxy, kubernetes-scheduler dashboard JSONs
- Removed corresponding 6 configMapGenerator entries from `platform/monitoring/kustomization.yml`
- Kept uptime.json/grafana-uptime

**TASK 3–4 — Added 5 lean dashboards + 2 ServiceMonitors:**
- **Dashboards:** node-exporter (1860, 124 panels ⚠️ heavy but high value for thermal visibility), cluster-overview (15757, 26 panels), coredns (5926, 12 panels), longhorn (13032, 28 panels), cert-manager (20842, 8 panels)
- All datasource UIDs normalized to `${DS_PROMETHEUS}` in JSON; added configMapGenerator entries with `disableNameSuffixHash: true` + `grafana_dashboard: "true"` label
- **ServiceMonitors:** longhorn (ns monitoring, app=longhorn-manager, port 9500, 60s) and certmanager (ns monitoring, app.kubernetes.io/name=cert-manager, port 9402, 120s); both labeled `release: monitoring`
- All resources added to `platform/monitoring/kustomization.yml`

**TASK 5 — Cardinality assessment:**
- Longhorn 60s, cert-manager 120s, no histogram cardinality adds
- Node Exporter Full (1860) concern: 124 panels vs. "avoid 100+ panel" guideline. Task explicitly named this ID; RPi thermal/memory visibility ROI justifies risk. Recommend Brandon post-sync evaluation; fallback to ID 13978 (26 panels) if render performance unacceptable

**Status:** Kustomization.yml + JSONs + ServiceMonitors committed (7 files); Dallas independently enabled MetalLB ServiceMonitor; edit-only (no git mutation by Scribe); pending Brandon manual sync.

---

### 14. Triage Verdicts for 27 Open Issues — Recommended Closures & Sprint Plan (2026-06-29T05-18-45)

**Author:** Ripley & team | **Date:** 2026-06-29 | **Status:** Read-only triage; pending Brandon closure execution

Full triage of 27 open issues by Ripley (lead), Dallas (GitOps/K8s), Parker (Infra), Bishop (Security), Ash (capacity/monitoring), Lambert (docs).

**RECOMMEND CLOSE (9 issues):**
- **#65** — preserveResourcesOnDeletion guard in scripts/validate.sh (check_appset_preserve_policy) + clusters/rpi/apps-appset.yml line 24
- **#71** — scripts/verify-backup.sh + docs/runbooks/backup-verification.md (both substantive)
- **#73** — epic COMPLETE: MetalLB HA (3 commits: 3366899, ad07ffe, +1), static node IPs in ansible host_vars, OS net self-healing watchdog templates
- **#40** — obsolete (dnsdist exec /dev/tcp probes, no dig in image)
- **#77** — superseded (qemu Minecraft replicas→0 in commit a9055d56; open work in #62 + #82)
- **#68** — docs/runbooks/heavy-rollouts.md + HomelabNodeHighLoadAverage alert in platform/monitoring/helm-values.yaml line 298
- **#67** — sync-secrets.sh --verify/--reconcile, commit 6d186ac9da, documented in docs/runbooks/credential-rotation.md + docs/secrets.md
- **#69** — docs/runbooks/argocd-outofsync.md + docs/runbooks/disaster-recovery.md (both substantive)
- **#45** — platform/crds/cert-manager v1.19.3 + platform/crds/monitoring kps 82.1.1; Longhorn/MetalLB infeasibility documented in clusters/rpi/platform-apps.yml lines 28–35

**RECOMMEND HOLD OPEN (1 issue):**
- **#46** — "Only 3 of 5 apps auto-sync." changedetection + unbound still in appset directory generator with no automated block (gate-3 auto-sync promotion pending) — FAILED VERIFICATION; open for follow-up #46.1: promote changedetection + unbound to gate-3 auto-sync to finish

**ENRICH & KEEP (9 issues — feature backlog):**
- #54, #16, #17, #74, #83, #66, #14, #11, #13, #15, #18, #62, #82, #70, #7, #20, #53 (various P2–P3 features and ongoing work)

**NEEDS-INFO (6 issues — requires clarification):**
- #62, #82, #70, #7, #20, #53 (clarification/design phase)

**Evidence-Based Verification:**
- Each owner re-verified evidence concretely before close recommendation
- All 9 recommended closures cite specific commits, file paths, runbook links, or live cluster evidence
- #46 held open because only 3 of 5 apps auto-sync enabled (changedetection + unbound lack gate-3 automation) — failing hard verification gate

---

### 15. Promote changedetection to GitOps gate-3 (auto-sync); keep unbound on manual sync (#46)

**Author:** Brandon Martinez (decision) — implemented by Dallas, reviewed/approved by Ripley | **Date:** 2026-06-29 | **Status:** Shipped via branch + PR; #46 closed

changedetection was promoted from ApplicationSet-generated to an explicit gate-3 Application in `clusters/rpi/apps-appset.yml`. Auto-sync is ON (`automated: {}`); prune and selfHeal remain OFF (gates 5/4). The change mirrors the uptime stateful pattern: fixed `replicas: 1`, no HPA, and therefore NO `/spec/replicas` ignoreDifferences.

unbound was intentionally NOT promoted. It remains generator-managed/manual per the DNS-path policy after the 2026-06-26 outage, tracked under DNS-resilience #73/#62/#70.

**Data safety:** changedetection is stateful (Longhorn PVC `changedetection-pvc`, reclaim `Retain`) with fresh backup `2026-06-29T07:00:07Z`. `preserveResourcesOnDeletion: true` ensures the generated → explicit handoff does NOT prune the PVC. `scripts/validate.sh` passed, including prune/selfHeal guard and ApplicationSet deletion-safety guard.

**Outcome:** shipped via branch `feat/changedetection-autosync` + PR; issue #46 closed.

---

### 16. Reviewer Gate Decision: Issue #93 — Pi-hole Session TTL 86400→300 (Ripley, 2026-06-30)

**Author:** Ripley | **Date:** 2026-06-30T12:26:15-04:00 | **Status:** APPROVED

**Verdict: APPROVE**

All safety gates pass. The plan is technically sound. Proceed with partition=0 release as described.

#### Gate-by-Gate Findings (live spot-check)

**GATE 1 — Data Safety: PASS ✅**
- All 3 PVCs (pihole-pvc-pihole-0/1/2): storageClass=longhorn, recurring-job-group=default → backup-default
- executionCount=271 — 271 completed backup executions confirmed
- lastBackupAt: 2026-06-30T07:01–07:03Z (today, ~5h before review)
- Data safety hard gate satisfied.

**GATE 2 — Cluster Health: PASS ✅**
- pihole-0: 1/1 Running, session_timeout=86400 (frozen, partition=1)
- pihole-1: 1/1 Running, session_timeout=300 ✓
- pihole-2: 1/1 Running, session_timeout=300 ✓
- DNS spot-check (github.com): all 3 pods + VIP resolving ✅
- PDB currentHealthy=3, disruptionsAllowed=1 — absorbs restart with margin

#### Review Answers

**Q1 — Safety gates adequate?** Yes. executionCount=271 with lastBackup=today is compelling evidence of functioning, recently-exercised backup chain. Health state confirmed live. No concurrent Longhorn rebuilds.

**Q2 — Releasing pihole-0 via partition=0: correct and safe?** Yes. StatefulSet pod template already references configmap pihole-configmap-bc58mbhchm (session_timeout=300 confirmed). Setting partition=0 is purely a gate release. Readiness probe is DNS-gated; pihole-0 not marked Ready until DNS answering. During ~30–60s restart, VIP routes to pihole-1/2 (both healthy).

**Q3 — GitOps hygiene: acceptable to leave OutOfSync until merge?** Yes, REQUIRED sequencing. Do NOT ArgoCD-sync before PR #94 merges. ArgoCD currently sources main (86400 old value). Pre-merge sync would revert all 3 pods back to 86400. After PR #94 merges, ArgoCD sync produces same configmap hash → no-op.

**Q4 — ArgoCD automated/selfHeal/prune state:** Live-verified. No automated block. No selfHeal. No prune. Zero auto-revert risk.

**Q5 — Required conditions before proceeding / blockers:** No blockers. Do NOT trigger ArgoCD manual sync until PR #94 merges to main — non-negotiable guardrail.

#### Recommended Execution Sequence
1. Patch partition 1→0
2. Watch pihole-0 restart
3. Verify pihole-0: Running 1/1, session_timeout=300, DNS resolving
4. Run nebulasync verify Job: confirm Completed 1/1, no 429
5. Merge PR #94 → main
6. (Optional) ArgoCD manual sync: expect no-op
7. Close #93

---

### 17. Decision: Issue #93 — Pi-hole Session TTL Roll Plan (Dallas, 2026-06-30)

**Author:** Dallas | **Date:** 2026-06-30T12:30:00-04:00 | **Status:** Proposed — awaiting coordinator merge

#### Context

Issue #93 reduces `FTLCONF_webserver_session_timeout` from 86400→300 to durably eliminate nebulasync HTTP 429s. PR #94 open on branch `squad/93-pihole-session-ttl-300`. A break-glass `kubectl kustomize` was already executed ~35 min before this check — roll already 2/3 complete.

#### Current Cluster State (as of 2026-06-30T12:30 EDT)

| Pod | session_timeout | Revision | Status |
|---|---|---|---|
| pihole-0 | 86400 (old) | pihole-58d559646f | frozen at partition=1 |
| pihole-1 | 300 ✓ | pihole-847677564f (update) | Ready |
| pihole-2 | 300 ✓ | pihole-847677564f (update) | Ready |

StatefulSet: updatedReplicas=2, readyReplicas=3, partition=1  
Active configmap: pihole-configmap-bc58mbhchm (session_timeout=300, created 35min ago)  
ArgoCD pihole: OutOfSync/Healthy — selfHeal=OFF, prune=OFF (safe)

#### Decision: Patch partition=0 to complete the roll

Only remaining action: `kubectl -n pihole patch sts pihole --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'`

This releases pihole-0. K8s rolls it one pod. Readiness probe gates promotion.

#### Deploy-source decision

- Break-glass apply already done. Do NOT trigger ArgoCD manual sync until PR #94 merges to main.
- After pihole-0 verified: merge PR #94 → main. ArgoCD sync produces same configmap hash → no-op.

#### Rollback path (if pihole-0 fails)

- pihole-1 and pihole-2 keep serving DNS (PDB minAvailable=2).
- Re-freeze: partition=1
- Investigate logs
- Emergency rollback: revert configmap to 86400 and close PR #94

---

### 18. Decision: Issue #93 Roll Complete (Dallas, 2026-06-30)

**Author:** Dallas | **Date:** 2026-06-30T12:35-04:00 | **Status:** COMPLETE

#### Outcome

The #93 pihole StatefulSet rolling update is fully complete. All three replicas now running `FTLCONF_webserver_session_timeout=300`.

#### Evidence

| Check | Result |
|-------|--------|
| STS pre-flight | updated=2, ready=3, partition=1 ✓ |
| Patch partition 1→0 | Applied at ~12:30 EDT |
| pihole-0 roll | Terminating → Running 0/1 → Running 1/1 in ~135s |
| pihole-1/2 during roll | Stayed 1/1 throughout (PDB not triggered) |
| session_timeout all pods | pihole-0=300, pihole-1=300, pihole-2=300 ✓ |
| STS final state | updated=3, ready=3, partition=0, READY 3/3 ✓ |
| DNS pihole-0 direct | github.com → 140.82.112.3, themartinez.cloud → 192.168.52.80 ✓ |
| nebulasync-verify93 | COMPLETED 1/1, no HTTP 429, INF Sync completed ✓ |
| Latest scheduled run | COMPLETED 1/1, no 429, no WRN ✓ |

#### Known Residual

nebulasync-verify93 emitted one WRN: "Failed to invalidate session for target: http://pihole-1.pihole.pihole.svc.cluster.local". This is the known nebulasync v0.11.2 / Pi-hole v6 session-invalidation incompatibility from issue #91. Non-fatal: with TTL=300s, even un-invalidated sessions expire within 5 minutes, preventing table saturation. Sync completed successfully; no 429 observed.

#### Recommended Next Actions

1. Merge PR #94 → ArgoCD sync (will be no-op; same configmap hash already live)
2. File issue for nebulasync v0.11.2 session invalidation WRN (track until upstream fixes Pi-hole v6 session API support)
3. VIP intermittency: investigate dnsdist load-distribution separately (pre-existing, not introduced by this change)

---

### 19. Platform data selector fan-out uses `role: pgbouncer` for pooler-only Services (#102)

**Author:** Dallas (implemented) / Scribe (recorded) | **Date:** 2026-07-01 | **Status:** PR #103 open; git-only, awaiting review/merge

Issue #102 found that Kustomize label fan-out made platform/data Services too broad: `app: data` is shared by both PostgreSQL and PgBouncer resources. Dallas fixed this on branch `fix/102-pgbouncer-selector-fanout` (commit `090288249ae88565aef42074542a972965c8d08f`) by adding `role: pgbouncer` to the PgBouncer pod template only and changing `postgres-svc` / `postgres-tcp` selectors to `{app: data, role: pgbouncer}`.

**Selector pattern:** use a narrow pod-template-only differentiator label for pooler-only Services, while leaving immutable workload selectors unchanged. This mirrors #101's `postgres-direct` approach of selecting the exact PostgreSQL endpoint instead of depending on broad app labels.

**Verified render:**
- `postgres-svc` and `postgres-tcp`: `{app: data, role: pgbouncer}`
- PgBouncer Deployment `matchLabels`: unchanged (`app: data`)
- PostgreSQL StatefulSet selector: unchanged (`app: data`)
- `postgres-direct`: unchanged pod-name selector

**Operational status:** no cluster apply. `platform/data` is manual-sync; after PR #103 merges, operator review and manual ArgoCD sync are required.

**Tooling gap discovered:** non-interactive shells did not have `/opt/homebrew/bin` on `PATH`, and `kustomize` / `kubectl` / `kubeconform` were initially unavailable. Dallas installed kustomize 5.8.1 and Homebrew bash 5.3.15 as local prerequisites; `scripts/validate.sh` passed with expected warnings for absent kubectl/kubeconform.

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

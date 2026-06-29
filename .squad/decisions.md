# Squad Decisions

## Active Decisions

### 1. Security: Rotate two credentials exposed in git history (P1)

**Author:** Bishop | **Date:** 2026-06-26 | **Status:** Action Required

Two real credential values were found in this public repo's git history (both already cleared from the working tree). Specific identifiers — variable names, files, and commit SHAs — are intentionally kept out of this tracked ledger and held only in untracked review notes (`files/review/bishop-security.md`). Tracked publicly only in generic form as issue #23.

**Actions:** 
1. Rotate both credentials at their source apps, then re-push via `scripts/sync-secrets.sh` (P1, S) — issue #23
2. Decide on git-history scrub — requires force-push to `main` (P1, L — Brandon)
3. Fix `scripts/validate.sh` false positives (add `.copilot/` and `.squad/` to path-skip, P2, S) — issue #32

**Model verdict:** 1Password push-sync architecture is sound. All working-tree secrets clean.

---

### 2. DNS/Storage/Networking Stack Findings (P1–P3)

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

### 3. Ansible Storage Role Must Align with Live Longhorn Mount Path (P1)

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

### 4. Post-Refactor Repo Structure and GitOps Pipeline (P1–P2)

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

### 5. Review Documentation Completed (Lambert, 2026-06-26)

**Status:** Delivered + security-redacted

- `docs/reviews/2026-06-26-repo-and-apps-review.md` — consolidated 4-reviewer report
- `docs/hardware-inventory.md` — hardware reference
- Both documents: no specific credential names, SHAs, or public IPs; RFC1918 LAN addresses retained as appropriate for public homelab repo

**Follow-up count:** P1: 10, P2: 21, P3: 14 (Total: 45)

---

### 6. Existing Open-Issue Triage Results (#3, #7, #10–#11, #13–#20)

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

### 7. Hardware Inventory Live-Fill & Thermal/Mount Findings (Parker, 2026-06-26)

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

### 8. Capacity Diet #83 — 6 Validated PRs (P1)

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

### 9. Issue #23 Closed — Both Leaked Credentials Rotated (P1)

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

### 10. Mandatory Backup-Verification Gate — Any Operation Touching Persisted Data (P1 Standing Rule)

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

### 11. Observability Stack Assessment & ServiceMonitor Gaps (P2–P3)

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

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

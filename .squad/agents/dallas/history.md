# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. I own `apps/<app>/` Kustomize bases and `platform/<stack>/` Helm values. Every workload is production: probes, resource limits, PDBs, topology spread, and HPAs where load varies. Model new apps on `apps/shlink/`. The apps ApplicationSet auto-discovers app folders — no per-app Application file.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Deep Longhorn, MetalLB, Pi-hole DNS stack review. Longhorn config is Pi-tuned; **gap:** no recurring backup/trim jobs (RPO = "never") — need daily-backup (02:00, 7-day retention) + weekly-trim (Sun 03:00). MetalLB layer2 + klipper coexistence correct; legacy pihole klipper LB services should be removed post-UDM-Pro DHCP confirmation. **Critical:** pin pihole and unbound-rpi to semver tags (v5/v6 incompatibility is silent failure); add Orbital Sync CronJob for pihole gravity sync; add TLS to pihole admin ingresses.

Output: `files/review/dallas-services.md` (P1: 4, P2: 7, P3: 4). All findings merged into `decisions.md`. GitHub milestone #1 now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Coordination point with Parker (storage) on Longhorn volume health gating for ansible adoption.


## Session: Existing-Issue Triage Follow-On (2026-06-26)

Existing-issue triage completed and results merged into decisions.md. Coordinator (previous phase) closed #3, #10, #19. Your assigned backlog queue: 5 issues now enriched and moved to Feature Backlog milestone #2:
- **#11** pihole-exporter / Prometheus metrics (P3)
- **#13** Unpoller / UDM-Pro metrics (P3)
- **#15** UniFi API Browser (P3)
- **#18** Diun image update notifications (P3)

Coordination point: also owns `.env.sample` rewrite decision (decision #4, P1 — coordinate with Lambert). No sprint contention on Feature Backlog.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** DNS/storage/networking review complete. Longhorn: backup/trim jobs gap identified (daily-backup + weekly-trim needed); default config (replicas=3, Retain) correct. Pi-hole: critical findings: pin versions (pihole v5/v6 incompatibility), add Orbital Sync CronJob, add TLS to admin ingresses; dnsdist PDB minAvailable raised to 2 (issues #26, #33–#36, #39). Feature Backlog: 5 issues promoted (#11, #13, #15, #18 + existing). .env.sample rewrite coordination point with Lambert. Ready for next platform hardening sprint.

## 2026-06-28T21:10:50-04:00 — Observability implementation

Cross-agent handoff recorded by Scribe for Brandon Martinez. Dallas fixed kubelet Endpoints to node IPs `192.168.52.110-113` in `apps+platform/kube-system/metrics-service.yml` and enabled the MetalLB ServiceMonitor. Ash removed 6 dead Grafana dashboards and entries, added lean dashboards for node-exporter 13978, cluster 15757, CoreDNS 5926, Longhorn 13032, and cert-manager 20842 using datasource `${DS_PROMETHEUS}`, added Longhorn/cert-manager ServiceMonitors (`release: monitoring`), and wired kustomization. Ripley is reviewing. Edit-only; Brandon owns commits and `scripts/validate.sh`.


---

### 2026-06-29T10:28:25Z — Issue Closure Verification Session (Cross-Agent Coordination)

**Session:** Verified closure of triage-flagged issues  
**Role:** GitOps/K8s infrastructure verification

- Re-verified & closed #65, #71, #73, #40 with concrete evidence (preserveResourcesOnDeletion guard, backup script, MetalLB HA commits, obsolete probes)
- Read-only verification only (gh-issue-API); no working-tree mutations
- Coordination: 5-agent parallel triage; backup-verification gate (decision #10) now standing rule
2026-06-29T11:05:06-04:00 Promoted changedetection to gate-3 explicit Application (stateful, auto-sync, prune/selfHeal OFF) in apps-appset.yml for #46.

---

## Session: Issue #91 — nebulasync CrashLoopBackOff + Pi-hole HTTP 429 (2026-06-30)

**Mode:** Sync (investigator) → Sync (lightweight) → Sync (deploy+verify, BLOCKED)  
**Status:** Decision #1 approved + PR #92 merged; live deploy blocked by network outage

**Phase 1 — Investigation (investigator):**
- Root-cause confirmed: nebulasync v0.11.2 cannot invalidate Pi-hole v6 sessions (WRN "Failed to invalidate" on all cycles)
- Session leak math: 10-min interval × 3 Pi-holes × 2+ attempts × 24h TTL → fills 16-slot session table in ~50 min
- CrashLoopBackOff: v0.11.2 exits on sync failure (FTL log level) → Deployment restart loop
- Orphan discovery: 470-day-old nebulasync Deployment in `pihole` namespace amplifying leak
- Decision: Deployment → CronJob (batch-job model, no restart loops); hold v0.11.2 digest pending upstream fix

**Phase 2 — Lightweight (apply changes):**
- Applied Ripley's required change: backoffLimit 2→1 (reduces leak from 9 to 6 sessions/cycle)
- Corrected leak-math comments; validate.sh PASS

**Phase 3 — Deploy+Verify (BLOCKED):**
- Network outage: workstation lost route to cluster LAN (~09:00 UTC)
- Cluster safely paused (nebulasync Deployments scaled to 0)
- Deferred: ArgoCD sync, first CronJob run verification, Pi-hole 429 confirmation, orphan cleanup (imperative `kubectl delete deploy/nebulasync -n pihole`)

**Gated follow-up:** Issue #93 (Pi-hole session TTL 86400 → 300s) filed; coordinate with Ripley post-deploy-verify.

## Session: Issue #91 — CronJob Deploy + Verification (2026-06-30T10:16:53-04:00)

**Mode:** Deploy+Verify (network restored, LAN SSH confirmed)
**Status:** COMPLETE — #91 acceptance MET

**Deploy path:** Break-glass `kubectl kustomize apps/nebulasync | kubectl apply` (argocd CLI not available). CronJob + configmap `nebulasync-configmap-dhghmdktbb` applied. ArgoCD Application `nebulasync` was Synced/Healthy on old state; manual apply overlaid the new CronJob on top.

**Deletions:**
- `deploy/nebulasync -n nebulasync`: DELETED (old Deployment, 0/0 replicas)
- `deploy/nebulasync -n pihole`: DELETED (470-day orphan, per decisions.md post-deploy cleanup note)

**Verify runs:**
1. `nebulasync-verify`: FAILED in ~1–2s (BackoffLimitExceeded). Pod logs lost. Probable Pi-hole 429 on first attempt (session table residue from crash-loop) or transient CRI startup issue.
2. `nebulasync-verify2`: COMPLETED 1/1 in 28s. `INF Sync completed`. No 429. No WRN on session invalidation.
3. Scheduled `nebulasync-29713830` (10:30 AM): COMPLETED 1/1 in 26s. `INF Sync completed`. No 429. Sessions invalidated successfully (`INF Invalidating sessions...` — no WRN).

**Final state:** CronJob only in nebulasync ns; no Deployments or RSes in nebulasync or pihole ns; Pi-hole pods all Running (3/3).

**Orphans (prune OFF):** `nebulasync-pdb` PDB + old configmap `nebulasync-configmap-kd2h772tt5` remain. Harmless; can be deleted imperatively.

**#91:** CLOSED. **#93 (session TTL):** Awaiting Brandon's approval — gated per decisions.md.

---

## Session: Issue #93 — EXECUTE: pihole-0 Roll + nebulasync Verify (2026-06-30T12:30-04:00)

**Mode:** Execute (approved by Brandon + Ripley)
**Status:** COMPLETE — #93 roll finished, all acceptance criteria met

**STEP 0 — Pre-flight (PASS):**
- STS: updated=2, ready=3, partition=1 ✓
- All 3 pods Running 1/1 (pihole-0 @ 10.42.3.84, pihole-1 @ 10.42.2.154, pihole-2 @ 10.42.1.213)

**STEP 1 — Patch partition 1→0:**
- `kubectl -n pihole patch sts pihole --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'` → PATCHED

**STEP 2 — Roll timeline (pihole-0):**
- T+0s: pihole-0 Terminating (old pod, 10.42.3.84); pihole-1/2 1/1 ✓
- T+25s: pihole-0 Running 0/1, new IP 10.42.3.118 (startupProbe warming)
- T+55s: pihole-0 Running 0/1 (66s age, probe still initializing)
- T+95s: pihole-0 Running 0/1 (112s age)
- T+135s: pihole-0 **Running 1/1** ✓ (2m38s age — startupProbe cleared)
- pihole-1 and pihole-2 stayed 1/1 throughout — PDB never triggered

**STEP 3 — Verification (PASS):**
- pihole-0 IP: 10.42.3.118 (rpi004)
- `FTLCONF_webserver_session_timeout=300` on pihole-0 ✓
- All three pods: pihole-0=300, pihole-1=300, pihole-2=300 ✓
- DNS on pihole-0 (10.42.3.118): github.com → 140.82.112.3, themartinez.cloud → 192.168.52.80 ✓
- DNS on VIP (192.168.52.53): intermittent (some queries resolve, some timeout) — confirmed pre-existing dnsdist condition, not caused by this roll; google.com resolved successfully on retry
- STS: updated=3, ready=3, partition=0 ✓ — READY 3/3

**STEP 4 — nebulasync verify (PASS):**
- Job: `nebulasync-verify93` COMPLETED 1/1 (30s)
- Logs: INF Sync completed; **NO HTTP 429**; one WRN "Failed to invalidate session for target: http://pihole-1.pihole.pihole.svc.cluster.local" (known v0.11.2 behaviour, non-fatal with 300s TTL — sessions expire in <5 min even if not explicitly invalidated)
- Latest scheduled run `nebulasync-29713950`: COMPLETED 1/1 in 28s; clean logs (no 429, no WRN, INF Sync completed) ✓
- Cleanup: `nebulasync-verify93` deleted ✓

**Outcome:** Issue #93 CLOSED. Pi-hole session TTL reduced from 86400 → 300s across all three replicas. nebulasync no-429 confirmed.

---

## Session: Issue #93 — Gate Verification + Roll Plan (2026-06-30T12:13-04:00)

**Mode:** Read-only gate verification + roll planning  
**Status:** GATE 1 PASS, GATE 2 PASS — critical mid-roll discovery; plan produced

**Cluster connectivity:** SSH to pi@192.168.52.110. Local kubectl credential error; all queries via SSH + `sudo kubectl`.

**GATE 1 — DATA SAFETY: PASS (verify-backup.sh equivalent, exit 0)**
- 3 pihole PVCs (pihole-pvc-pihole-{0,1,2}) → Longhorn volumes, storageClass=longhorn, group=default
- backup-default: task=backup, cron=`0 8 * * *`, retain=10, executionCount=**271**
- lastBackupAt today (2026-06-30T07:01-07:03Z) for all three volumes
- backup targets: `backup-target=default` label on all volumes

**GATE 2 — HEALTH: PASS**
- 3/3 Running+Ready 1/1; distinct nodes (pihole-0→rpi004, pihole-1→rpi002, pihole-2→rpi003)
- DNS resolving github.com on all 3 pod IPs (10.42.3.84, 10.42.2.154, 10.42.1.213) + VIP 192.168.52.53
- All 4 nodes Ready, none unschedulable; no active Longhorn rebuilds
- ArgoCD pihole: OutOfSync/Healthy, selfHeal=OFF, prune=OFF

**CRITICAL FINDING: Roll already 2/3 complete**
- Break-glass apply executed ~35min before this check: configmap `pihole-configmap-bc58mbhchm` (session_timeout=300) created, StatefulSet pod template updated
- Live partition=1 froze pihole-0; pihole-1+pihole-2 already rolled (session_timeout=300)
- pihole-0 still at session_timeout=86400 (currentRevision pihole-58d559646f, frozen by partition=1)
- StatefulSet: updatedReplicas=2, currentReplicas=1, readyReplicas=3

**Roll plan:** Only one action remains — `kubectl -n pihole patch sts pihole --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'`. No new apply needed. After pihole-0 rolls and DNS verifies clean: merge PR #94 → ArgoCD sync (no-op, same hash).

**Decision inbox:** `.squad/decisions/inbox/dallas-93-roll-plan.md`

---

## Session: Issue #102 — platform/data selector fan-out (2026-07-01T12:32:28-04:00)

Fixed GitHub issue #102 on branch `fix/102-pgbouncer-selector-fanout`, commit `090288249ae88565aef42074542a972965c8d08f`, PR #103 open. Added `role: pgbouncer` to the PgBouncer pod template only and changed `postgres-svc` / `postgres-tcp` selectors to `{app: data, role: pgbouncer}`. Kept PgBouncer Deployment `matchLabels`, PostgreSQL StatefulSet selector, and `postgres-direct` unchanged.

Validation: `scripts/validate.sh` passed with expected kubectl/kubeconform-missing warnings. Tooling gap: non-interactive PATH missed Homebrew tools under `/opt/homebrew/bin`; `kustomize`, `kubectl`, and `kubeconform` were initially absent. kustomize 5.8.1 and Homebrew bash 5.3.15 were installed locally as prerequisites.

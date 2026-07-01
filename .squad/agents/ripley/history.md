# Project Context

- **Owner:** Brandon Martinez
- **Project:** raspberry-pi-kubernetes-cluster — a production-grade home lab Kubernetes cluster on Raspberry Pi 4B (k3s). Serves real home + public traffic. Open source so others can learn from it. Treat the cluster as live production: changes are additive and non-disruptive.
- **Stack:** k3s, ArgoCD (app-of-apps + ApplicationSet), Kustomize + components, Helm (adopted charts, frozen versions), Ansible (node provisioning), Traefik, cert-manager (letsencrypt-prod), Longhorn, PostgreSQL + pgbouncer, 1Password CLI (push-sync secrets), Bash.
- **Created:** 2026-06-26

## Context

Just completed a big refactor: OS + package management moved from custom scripts to Ansible; k3s app deployment moved from a scripted pipeline to GitOps via ArgoCD. The old `k8s/src` + `envsubst` + `deploy.sh` pipeline is removed — do not reintroduce it. My focus as Lead is keeping the GitOps control plane coherent, gating promotions, and reviewing changes for production safety.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->


## Session: Post-Refactor Review + GitHub Tracking (2026-06-26)

Completed: Comprehensive global repo-structure and GitOps review. Identified 5 refactor orphans (.env.sample legacy toggles, variable-inventory.md stale refs, apps/speedtest stub, apps/kube-system misclassified, bootstrap old env vars) and 9 structural improvements. Key decisions: .env.sample rewrite (P1), kube-system relocation (P1), apps appset sync-wave annotation (P2), Traefik CRD API group verification (P1), CRD Applications prerequisite (P1).

Output: `files/review/ripley-global-gitops.md`. All findings merged into `decisions.md`. GitHub milestone #1 "Post-Refactor Review & Hardening" now tracks 32 issues (#22–#53).

Continuity: Agent history updated. Ready for next session sprint on structural cleanups.


## Session: Existing-Issue Triage Follow-On (2026-06-26)

Existing-issue triage completed and results merged into decisions.md. Coordinator (previous phase) closed #3 (k3sup, superseded), #10 (MetalLB, done), #19 (ArgoCD, done). Your assigned backlog queue: 3 issues now enriched and moved to Feature Backlog milestone #2:
- **#7** kured automatic node reboots (P3)
- **#14** Dashy homelab dashboard (P3)
- **#20** k3s system-upgrade-controller (P3)

No sprint contention; all Feature Backlog issues are post-hardening scope. Ready for pickup when milestone #1 wind-down begins.


## Sprint 1 (CI/HA Baseline) — Completion Note (2026-06-26)

**PR #55 merged.** Global GitOps review complete; sync-wave annotation applied to apps ApplicationSet (#25). Triage results recorded. Feature Backlog milestone created; 9 enriched issues promoted (#7, #11, #13–#18, #20). Next: .env.sample rewrite coordination + Traefik CRD verification (decisions #1, #4).


## Session: Observability Stack Review — Code Review (2026-06-28)

**Mode:** Sync | **Cross-Team Session:** Ash (primary), Rai (secret-scan override)

Reviewed Ash's comprehensive observability stack assessment and recommendations:

- **Analysis Validation:** Dashboard health findings sound (5 dead due to control-plane job config gap, 2 working). ServiceMonitor recommendations well-founded and prioritized by ROI. Memory budget analysis correct (21d → 10d saves ~300Mi, Grafana sizing feasible).
- **Code Review Result:** **APPROVE** ✅ — analysis structure and recommendations approved for team circulation.
- **Minor Issue Noted:** MetalLB ServiceMonitor citation line reference off-by-one in context (documentation polish only; does not affect recommendation validity or deployment).

**Secret-Scan Coordination:** Rai's false-positive override confirmed — gitignored review docs (`docs/reviews/2026-06-28-observability-stack-review.md`), `op://` references only, no plaintext secrets.

**Integration:** Findings merged into decisions.md § 11 (Observability Stack Assessment & ServiceMonitor Gaps). Review-only, no manifest changes. Recommendations staged for Coordinator prioritization against capacity diet #83 sync window.

**Continuity:** Ready for next sprint phase (ServiceMonitor deployment sequencing + retention optimization after capacity-diet baseline sync).


---

### 2026-06-29T10:28:25Z — Issue Closure Verification Session (Cross-Agent Coordination)

**Session:** Verified closure of triage-flagged issues  
**Role:** Lead verification + hard gates + #46 follow-up tracking

- Re-verified #45 closed (CRD Applications live, prune safety documented)
- Held #46 OPEN (changedetection + unbound lack gate-3 auto-sync automation)
- **Follow-up #46.1 (PRIORITY):** Promote changedetection + unbound to gate-3 auto-sync. This completes #46 verification.
- Coordination: 5-agent read-only triage; 9 issues closed with concrete evidence; decision #10 (backup-verification gate) now standing rule
- All orchestration logs written; decisions.md merged from inbox (3 entries); mutable state not committed per pattern

---

## Session: Issue #91 Reviewer Gate — nebulasync CrashLoopBackOff + Pi-hole HTTP 429 (2026-06-30)

**Mode:** Sync (reviewer gate)  
**Status:** PR #92 APPROVED WITH CHANGES; Dallas applied, Coordinator merged

**Review Outcome:**
- **Structure:** ✅ CronJob model correct for batch workload (consistent with pihole gravity-sync CronJob decision #2)
- **Required change:** backoffLimit 2→1 (aligns session-leak math: 3 Pi-holes × 2 attempts = 6 leaked sessions/cycle vs 9)
- **Post-sync cleanup flagged:** Two stale Deployments require imperative deletion (prune is off):
  1. `kubectl delete deploy/nebulasync -n pihole` (orphan, 470 days old)
  2. Old crash-looping RS `nebulasync-7cc9d44848` if not cleaned by ArgoCD sync
- **Gated follow-up approved:** Issue #93 (Pi-hole session TTL 86400 → 300s) separate PR, requires DNS health verification post-CronJob deploy

**Coordination:** Dallas → applied backoffLimit correction → validate.sh PASS → Coordinator merged PR #92.

**Continuity:** Awaiting network reconnect for deploy+verify. Will coordinate post-CronJob verification for issue #93 timing (TTL reduction requires clean sync first).

---

## Session: Issue #91 Deploy & Verification — nebulasync CronJob (2026-06-30T10:16:53-04:00)

**Mode:** Sync (Dallas executor, Brandon requester)  
**Status:** #91 DEPLOYMENT & VERIFICATION COMPLETE; acceptance met

Dallas deployed merged PR #92 (CronJob) via break-glass kustomize apply; deleted two stale Deployments (`deploy/nebulasync -n {nebulasync,pihole}`). Two clean verify runs confirm: nebulasync-verify2 Completed 1/1 in 28s, scheduled 10:30 Completed 1/1 in 26s — no 429 errors, session invalidation successful, CronJob schedule firing correctly. Pi-hole 3/3 Running, DNS unaffected.

**#91 recommendation:** CLOSE. Deployment → CronJob conversion deployed and verified.

**#93 (Pi-hole session-TTL 86400→300):** GATED, awaiting Brandon's explicit approval. When approved, Ripley to coordinate one-pod-at-a-time pihole StatefulSet rollout with DNS health verification before and after.

---

## Session: Issue #93 Reviewer Gate — Pi-hole Session TTL Roll (2026-06-30T12:26:15-04:00)

**Mode:** Reviewer gate (read-only spot-check + verdict)
**Status:** APPROVED — no blockers, proceed with partition=0 release

**Inputs reviewed:** Dallas's gate-verification report (dallas-93-roll-plan.md), Dallas history.md, live cluster SSH spot-checks.

**Live spot-checks performed (SSH pi@192.168.52.110):**
- StatefulSet: partition=1, updatedReplicas=2, currentReplicas=1, readyReplicas=3 — confirmed 2/3 roll complete
- Session timeouts: pihole-0=86400 (frozen), pihole-1=300 ✓, pihole-2=300 ✓
- DNS: github.com resolving on all 3 pod IPs + VIP 192.168.52.53 (140.82.114.4) ✓
- Configmap pihole-configmap-bc58mbhchm: `FTLCONF_webserver_session_timeout=300` ✓
- StatefulSet envFrom: references bc58mbhchm ✓
- ArgoCD syncPolicy: syncOptions only (CreateNamespace, ServerSideApply, RespectIgnoreDifferences) — no `automated`, no `selfHeal`, no `prune` ✓
- PDB: currentHealthy=3/desiredHealthy=2, disruptionsAllowed=1 ✓
- ArgoCD sync state: OutOfSync/Healthy (expected) ✓

**Gate 1 (data safety): PASS** — executionCount=271, lastBackup=2026-06-30T07:01–07:03Z
**Gate 2 (health): PASS** — 3/3 Running+Ready, distinct nodes, DNS fully operational
**ArgoCD auto-revert risk: NONE** — no automated/selfHeal/prune confirmed live

**Critical guardrail confirmed:** Do NOT ArgoCD-sync before PR #94 merges to main. Pre-merge sync re-generates configmap from old .env (86400) → different hash → rolls all 3 pods back. Post-merge sync is a no-op (same hash bc58mbhchm).

**Verdict:** APPROVE. Partition=0 is correct and safe. Break-glass-applied + partition-gated pattern was appropriate. OutOfSync/Healthy is a valid in-flight state.

**#93 close condition:** After nebulasync verify Job confirms Completed + no 429. PR merge + ArgoCD sync are hygiene steps, not acceptance criteria.

**Decision written to:** `.squad/decisions/inbox/ripley-93-gate.md`

---

## Session: Issue #102 — PR #103 awaiting review/merge (2026-07-01T12:32:28-04:00)

Dallas opened PR #103 for #102. The change is git-only: `postgres-svc` / `postgres-tcp` now target PgBouncer pods via `{app: data, role: pgbouncer}`; no cluster apply occurred. Because the data app is manual-sync, operator review/merge and a manual ArgoCD sync are still required.

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

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

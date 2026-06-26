# Hardware Inventory

This document records the physical hardware making up the homelab Kubernetes cluster so that others can learn from and replicate the setup. Values marked **TODO** need to be confirmed by the cluster owner; estimates or unknowns are flagged explicitly rather than invented.

---

## Cluster Overview

The cluster consists of **four Raspberry Pi 4B nodes** running [k3s](https://k3s.io) on Raspberry Pi OS (Debian 11 Bullseye) / arm64. The topology is:

- **1 control-plane node** (`rpi001`) — runs the k3s server, tainted `NoSchedule` so no workloads land here; also runs Homebridge and Scrypted via Docker using an external USB SSD. Does **not** participate in Longhorn storage.
- **3 worker nodes** (`rpi002`, `rpi003`, `rpi004`) — run all Kubernetes workloads; each contributes a USB-attached SSD to the [Longhorn](https://longhorn.io) replicated storage pool (3-replica default).

All nodes are on a flat LAN served by a Ubiquiti UDM-Pro. The cluster is GitOps-managed by [ArgoCD](https://argo-cd.readthedocs.io) (see `docs/gitops.md`).

**k3s API endpoint:** `https://192.168.52.110:6443` (rpi001)

---

## Nodes

| Hostname | FQDN | Role | Model | RAM | OS / Arch | LAN IP | Notes |
|---|---|---|---|---|---|---|---|
| `rpi001` | `rpi001.themartinez.cloud` | **Server** (control-plane) | Raspberry Pi 4 Model B Rev 1.5 | **8 GB** | Debian 11 (Bullseye) / arm64, kernel 6.1.21-v8+ | `192.168.52.110` | Tainted `NoSchedule` (control-plane + master); k3s API server; runs Homebridge and Scrypted via Docker on USB SSD. Not a Longhorn storage node. |
| `rpi002` | `rpi002.themartinez.cloud` | Agent (worker) | Raspberry Pi 4 Model B Rev 1.2 | **4 GB** | Debian 11 (Bullseye) / arm64, kernel 6.1.21-v8+ | `192.168.52.111` | Longhorn instance-manager active; Longhorn replicas on USB SSD. |
| `rpi003` | `rpi003.themartinez.cloud` | Agent (worker) | Raspberry Pi 4 Model B Rev 1.4 | **4 GB** | Debian 11 (Bullseye) / arm64, kernel 6.1.21-v8+ | `192.168.52.112` | Longhorn instance-manager active. ⚠️ Thermal concern: 78 °C observed at time of inventory with past throttling events (`throttled=0xe0000`). |
| `rpi004` | `rpi004.themartinez.cloud` | Agent (worker) | Raspberry Pi 4 Model B Rev 1.2 | **4 GB** | Debian 11 (Bullseye) / arm64, kernel 6.1.21-v8+ | `192.168.52.113` | Longhorn instance-manager active; Longhorn replicas on USB SSD. |

> **Sources:** live SSH inspection 2026-06-26 (`cat /proc/device-tree/model`, `free -h`, `uname -a`, `cat /etc/os-release`, `vcgencmd`); `ansible/inventory/hosts.yml`, `docs/architecture.md`.

### Boot configuration path

All nodes use `/boot/cmdline.txt` (Bullseye legacy path). The Bookworm path `/boot/firmware/cmdline.txt` does **not** exist on these nodes. This matters for Ansible roles and any automated cgroup / cmdline patching (see issue #50).

### SD cards

All four nodes have a **SanDisk SR32G 32 GB** microSD card as the boot/root drive. The card is identified by sysfs name `SR32G` from `/sys/block/mmcblk0/device/name`. Each SD card carries `/boot` (vFAT, ~255 MB) and `/` (ext4, ~29 GB, roughly 25–29 % used).

---

## Storage

Each worker node has an external USB SSD mounted at `/media/data_ext`. Longhorn uses `/media/data_ext/longhorn` as its default data path. The control-plane node (`rpi001`) also has a USB SSD mounted at `/media/data_ext`, used by Docker workloads (Homebridge, Scrypted) and k3s local data — it does **not** participate in Longhorn storage (the Longhorn manager daemonset targets only the 3 worker nodes due to the control-plane taint).

> ⚠️ **Important:** The USB mounts on all nodes were set up manually and are **not yet managed by Ansible** (see `docs/reviews/2026-06-26-repo-and-apps-review.md`, Parker finding F-02). `ansible/inventory/group_vars/all.yml` still shows `mount_usb: false` and `mount_usb_mount_path: /media/data`. Do not run `adopt.yml` with `allow_disruptive=true` for storage until these values are aligned with the live paths.

> ⚠️ **USB SSD ROTA quirk:** `lsblk` reports `ROTA=1` (rotational) for all USB-attached SSDs. This is a well-known Linux/USB-bridge kernel quirk — the USB controller does not advertise the non-rotational attribute. The model names confirm all drives are solid-state (SSD / flash); there are no spinning-disk HDDs in this cluster.

| Node | Device | Mount Point | Filesystem | Capacity | Current Usage | Purpose | How Managed |
|---|---|---|---|---|---|---|---|
| `rpi001` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 | 229 GB usable (232.9 GB raw) | ~57 GB used (26 %) | Docker data: Homebridge, Scrypted; k3s local storage. **Not** a Longhorn data node. | Manual (not Ansible-managed) |
| `rpi001` | `/dev/mmcblk0p2` | `/` | ext4 | ~29 GB | ~25 % used | OS root (SD card) | Not Ansible-managed for USB |
| `rpi002` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 | 234 GB usable (238.5 GB raw) | ~31 GB used (14 %) | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| `rpi003` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 | 234 GB usable (238.5 GB raw) | ~66 GB used (30 %) | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| `rpi004` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 | 229 GB usable (232.9 GB raw) | ~63 GB used (29 %) | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| all nodes | — | `/clusterfs` | — | — | — | Ansible-provisioned shared cluster directory (purpose TBD) | Ansible `storage` role |

**Off-cluster NAS (Longhorn backup target):** `192.168.52.100` — NFS share at `/rpi/longhorn/` (configured in `platform/longhorn/helm-values.yaml` as `backupTarget`). Longhorn **RecurringJobs are active in the live cluster** — daily backup (08:00, retain 10) and daily snapshot (02:00, retain 7) — so the real RPO is ~1 day, **not** "never". However, these jobs are **not codified in this repo** (GitOps drift: they would be lost on a Longhorn reinstall). Codifying them is tracked in issue #29. The NAS appliance itself is not managed by this repo.

### USB drive models

| Node | Model name (kernel) | Flash type | Raw capacity | Notes |
|---|---|---|---|---|
| `rpi001` | `SanDisk_SSD_PLUS_240GB` | SSD (SATA-in-USB enclosure) | 232.9 GB | `stripe=8191` mount option present (manual fstab entry) |
| `rpi002` | `Extreme_Pro` (SanDisk) | SSD / USB flash | 238.5 GB | SanDisk Extreme Pro USB; no stripe option |
| `rpi003` | `Extreme_Pro` (SanDisk) | SSD / USB flash | 238.5 GB | SanDisk Extreme Pro USB; no stripe option |
| `rpi004` | `SanDisk_SSD_PLUS_240GB` | SSD (SATA-in-USB enclosure) | 232.9 GB | `stripe=8191` mount option present (manual fstab entry) |

---

## Network

All nodes are on a single flat `/24` LAN with no VLAN segmentation between cluster nodes. The router/DHCP server is a Ubiquiti UDM-Pro.

| Item | Value | Source |
|---|---|---|
| LAN subnet | `192.168.52.0/24` | Inferred from node IPs |
| Router / DHCP | Ubiquiti UDM-Pro | `platform/metallb/helm-values.yaml`, `docs/runbooks/break-glass.md` |
| k3s API endpoint | `https://192.168.52.110:6443` | `ansible/roles/k3s_agent/defaults/main.yml` |
| DNS fallback (nodes) | `8.8.8.8`, `8.8.4.4` | `ansible/inventory/group_vars/all.yml` |
| Networking interface management | `dhcpcd` (active) + `networking`; **not** NetworkManager | Live: `systemctl is-active` on rpi002, 2026-06-26 (Bullseye default) |
| MetalLB mode | Layer 2 (gratuitous ARP) | `platform/metallb/l2advertisement.yml` |
| NAS (NFS backup) | `192.168.52.100` | `platform/longhorn/helm-values.yaml` |
| Hostname suffix | `themartinez.cloud` | `components/cluster-config/kustomization.yml` |
| Node network speed | **1000 Mbps full-duplex** (gigabit) on all 4 nodes | Live: `cat /sys/class/net/eth0/speed` 2026-06-26 |

### MetalLB VIP Map

[MetalLB](https://metallb.io) runs in L2 mode with `autoAssign: false` — no Service grabs a VIP unless it explicitly requests one. All VIPs use `externalTrafficPolicy: Local` so the announcing node is always the one running the relevant pod.

| VIP | Pool name | Service | Purpose |
|---|---|---|---|
| `192.168.52.53` | `dns-vip` | `apps/dnsdist/service.yml` | Cluster DNS (dnsdist → Pi-hole → Unbound). This is the address to hand out as primary DNS in UDM-Pro DHCP. |
| `192.168.52.80` | `ingress-vip` | `platform/traefik-config/ingress-vip-service.yml` | Traefik Ingress controller; all HTTP/HTTPS cluster services route through here. |
| `192.168.52.81` | `minecraft-vip` | `apps/minecraft/service.yml` | Minecraft Bedrock (UDP 19132) and Java (TCP 25565) exposed to the LAN. |

> **Note:** VIPs must fall outside the UDM-Pro DHCP lease range. TODO: confirm the exact DHCP exclusion range in the UDM-Pro and record it here so future operators know which IPs are safely available for new VIPs.

k3s klipper ServiceLB is still active for two services not yet migrated to MetalLB:

| Service | Type | Notes |
|---|---|---|
| `apps/chrony` chrony-ntp-udp | LoadBalancer (klipper) | NTP exposed on all node IPs; no stable single VIP yet. Migrating to a dedicated MetalLB VIP (`192.168.52.54`) is planned. |
| `apps/pihole` pihole-dns-udp / pihole-dns-tcp | LoadBalancer (klipper) | Phase-1 holdovers; DNS VIP has moved to dnsdist/MetalLB at `192.168.52.53`. These will be removed once UDM-Pro DHCP is confirmed pointing to the new VIP. |

---

## To Confirm / TODO

Items marked ✅ were resolved by live SSH inspection on 2026-06-26. Remaining items require access not available from the cluster.

| Item | Status | Notes |
|---|---|---|
| **RAM per node** | ✅ Resolved | rpi001 = 8 GB; rpi002/003/004 = 4 GB each (confirmed `free -h` + `/proc/meminfo`). |
| **Pi 4B hardware revision per node** | ✅ Resolved | rpi001 = Rev 1.5 (`d03115`); rpi002 = Rev 1.2 (`c03112`); rpi003 = Rev 1.4 (`c03114`); rpi004 = Rev 1.2 (`c03112`). |
| **SD card make/model and size per node** | ✅ Resolved | All four nodes: **SanDisk SR32G 32 GB** microSD, ~29.7 GB raw, `/` at ~25–29 % used, `/boot` at ~13 % used. |
| **USB drive make/model and capacity per node** (including rpi001) | ✅ Resolved | See USB drive models table above. rpi001: SanDisk SSD PLUS 240 GB. rpi002/rpi003: SanDisk Extreme Pro ~256 GB. rpi004: SanDisk SSD PLUS 240 GB. |
| **Whether rpi001 has a USB drive** | ✅ Resolved | Yes. rpi001 has `/dev/sda1` mounted at `/media/data_ext` (ext4, 229 GB). It hosts Docker workloads (homebridge, scrypted) and k3s local data — not Longhorn. |
| **Live filesystem type on `/media/data_ext`** | ✅ Resolved | **ext4** on all nodes (`lsblk -f` confirmed 2026-06-26). |
| **k3s version currently deployed** | ✅ Resolved | **v1.29.6+k3s2**, containerd 1.7.17-k3s1 (all nodes; `kubectl get nodes -o wide`). |
| **Raspberry Pi OS image version** | ✅ Resolved | **Debian GNU/Linux 11 (Bullseye)** on all nodes. The doc previously stated Bookworm — this was incorrect. Boot path is `/boot/cmdline.txt` (legacy), not `/boot/firmware/cmdline.txt` (Bookworm). See issue #50. |
| **Network speed per node** | ✅ Resolved | All nodes: **1000 Mbps full-duplex** (gigabit) — `/sys/class/net/eth0/speed` = 1000 on all four. |
| **WMI exporter IP address** | ⏳ Owner knowledge only | Referenced in `docs/variable-inventory.md` as `WMI_IP_ADDRESS` for Windows-exporter Prometheus scrape; not committed to the repo. |
| **UDM-Pro DHCP exclusion range** | ⏳ UDM-Pro admin console required | Must not overlap MetalLB VIPs (`.53`, `.80`, `.81`); document here once confirmed. |

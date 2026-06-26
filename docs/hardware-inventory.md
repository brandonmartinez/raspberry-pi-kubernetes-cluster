# Hardware Inventory

This document records the physical hardware making up the homelab Kubernetes cluster so that others can learn from and replicate the setup. Values marked **TODO** need to be confirmed by the cluster owner; estimates or unknowns are flagged explicitly rather than invented.

---

## Cluster Overview

The cluster consists of **four Raspberry Pi 4B nodes** running [k3s](https://k3s.io) on Raspberry Pi OS Bookworm (arm64). The topology is:

- **1 control-plane node** (`rpi001`) — runs the k3s server, tainted `NoSchedule` so no workloads land here, and also runs Homebridge via Docker.
- **3 worker nodes** (`rpi002`, `rpi003`, `rpi004`) — run all Kubernetes workloads; each contributes USB-attached storage to the [Longhorn](https://longhorn.io) replicated storage pool.

All nodes are on a flat LAN served by a Ubiquiti UDM-Pro. The cluster is GitOps-managed by [ArgoCD](https://argo-cd.readthedocs.io) (see `docs/gitops.md`).

**k3s API endpoint:** `https://192.168.52.110:6443` (rpi001)

---

## Nodes

| Hostname | FQDN | Role | Model | RAM | OS / Arch | LAN IP | Notes |
|---|---|---|---|---|---|---|---|
| `rpi001` | `rpi001.themartinez.cloud` | **Server** (control-plane) | Raspberry Pi 4B | TODO (4 GB or 8 GB) | Raspberry Pi OS Bookworm / arm64 | `192.168.52.110` | Tainted `NoSchedule`; runs Homebridge via Docker; k3s API server. Not a Longhorn storage node. |
| `rpi002` | `rpi002.themartinez.cloud` | Agent (worker) | Raspberry Pi 4B | TODO | Raspberry Pi OS Bookworm / arm64 | `192.168.52.111` | Longhorn instance-manager confirmed active. |
| `rpi003` | `rpi003.themartinez.cloud` | Agent (worker) | Raspberry Pi 4B | TODO | Raspberry Pi OS Bookworm / arm64 | `192.168.52.112` | Longhorn instance-manager confirmed active. |
| `rpi004` | `rpi004.themartinez.cloud` | Agent (worker) | Raspberry Pi 4B | TODO | Raspberry Pi OS Bookworm / arm64 | `192.168.52.113` | Longhorn instance-manager confirmed active. |

> **Sources:** `ansible/inventory/hosts.yml`, `docs/architecture.md`, backup capture `_backups/20260625-095248/kubectl-get-all.yaml`.

---

## Storage

Each worker node has an external USB drive mounted at `/media/data_ext`. Longhorn uses `/media/data_ext/longhorn` as its default data path. The control-plane node (`rpi001`) does not participate in Longhorn storage; Homebridge data lives at `/home/pi/homebridge` on the SD card (USB mount is not enabled on rpi001).

> ⚠️ **Important:** The USB mounts on worker nodes were set up manually and are **not yet managed by Ansible** (see `docs/reviews/2026-06-26-repo-and-apps-review.md`, Parker finding F-02). `ansible/inventory/group_vars/all.yml` still shows `mount_usb: false` and `mount_usb_mount_path: /media/data`. Do not run `adopt.yml` with `allow_disruptive=true` for storage until these values are aligned with the live paths.

| Node | Device | Mount Point | Filesystem | Capacity | Purpose | How Managed |
|---|---|---|---|---|---|---|
| `rpi001` | n/a | `/home/pi/homebridge` (SD card) | TODO | TODO | Homebridge container data | Not Ansible-managed for USB |
| `rpi002` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 (TODO — verify with `lsblk -f`) | TODO | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| `rpi003` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 (TODO — verify with `lsblk -f`) | TODO | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| `rpi004` | `/dev/sda` → `/dev/sda1` | `/media/data_ext` | ext4 (TODO — verify with `lsblk -f`) | TODO | Longhorn default data path: `/media/data_ext/longhorn` | Manual (not yet Ansible-managed) |
| all nodes | — | `/clusterfs` | — | — | Ansible-provisioned shared cluster directory (purpose TBD) | Ansible `storage` role |

**Off-cluster NAS (Longhorn backup target):** `192.168.52.100` — NFS share at `/rpi/longhorn/`. Not managed by this repo.

---

## Network

All nodes are on a single flat `/24` LAN with no VLAN segmentation between cluster nodes. The router/DHCP server is a Ubiquiti UDM-Pro.

| Item | Value | Source |
|---|---|---|
| LAN subnet | `192.168.52.0/24` | Inferred from node IPs |
| Router / DHCP | Ubiquiti UDM-Pro | `platform/metallb/helm-values.yaml`, `docs/runbooks/break-glass.md` |
| k3s API endpoint | `https://192.168.52.110:6443` | `ansible/roles/k3s_agent/defaults/main.yml` |
| DNS fallback (nodes) | `8.8.8.8`, `8.8.4.4` | `ansible/inventory/group_vars/all.yml` |
| Networking interface management | NetworkManager (Bookworm default) | `ansible/roles/base/tasks/main.yml` |
| MetalLB mode | Layer 2 (gratuitous ARP) | `platform/metallb/l2advertisement.yml` |
| NAS (NFS backup) | `192.168.52.100` | `platform/longhorn/helm-values.yaml` |
| Hostname suffix | `themartinez.cloud` | `components/cluster-config/kustomization.yml` |

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

The following details were not available in the committed codebase at the time of this writing. Brandon should fill these in — run the listed commands on the live cluster or nodes to retrieve the values.

| Item | How to confirm | Why it matters |
|---|---|---|
| **RAM per node** | `kubectl get nodes -o wide` or `ansible all -m setup -a 'filter=ansible_memtotal_mb'` | Capacity planning for pod scheduling; monitoring stack is RAM-hungry |
| **Pi 4B hardware revision per node** (rev 1.1 / 1.2 / 1.4 / 1.5) | `cat /proc/cpuinfo \| grep Revision` on each node | May affect USB 3 vs USB 2 bus speed for storage I/O |
| **SD card make/model and size per node** | `lsblk /dev/mmcblk0` | Local-path provisioner capacity; boot drive reliability |
| **USB drive make/model and capacity per worker node** (rpi002, rpi003, rpi004) | `lsblk -o NAME,SIZE,MODEL /dev/sda` on each worker | Critical for Longhorn I/O tuning; SSD vs HDD changes optimal rebuild concurrency and timeout settings |
| **Whether rpi001 has a USB drive** | `lsblk` on rpi001 | `mount_usb: false` currently; Homebridge data is on SD card; confirm if a USB drive exists for future migration |
| **Live filesystem type on `/media/data_ext`** | `lsblk -f /dev/sda` on rpi002/003/004 | Ansible defaults suggest ext4 but mounts were set up manually |
| **k3s version currently deployed** | `k3s --version` on any node | Needed for upgrade planning and confirming Traefik version (CRD API group) |
| **Raspberry Pi OS image version and date** | `cat /etc/os-release` on each node | Confirm all nodes are at the same Bookworm release; affects cgroup path (`/boot/firmware/cmdline.txt` vs `/boot/cmdline.txt`) |
| **Network speed per node** | `ethtool eth0` on each node | Pi 4B has gigabit on-board; confirm switch/cables are gigabit; affects Longhorn replica traffic and NFS backup throughput |
| **WMI exporter IP address** | Owner knowledge | Referenced in `docs/variable-inventory.md` as `WMI_IP_ADDRESS` for Windows-exporter Prometheus scrape; not committed to the repo |
| **UDM-Pro DHCP exclusion range** | UDM-Pro admin console | Must not overlap with MetalLB VIPs (`.53`, `.80`, `.81`); document here once confirmed |

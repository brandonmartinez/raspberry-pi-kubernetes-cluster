# raspberry-pi-kubernetes-cluster

A production-grade home lab Kubernetes cluster running on Raspberry Pi 4B
devices using [k3s](https://k3s.io). The cluster hosts home network
infrastructure (DNS, NTP, monitoring) and public-facing services (URL shortener,
uptime monitoring) with TLS, high availability, and automated deployment.

The project is divided into two parts:

- **`rpi/`** — One-time provisioning scripts that prepare a fresh Raspberry Pi
  OS install as a k3s master or worker node. Run in order with `sudo` on each
  device; see [`rpi/README.md`](rpi/README.md) for step-by-step instructions.
- **`k8s/`** — Kubernetes manifests and Helm values that define all cluster
  services. Deployed via `k8s/src/deploy.sh` (or `deploy-from-local.sh` from a
  workstation). See [`k8s/README.md`](k8s/README.md) for the full service
  catalog.

## Prerequisites

- At least two
  [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)'s
  (8 GB models recommended)
- [Raspberry Pi OS (64-bit, Lite)](https://www.raspberrypi.com/software/operating-systems/)
  written to a Micro SD card
- Static IP reservations for all nodes (MAC-based via DHCP/router)
- An [SSH key](https://www.ssh.com/academy/ssh/keygen) for passwordless login
- SSH enabled on first boot (`touch /Volumes/bootfs/ssh` on macOS, or enable via
  Raspberry Pi Imager)
- Recommended: a domain name you control (otherwise `.home.arpa` works)

## Getting started

1. Clone the repository onto each Raspberry Pi:

   ```sh
   mkdir -p ~/src && cd ~/src
   git clone https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git
   cd raspberry-pi-kubernetes-cluster
   ```

2. Copy the sample environment file and customize it for your network:

   ```sh
   cp .env.sample .env
   nano .env
   ```

   The `.env` file powers both the provisioning scripts (`rpi/src/`) and the
   Kubernetes deployments (`k8s/src/`). Keep real secrets out of source control
   and document any new variables in `.env.sample`.

3. On every node, run the numbered scripts in `rpi/src/` with `sudo`, rebooting
   when prompted. Script `004.sh` installs k3s — run it without arguments on the
   master and with `PRIMARY_IP` and `TOKEN` arguments on workers. See
   [`rpi/README.md`](rpi/README.md) for detailed steps.

4. After the cluster is ready, deploy services:
   - **From the master node:**
     `cd ~/src/raspberry-pi-kubernetes-cluster/rpi/src/ && sudo ./005.sh`
   - **From a workstation:** `cd k8s/src && ./deploy-from-local.sh` (fetches the
     live kubeconfig via SCP and runs `deploy.sh`)

   `deploy.sh` assembles a temporary `kustomization.yml`, renders manifests with
   `kubectl kustomize | envsubst`, and applies them. Literal `$` characters in
   YAML are preserved by writing `${DOLLAR}` in source files.

## Resources

- [k3s documentation](https://docs.k3s.io)
- [k3s.rocks](https://k3s.rocks)
- [kube-prometheus-stack upgrades](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/UPGRADE.md)

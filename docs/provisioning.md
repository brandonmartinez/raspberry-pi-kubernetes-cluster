# Provisioning

Provisioning is moving from manual `rpi/src/00X.sh` scripts to Ansible. The legacy scripts remain useful context, but new work should model the node state in `ansible/`.

## Model

- `provision.yml`: fresh-node setup for new Raspberry Pi OS installs (verify path/playbook exists before running).
- `adopt.yml`: read-mostly convergence for live nodes (verify path/playbook exists before running).
- Run adoption with `--check --diff`, `serial: 1`, no automatic reboot, and guards around the existing k3s services.
- Keep changes additive; do not interrupt the live cluster.

## Roles

| Role | Purpose |
| --- | --- |
| `base` | Hostname, users, packages, DNS fallback, Raspberry Pi/kernel basics. |
| `storage` | USB mount setup, `/etc/fstab`, Longhorn/local-path directories. |
| `k3s_server` | Control-plane k3s install and server flags. |
| `k3s_agent` | Worker join using the server URL/token. |
| `node_docker` | Docker/Compose support for services still outside k3s. |

## Legacy script mapping

- `001.sh`: hostname, `pi` password, filesystem expansion, optional USB format/mount/fstab.
- `002.sh`: temporary public DNS, OS upgrade, Docker install.
- `003.sh`: Docker group/Compose, DNS utilities, `/clusterfs`, iSCSI, boot cgroups, avahi removal.
- `004.sh`: NFS client plus k3s server or worker install; Helm on the server.
- `005.sh`: master taints/labels, Longhorn directory, legacy `k8s/src/deploy.sh`, Docker watchtower/homebridge.

These scripts are retired by Ansible; do not extend them for new cluster state.

## Bookworm fixes to preserve

- NetworkManager DNS behavior must avoid circular dependency on Pi-hole during bootstrap/adoption.
- Prefer the distro Docker Compose plugin over the legacy `pip3 install docker-compose` pattern.
- Use Debian `nobody:nogroup` ownership syntax, not distro-specific variants.

## Prerequisites

- SSH access from the operator host to every node.
- Passwordless sudo or a known become password.
- Ansible inventory under `ansible/inventory/` with master/worker groups (verify live names/IPs).
- Ansible Vault or another safe channel for join tokens and privileged values.
- Public DNS fallback configured before touching Pi-hole-dependent nodes.

## Example commands

```sh
# Dry-run live adoption, one host at a time.
ansible-playbook -i ansible/inventory/hosts.yml ansible/adopt.yml --check --diff --limit rpi001

# Fresh provision once inventory and vault values are ready.
ansible-playbook -i ansible/inventory/hosts.yml ansible/provision.yml --ask-become-pass
```

If a task wants to restart k3s, reboot, change storage paths, or rewrite DNS, stop and use [runbooks/break-glass.md](runbooks/break-glass.md).

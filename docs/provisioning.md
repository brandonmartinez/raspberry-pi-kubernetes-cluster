# Provisioning

Provisioning is moving from manual `rpi/src/00X.sh` scripts to Ansible. The legacy scripts remain useful context, but new work should model the node state in `ansible/`.

## Model

- `provision.yml`: fresh-node setup for new Raspberry Pi OS installs (verify path/playbook exists before running).
- `adopt.yml`: read-mostly convergence for live nodes (verify path/playbook exists before running).
- Run adoption with `--check --diff`, `serial: 1`, no automatic reboot, and guards around the existing k3s services.
- Keep changes additive; do not interrupt the live cluster.

## Node-local bootstrap (`bootstrap-node.sh`)

`ansible/bootstrap-node.sh` is the node-side entrypoint (ansible-pull style):
copy the one script to a Pi, run it, and it installs Ansible + git, clones/updates
this repo on the node, resolves the node's own inventory name, and runs the
playbook against itself over a **local** connection. The node's inventory group
(`k3s_servers` vs `k3s_agents`) selects the master/worker role automatically — no
per-node edits. Add a node to `ansible/inventory/hosts.yml` first; the script
refuses to run for a host it cannot match.

It is **safe by default**: with no mode flag it runs the read-mostly `adopt.yml`
with `--check --diff` (no changes, no reboot). Disruptive convergence and fresh
provisioning are explicit opt-ins.

```sh
# On the node — read-only check (default), then confirm the role mapping:
sudo ./bootstrap-node.sh
sudo ./bootstrap-node.sh --list-hosts

# Apply gated convergence on a live node (no auto-reboot):
sudo ./bootstrap-node.sh --adopt

# Fresh node only (refuses if k3s already present). Agents need a join token:
sudo K3S_TOKEN=... ./bootstrap-node.sh --provision

# Trial branch / private repo overrides when only the script is staged:
sudo ./bootstrap-node.sh --repo https://github.com/<owner>/<repo>.git --branch main
```

Modes: `--check` (default, read-only adopt), `--adopt` (`allow_disruptive=true`),
`--provision` (fresh node, guarded). Useful flags: `--host NAME`, `--branch REF`,
`--repo URL`, `--dest DIR`, `--no-pull`, `--purge`, `--k3s-token`,
`--admin-pass-hash`, `-e KEY=VAL`. Run `./bootstrap-node.sh --help` for the full
list.

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
- `005.sh`: master taints/labels, Longhorn directory, the legacy deploy pipeline, Docker watchtower/homebridge.

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

These run from an **operator host** with SSH to the nodes. To drive a node from
itself instead, use [`bootstrap-node.sh`](#node-local-bootstrap-bootstrap-nodesh).

```sh
# Dry-run live adoption, one host at a time.
ansible-playbook -i ansible/inventory/hosts.yml ansible/adopt.yml --check --diff --limit rpi001

# Fresh provision once inventory and vault values are ready.
ansible-playbook -i ansible/inventory/hosts.yml ansible/provision.yml --ask-become-pass
```

If a task wants to restart k3s, reboot, change storage paths, or rewrite DNS, stop and use [runbooks/break-glass.md](runbooks/break-glass.md).

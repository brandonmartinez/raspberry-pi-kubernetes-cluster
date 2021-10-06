# raspberry-pi-kubernetes-cluster

A set of scripts to configure a Raspberry Pi 4 as a Kubernetes cluster.

## OS

Scripts in the `OS` folder are meant to be executed in order. Each script
requires a reboot in-between, thus the need for separate files. Scripts must be
executed with `sudo`, and assume a fresh install of Raspberry Pi OS (64-bit) on
a Raspberry Pi 4B with no modifications.

To get started, configure your Raspbery Pi(s) - ideally with SSH keys - and
remote into them. Run the following to pull the repo and execute the scripts:

```sh
git clone https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git
cd raspberry-pi-kubernetes-cluster
sudo ./SetupPiClusterOs-001.sh YourPreferredHostNameForThePi YourPreferredPasswordForThePiUserAccount

# Reboots Pi

sudo ./SetupPiClusterOs-002.sh

# Reboots Pi

sudo ./SetupPiClusterOs-003.sh

# Reboots Pi

# For Master Node:
sudo ./SetupPiClusterOs-004-A.sh

# For Worker Nodes:
sudo ./SetupPiClusterOs-004-B.sh
```

## Services

Pre-reqs:

1. Local install of `kubectl`
2. Local install of `helm`

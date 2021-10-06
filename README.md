# raspberry-pi-kubernetes-cluster

A set of scripts to configure a Raspberry Pi 4 as a Kubernetes cluster.

## OS

Scripts in the `OS` folder are meant to be executed in order. Each script
requires a reboot in-between, thus the need for separate files. Scripts must be
executed with `sudo`, and assume a fresh install of Raspberry Pi OS (64-bit) on
a Raspberry Pi 4B with no modifications besides adding the `ssh` file to the
`boot` volume to enable remote access.

To configure the RPi, login via ssh:

```sh
ssh-copy-id ~/.ssh/id_rsa.pub pi@192.168.1.1 # use your SSH key and the IP of the pi
ssh pi@192.168.1.1 #replace with the IP address of your pi
```

Install git (to pull the repo):

```sh
sudo apt-get install -y git
```

Next, clone this repository:

```sh
# Or wherever you want to store your source code
mkdir src; cd src

# cloning the repo
git clone https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git
cd raspberry-pi-kubernetes-cluster/OS
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

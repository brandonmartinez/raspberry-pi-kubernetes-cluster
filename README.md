# raspberry-pi-kubernetes-cluster

A set of scripts to configure a group of Raspberry Pi 4's as a Kubernetes (k3s)
cluster.

## What's Included

There are multiple services that are installed on the cluster to provide
functionality to any network. More will be added in the future; if you have
suggestions, submit an issue.

### Chrony

[Chrony](https://chrony.tuxfamily.org) is a network time protocol (NTP) client
and server to provided synchronized time across your network and cluster.
Configure servers on your network to point to your cluster's master node IP
address to sync to the cluster's time.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/chrony)

### Deepstack

[Deepstack](https://deepstack.cc) is a deep learning object detection server,
providing a REST-based API for object detection and recognition. Can be used as
a standalone API, or integrated with systems like
[Blue Iris](https://blueirissoftware.com).

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/deepstack)

### kube-prometheus-stack

The
[kube-prometheus-stack](https://github.com/prometheus-operator/kube-prometheus)
is a pre-configured stack of monitoring tools for your Kubernetes cluster. There
are two primary services configured in the `monitoring` namespace:

- [Prometheus](https://prometheus.io): a monitoring and alerting toolkit
  designed to capture metrics from your cluster. It is configured specifically
  for k3s in this deployment (normally it would be k8s-ready).
- [Grafana](https://grafana.com): an observability platform that provides
  dashboards, visualizations, and graphs from multiple data sources. Dashboards
  have been setup specifically for k3s, but it can be configured further within
  the web interface.

[Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
|
[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/prometheus)

### Longhorn

[Longhorn](https://longhorn.io) is a distributed block storage system for
Kubernetes. It allows for the creation of persistent volumes that can be used
from multiple nodes in the cluster by maintaining distributed replicas.

[Helm Chart](https://github.com/longhorn/charts) |
[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/longhorn)

### Minecraft: Bedrock Dedicated Server

A dedicated
[Minecraft Bedrock](https://github.com/TheRemote/MinecraftBedrockServer) server
to help you pass the time and have some fun.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/minecraft)

### Pi-hole

[Pi-hole](https://pi-hole.net) is a DNS-based ad-blocking solution for your
network. It provides a DNS server that can be configured via a web interface to
block ads from publicly available ad lists. The following services are deployed
as part of the `pihole` namespace:

- [Pi-hole](https://pi-hole.net): an HA (highly available) deployment of
  Pi-hole, running 4 instances by default.
- [orbital-sync](https://github.com/mattwebbio/orbital-sync): a service to
  synchronize Pi-hole configurations across multiple instances of Pi-hole using
  the _teleporter_ functionality of Pi-hole.
- [unbound](https://github.com/MatthewVance/unbound-docker-rpi): unbound is a
  validating, recursive, and caching DNS resolver. Paired with pi-hole, it
  provides DNS caching and custom DNS records for your network and your cluster.

[Pi-hole Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/pihole)
|
[orbital-sync Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/orbitalsync)
|
[unbound Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/unbound)

### Portainer

[Portainer](https://www.portainer.io) is a web-based management tool for Docker
and Kubernetes. It provides an interface to manage your cluster, view logs, and
more.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/portainer)

## Prerequisites

- At least two
  [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)'s,
  ideally 4 or 8 GB models
- [Raspberry Pi OS - 64 Bit](https://downloads.raspberrypi.org/raspios_lite_arm64/images/)
  freshly cloned to a Micro SD Card
- Static IP Reservations for All RPi's in the Cluster (suggested to be MAC
  Address based in your router)
- [A userconf file on the boot partition to set default password](https://www.raspberrypi.com/news/raspberry-pi-bullseye-update-april-2022/) -
  see the "Headless Setup" section, or see below for non-Linux OS's
- [ssh file on the boot partition](https://www.raspberrypi.com/documentation/computers/configuration.html#ssh-or-ssh-txt)
  to enable remote access on first boot (e.g., `touch /Volumes/boot/ssh` on
  macOS)
- An [ssh key](https://www.ssh.com/academy/ssh/keygen) to simplify login to
  RPi's (this repo is assuming RSA keys with no password)
- Recommended: a domain name you control (otherwise, .home.arpa will work)

> :warning: **Note:** If you don't have access to a version of `openssl` with the `-6` option (such
> as on macOS), you can use the following command to generate the default `pi`
> username with `raspberry` as the password (though, it's recommended to
> generate a proper username password pair):
>
> ```sh
> echo 'pi:$6$i9XSzPaTyjaCnnKe$fwuKZKF9CYR/vJKVLVusR.NoHQxrj2XSVPK/g7N46RzSaB/9oNmxMXIC3uLIEGV.qg8MYmuJIFAL4ymF4YLeP.' > /Volumes/boot/userconf
> ```

## Configure Raspberry Pi Cluster and Nodes to Execute Scripts

The following steps will need to be executed on every RPi that will be a part of
your cluster.

To configure the RPi, login via ssh:

```sh
ssh-copy-id -i ~/.ssh/id_rsa.pub pi@X.X.X.X # use your SSH key and the IP of the pi
ssh pi@X.X.X.X #replace with the IP address of your pi
```

Install git (to pull the repo):

```sh
sudo apt-get install -y git
```

Next, clone this repository:

```sh
mkdir src; cd src

# cloning the repo
git clone https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster.git
cd raspberry-pi-kubernetes-cluster/

# Copy the .env.sample to a local editable file
cp .env.sample .env

# Edit the new .env file, replacing values with your preferences
# When you're done editing, ctrl+o to save, ctrl+x to quite nano
nano .env

# return home
cd ~
```

## Run Installation Scripts

Scripts in the `src/rpi` folder are meant to be executed in order. Most scripts
require a reboot in-between, thus the need for separate files. Scripts must be
executed with `sudo`.

Time to start executing our scripts.

```sh
# Configuring Hostname and Expanding File System
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./001.sh YourPreferredHostNameForThePi YourPreferredPasswordForThePiUserAccount
# Reboots Pi
```

Reconnect to the RPi with `ssh pi@X.X.X.X`, replacing with your IP address.

```sh
# Update OS Packages and Install Docker
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./002.sh
# Reboots Pi
```

Reconnect to the RPi with `ssh pi@X.X.X.X`, replacing with your IP address.

```sh
# Finish Docker Config and Install Compose; Create NFS Mount Paths; Setup Boot Options
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./003.sh
# Reboots Pi
```

Reconnect to the RPi with `ssh pi@X.X.X.X`, replacing with your IP address.

### Cluster Master

```sh
# For Master Node/Cluster - Install NFS Server and k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004.sh
# Copy the output from the last script, it will be needed for worker nodes
```

Reconnect to the RPi with `ssh pi@X.X.X.X`, replacing with your IP address.

### Cluster Workers

```sh
# For Worker Nodes - Install NFS client, add mount entry, and mount share; install k3s worker node
# X.X.X.X is the IP Address of your master, followed by the token from k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004.sh X.X.X.X "REPLACE WITH TOKEN FROM CLUSTER MASTER"
```

### Deploy Network Services (from Primary Cluster Node)

After all nodes have been setup and configured, run the following on the cluster
master. This will deploy a handful of services to the newly setup Kubernetes
(k3s) cluster.

```sh
cd ~/src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./005.sh
```

## Network Setup

Now that you have a Kubernetes cluster running with network wide services, be
sure to update your router or DHCP server to point to your new Pi-hole DNS
server. Use your primary cluster node's IP address as the DNS server.

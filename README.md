# raspberry-pi-kubernetes-cluster

A set of scripts to configure a Raspberry Pi 4 as a Kubernetes cluster.

## Prerequisites

- At least two
  [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)'s,
  ideally 4 or 8 GB models
- [Raspberry Pi OS - 64 Bit](https://downloads.raspberrypi.org/raspios_lite_arm64/images/)
  freshly cloned to a Micro SD Card
- [A userconf file on the boot partition to set default password](https://www.raspberrypi.com/news/raspberry-pi-bullseye-update-april-2022/) -
  see the "Headless Setup" section, or see below for non-Linux OS's
- [ssh file on the boot partition](https://www.raspberrypi.com/documentation/computers/configuration.html#ssh-or-ssh-txt)
  to enable remote access on first boot (e.g., `touch /Volumes/boot` on macOS)
- An [ssh key](https://www.ssh.com/academy/ssh/keygen) to simplify login to
  RPi's (this repo is assuming RSA keys with no password)
- Pro-Tip: statically assigned IP addresses via your router for each RPi

If you don't have access to a version of `openssl` with the `-6` option (such as
on macOS), you can use the following command to generate the default `pi`
username with `raspberry` as the password (though, it's recommended to generate
a proper username password pair):

```sh
echo 'pi:$6$i9XSzPaTyjaCnnKe$fwuKZKF9CYR/vJKVLVusR.NoHQxrj2XSVPK/g7N46RzSaB/9oNmxMXIC3uLIEGV.qg8MYmuJIFAL4ymF4YLeP.' > /Volumes/boot/userconf
```

## Configure Raspberry Pi Cluster and Nodes to Execute Scripts

The following steps will need to be executed on every RPi that will be a part of
your cluster.

To configure the RPi, login via ssh:

```sh
ssh-copy-id -i ~/.ssh/id_rsa.pub pi@X.X.X.X # use your SSH key and the IP of the pi
ssh pi@X.X.X.X #replace with the IP address of your pi
```

Update the OS and its packages:

```sh
sudo apt update
sudo apt full-upgrade
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

Reconnect to the RPi with `ssh pi@X.X.X.X`, replacing with your IP address. The
next steps will be different based on the primary cluster node vs worker nodes.
Only execute the relevant scripts!

### Primary Cluster Node

```sh
# For Master Node/Cluster - Install NFS Server and k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004-Cluster.sh
# Copy the output from the last script, it will be needed for worker nodes
```

### Worker Nodes

```sh
# For Worker Nodes - Install NFS client, add mount entry, and mount share; install k3s worker node
# X.X.X.X is the IP Address of your master, followed by the token from k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004-Node.sh X.X.X.X "Token from 004-Cluster"
```

### Deploy Network Services (from Primary Cluster Node)

After all nodes have been setup and configured, run the following on the primary
cluster node. This will deploy a handful of services to the newly setup
Kubernetes (k3s) cluster.

```sh
cd ~; cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./005-Cluster.sh
```

## Network Setup

Now that you have a Kubernetes cluster running with network wide services, be
sure to update your router or DHCP server to point to your new Pi-hole DNS
server. Use your primary cluster node's IP address as the DNS server.

## Additional Tips

### Ubiquiti Hardware and DNS

If your Ubiquiti gear (e.g., UDM Pro) is not allowing for local DNS to resolve
properly (such as `*.home.arpa` domains), try creating records via `iptables`
like in this
[guide](https://scotthelme.co.uk/catching-and-dealing-with-naughty-devices-on-my-home-network-v2/).

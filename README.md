# raspberry-pi-kubernetes-cluster

A set of scripts to configure a Raspberry Pi 4 as a Kubernetes cluster.

## Prerequisites

- At least two
  [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)'s,
  ideally 4 or 8 GB models
- [Raspberry Pi OS - 64 Bit](https://downloads.raspberrypi.org/raspios_lite_arm64/images/)
  freshly cloned to a Micro SD Card
- [ssh file on the boot partition](https://www.raspberrypi.com/documentation/computers/configuration.html#ssh-or-ssh-txt)
  to enable remote access on first boot
- An [ssh key](https://www.ssh.com/academy/ssh/keygen) to simplify login to
  RPi's (this repo is assuming RSA keys with no password)
- Pro-Tip: statically assigned IP addresses via your router for each RPi

## Configure Raspberry Pi Cluster and Nodes to Execute Scripts

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

# Edit the new .env file, replacing values with your preferences;
# these will be used in future scripts to avoid passing parameters
# When you're done editing, ctrl+o to save, ctrl+x to quite nano
nano .env
```

## Run Installation Scripts

Scripts in the `src/rpi` folder are meant to be executed in order. Each script
requires a reboot in-between, thus the need for separate files. Scripts must be
executed with `sudo`, and assume a fresh install of Raspberry Pi OS (64-bit) on
a Raspberry Pi 4B with no modifications besides adding the `ssh` file to the
`boot` volume to enable remote access.

And now execute the scripts. Note that in between 1-4, your Pi will
automatically reboot, so your connection will be dropped. Just `ssh pi@X.X.X.X`
again to start the next step.

```sh
# Configuring Hostname and Expanding File System
sudo ./001.sh YourPreferredHostNameForThePi YourPreferredPasswordForThePiUserAccount
# Reboots Pi

# Update OS Packages and Install Docker
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./002.sh
# Reboots Pi

# Finish Docker Config and Install Compose; Create NFS Mount Paths; Setup Boot Options
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./003.sh
# Reboots Pi

# ONLY CHOOSE ONE OF THE FOLLOWING BASED ON MASTER VS WORKER NODE

# For Master Node/Cluster - Install NFS Server and k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004-Cluster.sh

# For Worker Nodes - Install NFS client, add mount entry, and mount share; install k3s worker node
# X.X.X.X is the IP Address of your master, followed by the token from k3s:
cd src/raspberry-pi-kubernetes-cluster/src/rpi/; sudo ./004-Node.sh X.X.X.X "Token from 004-A"
```

## Additional Tips

### Ubiquiti Hardware and DNS

If your Ubiquiti gear (e.g., UDM Pro) is not allowing for local DNS to resolve
properly (such as `*.home.arpa` domains), try creating records via `iptables`
like in this
[guide](https://scotthelme.co.uk/catching-and-dealing-with-naughty-devices-on-my-home-network-v2/).

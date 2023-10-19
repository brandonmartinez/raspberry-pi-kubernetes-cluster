# raspberry-pi-kubernetes-cluster: rpi

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

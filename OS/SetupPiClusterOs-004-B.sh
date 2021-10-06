#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-003.sh                        #
##################################################

PRIMARY_IP=$1
TOKEN=$2

echo "Installing NFS Client and Configuring Cluster Share"
apt install nfs-common -y

echo "$PRIMARY_IP:/clusterfs    /clusterfs   nfs   defaults   0 0" | tee -a /etc/fstab > /dev/null

mount -a

echo "Installing k3s Node"
curl -sfL https://get.k3s.io | K3S_URL=https://$PRIMARY_IP:6443 K3S_TOKEN=$TOKEN sh -
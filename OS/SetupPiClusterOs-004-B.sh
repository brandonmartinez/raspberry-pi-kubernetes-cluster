#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-003.sh                        #
##################################################

PRIMARY_IP=$1
TOKEN=$2

echo "Installing k3s Node"
curl -sfL https://get.k3s.io | K3S_URL=https://$PRIMARY_IP:6443 K3S_TOKEN=$TOKEN sh -
#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-003.sh                        #
##################################################

echo "Installing k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

echo "Finished Installing k3s - Use the Following Token to Add Nodes"
cat /var/lib/rancher/k3s/server/token

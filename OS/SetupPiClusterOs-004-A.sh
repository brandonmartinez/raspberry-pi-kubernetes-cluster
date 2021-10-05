#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-003.sh                        #
##################################################

echo "Installing k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

echo "Enabling Traefik Dashboard"
echo "    dashboard:" | tee -a /var/lib/rancher/k3s/server/manifests/traefik.yaml > /dev/null
echo "      enabled: true" | tee -a /var/lib/rancher/k3s/server/manifests/traefik.yaml > /dev/null

echo "Installing Helm"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Creating Kubernetes Support Directories"
mkdir /var/lib/pihole

echo "Finished Installing k3s - Use the Following Token to Add Nodes"
cat /var/lib/rancher/k3s/server/token

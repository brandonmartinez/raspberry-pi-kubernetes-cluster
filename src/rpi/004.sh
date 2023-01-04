#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

PRIMARY_IP=$1
TOKEN=$2

section "Installing NFS Client and Configuring Cluster Share"
apt install nfs-common -y

# If there's no token, assume on the cluster master
if [ "$TOKEN" = "" ]
then
  section "Installing k3s"
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.24 sh -s - --write-kubeconfig-mode 644 --kube-controller-manager-arg 'bind-address=0.0.0.0' --kube-proxy-arg 'metrics-bind-address=0.0.0.0' --kube-scheduler-arg 'bind-address=0.0.0.0'

  section "Sleeping for 30 Seconds to Wait for k3s"

  sleep 30

  section "Installing Helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  section "Finished Installing k3s - Use the Following Token to Add Nodes"
  cat /var/lib/rancher/k3s/server/token
else
  section "Installing k3s Node"
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.24 K3S_URL=https://$PRIMARY_IP:6443 K3S_TOKEN=$TOKEN sh -s - --kube-proxy-arg 'metrics-bind-address=0.0.0.0'
fi

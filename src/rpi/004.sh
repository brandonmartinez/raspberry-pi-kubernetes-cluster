#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

PRIMARY_IP=$1
TOKEN=$2

# If there's no token, assume on the cluster master
if [ "$TOKEN" != "" ]
then
  section "Installing NFS Server and Exposing Share"
  apt install nfs-kernel-server -y

  GATEWAY_ADDRESS=$(route -n | grep -E '255.*eth0' | grep -o -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
  SUBNET_MASK=$(ip -br -4 addr show | grep eth0 | grep -E -o /[0-9]+)
  FULL_NET_ADDRESS="${GATEWAY_ADDRESS}${SUBNET_MASK}"
  IP_ADDRESS=$(ifconfig eth0 | grep -o -E 'inet [0-9\.]+' | grep -o -E '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')

  echo "/clusterfs      $FULL_NET_ADDRESS(rw,sync,no_root_squash,no_subtree_check)" | tee -a /etc/exports > /dev/null

  exportfs -a

  section "Installing k3s"
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --kube-controller-manager-arg 'bind-address=0.0.0.0' --kube-proxy-arg 'metrics-bind-address=0.0.0.0' --kube-scheduler-arg 'bind-address=0.0.0.0'

  section "Sleeping for 30 Seconds to Wait for k3s"

  sleep 30

  section "Installing Helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  section "Installing NFS Support for k3s"

  tee -a /var/lib/rancher/k3s/server/manifests/nfs.yaml << EOF > /dev/null
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: nfs
  namespace: default
spec:
  chart: nfs-subdir-external-provisioner
  repo: https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
  targetNamespace: default
  set:
    nfs.server: $IP_ADDRESS
    nfs.path: /clusterfs
    storageClass.name: nfs
    storageClass.reclaimPolicy: Retain
EOF

  section "Finished Installing k3s - Use the Following Token to Add Nodes"
  cat /var/lib/rancher/k3s/server/token
else
  section "Installing NFS Client and Configuring Cluster Share"
  apt install nfs-common -y

  echo "$PRIMARY_IP:/clusterfs    /clusterfs   nfs   defaults   0 0" | tee -a /etc/fstab > /dev/null

  mount -a

  section "Installing k3s Node"
  curl -sfL https://get.k3s.io | K3S_URL=https://$PRIMARY_IP:6443 K3S_TOKEN=$TOKEN sh -
fi

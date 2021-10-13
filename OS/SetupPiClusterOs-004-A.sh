#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-003.sh                        #
##################################################

echo "Installing NFS Server and Exposing Share"
apt install nfs-kernel-server -y

GATEWAY_ADDRESS=$(route -n | grep -E '255.*eth0' | grep -o -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
SUBNET_MASK=$(ip -br -4 addr show | grep eth0 | grep -E -o /[0-9]+)
FULL_NET_ADDRESS="${GATEWAY_ADDRESS}${SUBNET_MASK}"
IP_ADDRESS=$(ifconfig eth0 | grep -o -E 'inet [0-9\.]+' | grep -o -E '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')

echo "/clusterfs      $FULL_NET_ADDRESS(rw,sync,no_root_squash,no_subtree_check)" | tee -a /etc/exports > /dev/null

exportfs -a

echo "Installing Additional Tools"
apt install jq avahi-utils -y

echo "Installing k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

echo "Enabling Traefik Dashboard"
echo "    dashboard:" | tee -a /var/lib/rancher/k3s/server/manifests/traefik.yaml > /dev/null
echo "      enabled: true" | tee -a /var/lib/rancher/k3s/server/manifests/traefik.yaml > /dev/null

echo "Installing Helm"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Installing NFS Support for k3s"

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

echo "Finished Installing k3s - Use the Following Token to Add Nodes"
cat /var/lib/rancher/k3s/server/token

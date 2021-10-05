#!/usr/bin/env bash

##################################################
# Before running this script, copy the k3s.yaml  #
# file from the remote cluster. You can do that  #
# from the remote pi with this command:          #
# cat /etc/rancher/k3s/k3s.yaml                  #
# Also, copy the .env.sample to .env and update  #
# the values any of your choosing                #
##################################################

set -e

set -o allexport
source .env
set +o allexport

export KUBECONFIG=$(pwd)/kubeconfig.yml

function apply() {
    echo "Replacing environment variables and applying $1 via kubectl"
    envsubst < $1 | kubectl apply -f -
}

echo "Adding Rancher Local Path Provisioner"
# From: https://github.com/rancher/local-path-provisioner/blob/master/README.md#usage
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass "nfs" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Configuring NFS as Default Storage"
kubectl patch storageclass "local-path" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

echo "Applying Portainer"
kubectl apply -n portainer -f https://raw.githubusercontent.com/portainer/k8s/master/deploy/manifests/portainer/portainer-lb.yaml

echo "Applying Namespaces"
apply Services/01-namespaces.yml

echo "Creating DNS Services"
apply Services/02-dns.yml

echo "Creating Pi-Hole Services"
apply Services/03-pihole.yml

echo "Configuring Ingress"
apply Services/04-Ingress.yml

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
chmod 600 "$KUBECONFIG"

YELLOW='\033[1;33m'
GRAY='\033[1;30m'
NC='\033[0m'

function section () {
    echo -e "\n${YELLOW}**************************************************${NC}"
    echo -e $1
    echo -e "${YELLOW}**************************************************${NC}\n"
}

function log () {
    echo -e "${NC}$1${GRAY}"
}

# TODO: https://kustomize.io
function apply () {
    log "Replacing environment variables and applying $1 via kubectl"
    envsubst < Services/$1.yml | kubectl apply -f -
}

##################################################
section "Adding Rancher Local Path Provisioner"
##################################################
# From: https://github.com/rancher/local-path-provisioner/blob/master/README.md#usage
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass "local-path" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

##################################################
section "Setting NFS as the Default Storage Class"
##################################################
kubectl patch storageclass "nfs" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'


##################################################
section "Deploying Service Stacks"
##################################################
log "Creating network services to be consumed by cluster and network-wide resources."

SERVICES_TO_DEPLOY=("portainer" "pihole" "homebridge" "deepstack")

for t in ${SERVICES_TO_DEPLOY[@]}; do
    section "Deploying Service Stack: $t"
    apply $t
done

##################################################
section "Done."
##################################################

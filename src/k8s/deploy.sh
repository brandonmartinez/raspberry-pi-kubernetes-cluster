#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

# Pi-hole password needs to be base64 encoded
PIHOLE_PASSWORD=$(echo $PIHOLE_PASSWORD | base64 -)

# TODO: https://kustomize.io
function apply () {
    log "Replacing environment variables and applying $1 via kubectl"
    envsubst < $1.yml | kubectl apply -f -
}

function deploy() {
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
    section "Assigning homebridge label to $CLUSTER_HOSTNAME"
    ##################################################
    kubectl label nodes $CLUSTER_HOSTNAME homebridge=true --overwrite
    
    ##################################################
    section "Deploying Service Stacks"
    ##################################################
    log "Creating network services to be consumed by cluster and network-wide resources."
    
    SERVICES_TO_DEPLOY=("pihole" "portainer" "homebridge" "deepstack")
    
    for t in ${SERVICES_TO_DEPLOY[@]}; do
        section "Deploying Service Stack: $t"
        apply $t
    done
    
    ##################################################
    section "Done."
    ##################################################
}

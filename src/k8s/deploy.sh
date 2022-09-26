#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

# Pi-hole password needs to be base64 encoded
PIHOLE_PASSWORD=$(echo $PIHOLE_PASSWORD | base64 -)

function deploy() {
    ##################################################
    section "Setting NFS as the Default Storage Class"
    ##################################################
    kubectl patch storageclass "nfs" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    kubectl patch storageclass "local-path" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
    
    ##################################################
    section "Deploying Service Stacks"
    ##################################################
    log "Creating network services to be consumed by cluster and network-wide resources."
    
    kubectl kustomize | envsubst > compiled.yml
    kubectl apply -f compiled.yml

    # ##################################################
    # section "Installing Prometheus Operator Helm Charts (kube-promtheus-stack)"
    # ##################################################

    # helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    # helm repo 
    # helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack
    
    ##################################################
    section "Done."
    ##################################################
}

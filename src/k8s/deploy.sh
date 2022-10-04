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
    section "Installing Prometheus Operator"
    ##################################################
    set +e
    KUBE_PROMETHEUS_STACK_STATUS=$(helm status 'monitoring' --namespace monitoring 2>&1 > /dev/null)
    set -e

    if [[ $KUBE_PROMETHEUS_STACK_STATUS == *"Error"* ]]; then
        log "Adding Prometheus Operator Charts"
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo update

        log "Installing Prometheus Operator"
        helm install -f <(cat bases/prometheus/helm-values.yml | envsubst) 'monitoring' prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
    else
        log "Prometheus Operator already installed, updating release."
        helm upgrade -f <(cat bases/prometheus/helm-values.yml | envsubst) 'monitoring' prometheus-community/kube-prometheus-stack --namespace monitoring
    fi
   
    ##################################################
    section "Deploying Service Stacks"
    ##################################################
    log "Creating network services to be consumed by cluster and network-wide resources."
    
    # This is hack for the prometheus stack, as "$" is used in rules and dashboard definitions
    # When adding new templates, be sure to replace "$" with "${DOLLAR}" to avoid invalid YAML
    export DOLLAR='$'
    kubectl kustomize | envsubst > compiled.yml
    kubectl apply -f compiled.yml
    
    ##################################################
    section "Done."
    ##################################################
}

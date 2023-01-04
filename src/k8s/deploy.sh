#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

# Some secret values need to be base64 encoded
WEBPASSWORD=$(echo $WEBPASSWORD | base64)

function deploy_helm() {
    REPO_ALIAS=$1
    REPO_URI=$2
    RELEASE=$3
    CHART=$4
    HELM_VALUES=$5
    NAMESPACE=$6
    SLEEP_INSTALL=${7:-60}
    SLEEP_UPGRADE=${8:-10}

    set +e
    HELM_RELEASE_STATUS=$(helm status "${RELEASE}" --namespace "${NAMESPACE}" 2>&1 > /dev/null)
    set -e

    if [[ $HELM_RELEASE_STATUS == *"Error"* ]]; then
        log "Adding Helm Chart Repo ${REPO_ALIAS}"
        helm repo add "${REPO_ALIAS}" "${REPO_URI}"
        helm repo update

        log "Installing Helm Chart ${CHART} as ${RELEASE}"
        helm install -f <(cat "${HELM_VALUES}" | envsubst) "${RELEASE}" "${CHART}" --namespace ${NAMESPACE} --create-namespace

        log "Waiting ${SLEEP_INSTALL} seconds for ${RELEASE} to be Ready"
        sleep ${SLEEP_INSTALL}
    else
        helm repo update

        log "Helm Chart ${CHART} already exists; upgrading ${RELEASE} release"
        helm upgrade -f <(cat "${HELM_VALUES}" | envsubst) "${RELEASE}" "${CHART}" --namespace ${NAMESPACE} --create-namespace

        log "Waiting ${SLEEP_UPGRADE} seconds for ${RELEASE} to be Ready"
        sleep ${SLEEP_UPGRADE}
    fi
}

function deploy() {
    if [ "$DEPLOY_LONGHORN" = true ] ; then
        ##################################################
        section "Installing Longhorn Storage Provider"
        ##################################################
        deploy_helm "longhorn" "https://charts.longhorn.io" \
            "longhorn" "longhorn/longhorn" \
            "bases/longhorn/helm-values.yml" \
            "longhorn-system" \
            120

        ##################################################
        section "Setting Longhorn as the Default Storage Class"
        ##################################################
        kubectl patch storageclass "local-path" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
        # kubectl patch storageclass "nfs" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
        kubectl patch storageclass "longhorn" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    fi

    if [ "$DEPLOY_PROMETHEUS" = true ] ; then
        ##################################################
        section "Installing Prometheus Monitoring Stack"
        ##################################################

        deploy_helm "prometheus-community" "https://prometheus-community.github.io/helm-charts" \
            "monitoring" "prometheus-community/kube-prometheus-stack" \
            "bases/prometheus/helm-values.yml" \
            "monitoring"
    fi

    ##################################################
    section "Deploying Service Stacks"
    ##################################################
    log "Creating network services to be consumed by cluster and network-wide resources."

    log "Generating kustomize script"
    echo -e "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nbases:" > kustomization.yml
    echo "- bases/kube-system" >> kustomization.yml

    if [ "$DEPLOY_LONGHORN" = true ] ; then
        echo "- bases/longhorn" >> kustomization.yml
    fi

    if [ "$DEPLOY_PROMETHEUS" = true ] ; then
        echo "- bases/prometheus" >> kustomization.yml
    fi

    if [ "$DEPLOY_PIHOLE" = true ] ; then
        echo "- bases/unbound" >> kustomization.yml
        echo "- bases/pihole" >> kustomization.yml
        echo "- bases/orbitalsync" >> kustomization.yml
    fi

    if [ "$DEPLOY_HOMEBRIDGE" = true ] ; then
        echo "- bases/homebridge" >> kustomization.yml
    fi

    if [ "$DEPLOY_DEEPSTACK" = true ] ; then
        echo "- bases/deepstack" >> kustomization.yml
    fi

    if [ "$DEPLOY_PORTAINER" = true ] ; then
        echo "- bases/portainer" >> kustomization.yml
    fi

    if [ "$DEPLOY_CHRONY" = true ] ; then
        echo "- bases/chrony" >> kustomization.yml
    fi

    if [ "$DEPLOY_MINECRAFT" = true ] ; then
        echo "- bases/minecraft" >> kustomization.yml
    fi

    log "Deploying kustomize script via kubectl"
    # This is hack for the prometheus stack, as "$" is used in rules and dashboard definitions
    # When adding new templates, be sure to replace "$" with "${DOLLAR}" to avoid invalid YAML
    export DOLLAR='$'
    kubectl kustomize | envsubst > compiled.yml
    kubectl apply -f compiled.yml
    
    ##################################################
    section "Done."
    ##################################################
}

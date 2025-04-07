#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../../_shared/echo.sh
set +o allexport

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

    log "Adding Helm Chart Repo ${REPO_ALIAS}"
    helm repo add "${REPO_ALIAS}" "${REPO_URI}"
    helm repo update

    if [[ $HELM_RELEASE_STATUS == *"Error"* ]]; then
        log "Installing Helm Chart ${CHART} as ${RELEASE}"
        helm install -f <(cat "${HELM_VALUES}" | envsubst) "${RELEASE}" "${CHART}" --namespace ${NAMESPACE} --create-namespace

        log "Waiting ${SLEEP_INSTALL} seconds for ${RELEASE} to be Ready"
        sleep ${SLEEP_INSTALL}
    else
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
            "resources/longhorn/helm-values.yml" \
            "longhorn-system" \
            120

        ##################################################
        section "Setting Longhorn as the Default Storage Class"
        ##################################################
        kubectl patch storageclass "local-path" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
        # kubectl patch storageclass "nfs" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
        kubectl patch storageclass "longhorn" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    fi

    if [ "$DEPLOY_CERTMANAGER" = true ] ; then
        ##################################################
        section "Installing Cert Manager Stack"
        ##################################################
        deploy_helm "jetstack" "https://charts.jetstack.io" \
            "cert-manager" "jetstack/cert-manager" \
            "resources/cert-manager/helm-values.yml" \
            "cert-manager" \
            120
    fi

    if [ "$DEPLOY_PROMETHEUS" = true ] ; then
        ##################################################
        section "Installing Prometheus Monitoring Stack"
        ##################################################

        deploy_helm "prometheus-community" "https://prometheus-community.github.io/helm-charts" \
            "monitoring" "prometheus-community/kube-prometheus-stack" \
            "resources/prometheus/helm-values.yml" \
            "monitoring"

        log "Building Grafana Dashboard Kustomize YAML Files from JSON Dashboards"
        for file in resources/prometheus/grafana-dashboards/*.json; do
            base_name=$(basename "$file" .json)
            yml_file="resources/prometheus/grafana-dashboards/${base_name}.yml"
            tmp_file="resources/prometheus/grafana-dashboards/${base_name}.tmp"

            # Create the base template
            echo "apiVersion: v1" > "$yml_file"
            echo "kind: ConfigMap" >> "$yml_file"
            echo "metadata:" >> "$yml_file"
            echo "  name: grafana-$base_name" >> "$yml_file"
            echo "  labels:" >> "$yml_file"
            echo "    grafana_dashboard: \"true\"" >> "$yml_file"
            echo "data:" >> "$yml_file"
            echo "  grafana-$base_name.json: |-" >> "$yml_file"

            # Convert the JSON to YAML
            sed -e 's/\$/\${DOLLAR}/g' -e 's/^/    /' "$file" > "$tmp_file"
            cat "$tmp_file" >> "$yml_file"
            rm -f $tmp_file
        done
    fi

    ##################################################
    section "Deploying Service Stacks"
    ##################################################
    log "Creating network services to be consumed by cluster and network-wide resources."

    log "Generating kustomize script"
    echo -e "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nresources:" > kustomization.yml
    echo "- resources/kube-system" >> kustomization.yml

    if [ "$DEPLOY_SECURITY" = true ] ; then
        echo "- resources/security" >> kustomization.yml
        echo "- resources/longhorn" >> kustomization.yml
    fi

    if [ "$DEPLOY_LOCALPROXY" = true ] ; then
        echo "- resources/localproxy" >> kustomization.yml
    fi

    if [ "$DEPLOY_LONGHORN" = true ] ; then
        echo "- resources/longhorn" >> kustomization.yml
    fi

    if [ "$DEPLOY_PROMETHEUS" = true ] ; then
        echo "- resources/prometheus" >> kustomization.yml
    fi

    if [ "$DEPLOY_UNBOUND" = true ] ; then
        echo "- resources/unbound" >> kustomization.yml
    fi

    if [ "$DEPLOY_PIHOLE" = true ] ; then
        echo "- resources/pihole" >> kustomization.yml
        echo "- resources/nebulasync" >> kustomization.yml
    fi

    if [ "$DEPLOY_HEIMDALL" = true ] ; then
        echo "- resources/heimdall" >> kustomization.yml
    fi

    if [ "$DEPLOY_HOMEBRIDGE" = true ] ; then
        echo "- resources/homebridge" >> kustomization.yml
    fi

    if [ "$DEPLOY_DATA" = true ] ; then
        echo "- resources/data" >> kustomization.yml
    fi

    if [ "$DEPLOY_DEEPSTACK" = true ] ; then
        echo "- resources/deepstack" >> kustomization.yml
    fi

    if [ "$DEPLOY_PORTAINER" = true ] ; then
        echo "- resources/portainer" >> kustomization.yml
    fi

    if [ "$DEPLOY_CHRONY" = true ] ; then
        echo "- resources/chrony" >> kustomization.yml
    fi

    if [ "$DEPLOY_MINECRAFT" = true ] ; then
        echo "- resources/minecraft" >> kustomization.yml
    fi

    if [ "$DEPLOY_PIKARAOKE" = true ] ; then
        echo "- resources/pikaraoke" >> kustomization.yml
    fi

    if [ "$DEPLOY_SHLINK" = true ] ; then
        echo "- resources/shlink" >> kustomization.yml
    fi

    if [ "$DEPLOY_UPTIME" = true ] ; then
        echo "- resources/uptime" >> kustomization.yml
    fi

    log "Deploying kustomize script via kubectl"
    # This is hack for the prometheus stack, as "$" is used in rules and dashboard definitions
    # When adding new templates, be sure to replace "$" with "${DOLLAR}" to avoid invalid YAML
    export DOLLAR='$'
    find resources/ -name ".env.secret" | while read -r secret_file; do
        envsubst < "$secret_file" > "${secret_file}.temp"
    done
    kubectl kustomize | envsubst | sed "s/'''/'/g" > compiled.yml
    kubectl apply -f compiled.yml

    ##################################################
    section "Done."
    ##################################################
}

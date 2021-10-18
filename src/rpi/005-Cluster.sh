#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-004-A.sh                      #
##################################################

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
source ../k8s/deploy.sh
set +o allexport

section "Moving to k8s directory"
cd ../k8s

deploy

section "Moving to .tmp directory"

cd ../../.tmp

section "Deploying carlosedp/cluster-monitoring"

log "Cloning from GitHub"

git clone https://github.com/carlosedp/cluster-monitoring.git

log "Moving into folder cluster-monitoring"

cd cluster-monitoring

log "Substituting pre-setup vars.jsonnet file with local environment variables"
envsubst < ../../src/_misc/monitoring/cluster-monitoring.jsonnet > vars.jsonnet
envsubst < ../../src/_misc/monitoring/wmi_exporter.jsonnet > modules/wmi_exporter.jsonnet
envsubst < ../../src/_misc/monitoring/wmi-dashboard.json > grafana-dashboard/wmi-dashboard.json

log "Building manifests for cluster monitoring"
make docker

log "Deploying manifests"
make deploy

#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
source deploy.sh
set +o allexport

# scp pi@$CLUSTER_HOSTNETWORKINGIPADDRESS:/etc/rancher/k3s/k3s.yaml kubeconfig.yml > /dev/null
# sed -i '' "s/127.0.0.1/$CLUSTER_HOSTNETWORKINGIPADDRESS/g" kubeconfig.yml

export KUBECONFIG=$(pwd)/kubeconfig.yml
chmod 600 "$KUBECONFIG"

deploy

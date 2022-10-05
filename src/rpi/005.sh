#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
source ../k8s/deploy.sh
set +o allexport

section "Adding Taint to Avoid Scheduling on Master"
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule

section "Moving to k8s directory"
cd ../k8s

deploy

section "Starting HomeBridge in Docker"

mkdir /clusterfs/homebridge

docker run -d \
    --restart unless-stopped \
    --net=host --name=homebridge \
    -e PGID=1000 -e PUID=1000 -e HOMEBRIDGE_CONFIG_UI=1 -e HOMEBRIDGE_CONFIG_UI_PORT=8081 -e TZ=America/Detroit \
    -v /clusterfs/homebridge:/homebridge oznu/homebridge:latest

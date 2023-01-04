#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
source ../k8s/deploy.sh
set +o allexport

section "Addings Taint to Avoid Scheduling on Master Node"
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/control-plane:NoSchedule --overwrite
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule --overwrite
kubectl taint nodes $CLUSTER_HOSTNAME cattle.io/os=linux:NoSchedule --overwrite

section "Adding ipv4Only Label to Cluster Master Node"
kubectl label nodes $CLUSTER_HOSTNAME ipv4Only=true --overwrite

section "Moving to k8s directory"
cd ../k8s

mkdir -p "$LONGHORN_DATAPATH"

deploy

section "Starting HomeBridge in Docker"

HOMEBRIDGE_DATA_DIRECTORY="/home/pi/homebridge"

if [ "$MOUNT_USB" = true ] ; then
    HOMEBRIDGE_DATA_DIRECTORY="$MOUNT_USB_MOUNT_PATH/homebridge"
fi

mkdir -p "$HOMEBRIDGE_DATA_DIRECTORY"

docker run -d \
    --restart unless-stopped \
    --net=host --name=homebridge \
    -e PGID=1000 -e PUID=1000 -e HOMEBRIDGE_CONFIG_UI=1 -e HOMEBRIDGE_CONFIG_UI_PORT=8081 -e TZ=America/Detroit \
    -v "$HOMEBRIDGE_DATA_DIRECTORY:/homebridge" oznu/homebridge:latest

#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
source ../../k8s/src/deploy.sh
set +o allexport

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

section "Addings Taint to Avoid Scheduling on Master Node"
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/control-plane:NoSchedule --overwrite
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule --overwrite
if [ "$MOUNT_USB" = false ] ; then
    kubectl taint nodes $CLUSTER_HOSTNAME cattle.io/os=linux:NoSchedule --overwrite
fi

section "Adding ipv4Only Label to Cluster Master Node"
kubectl label nodes $CLUSTER_HOSTNAME ipv4Only=true --overwrite

section "Moving to k8s directory"
cd ../k8s

mkdir -p "$LONGHORN_DATAPATH"

deploy

section "Starting Watchtower to Keep Docker Images Updated"

docker run -d \
  --name watchtower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower:latest \
  --interval 3600 --cleanup

section "Starting HomeBridge in Docker"

HOMEBRIDGE_DATA_DIRECTORY="/home/pi/homebridge"

if [ "$MOUNT_USB" = true ] ; then
    HOMEBRIDGE_DATA_DIRECTORY="$MOUNT_USB_MOUNT_PATH/homebridge"
fi

mkdir -p "$HOMEBRIDGE_DATA_DIRECTORY"

docker run -d \
    --restart unless-stopped \
    --net=host --name=homebridge \
    -e PGID=1000 -e PUID=1000 -e HOMEBRIDGE_CONFIG_UI=1 -e HOMEBRIDGE_CONFIG_UI_PORT=8581 -e TZ=America/Detroit \
    -v "$HOMEBRIDGE_DATA_DIRECTORY:/homebridge" oznu/homebridge:latest

section "Starting Scrypted in Docker"

SCRYPTED_DATA_DIRECTORY="/home/pi/scrypted"

if [ "$MOUNT_USB" = true ] ; then
    SCRYPTED_DATA_DIRECTORY="$MOUNT_USB_MOUNT_PATH/scrypted"
fi

mkdir -p "$SCRYPTED_DATA_DIRECTORY"

docker run -d \
    --restart unless-stopped \
    --net=host --name=scrypted \
    -e PGID=1000 -e PUID=1000 -e TZ=America/Detroit \
    -v "$SCRYPTED_DATA_DIRECTORY:/server/volume" koush/scrypted:latest


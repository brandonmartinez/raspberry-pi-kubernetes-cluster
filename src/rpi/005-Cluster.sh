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

section "Adding Taint to Avoid Scheduling on Master"
kubectl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule

section "Moving to k8s directory"
cd ../k8s

deploy

section "Starting HomeBridge in Docker"

mkdir /clusterfs/homebridge

docker run -d --restart unless-stopped --net=host --name=homebridge -v /clusterfs/homebridge:/homebridge oznu/homebridge:latest

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
kubektl taint nodes $CLUSTER_HOSTNAME node-role.kubernetes.io/master:NoSchedule

section "Moving to k8s directory"
cd ../k8s

deploy

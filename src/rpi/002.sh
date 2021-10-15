#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-001.sh                        #
##################################################

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

section "Updating Packages"
apt-get update && apt-get -y upgrade

section "Installing Docker"
curl -sSL https://get.docker.com | sh
reboot

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

section "Setting DNS to CloudFlare to Avoid Circular DNS"
sed -i "s/#static domain_name_servers=192.168.1.1/static domain_name_servers=1.1.1.1 1.0.0.1/g" /etc/dhcpcd.conf
systemctl daemon-reload
service dhcpcd restart

section "Updating Packages"
apt-get update && apt-get -y upgrade

section "Installing Docker"
curl -sSL https://get.docker.com | sh
reboot

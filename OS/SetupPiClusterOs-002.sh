#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-001.sh                        #
##################################################

echo "Updating Packages"
apt-get update && apt-get -y upgrade

echo "Installing Docker"
curl -sSL https://get.docker.com | sh
reboot

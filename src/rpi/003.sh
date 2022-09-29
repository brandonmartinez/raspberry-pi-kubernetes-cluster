#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-002.sh                        #
##################################################

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

section "Adding pi User to Docker Group"
usermod -aG docker pi

section "Installing Docker Compose"
apt-get install -y libffi-dev libssl-dev
apt-get install -y python3 python3-pip
# apt-get remove python-configparser
pip3 -v install docker-compose

section "Installing DNS Utils"
apt-get install -y dnsutils

section "Creating Shared Storage Area"
mkdir /clusterfs
chown nobody.nogroup -R /clusterfs
chmod 777 -R /clusterfs

section "Adding Boot Options"
sed -i "s/rootwait/rootwait cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/g" /boot/cmdline.txt
# disabling ipv6 for better homebridge support per https://github.com/homebridge/homebridge/issues/2089
sed -i "s/use-ipv6=yes/use-ipv6=no/g" /etc/avahi/avahi-daemon.conf
sed -i "s/#allow-interfaces=eth0/allow-interfaces=eth0/g" /etc/avahi/avahi-daemon.conf

section "Rebooting"
reboot

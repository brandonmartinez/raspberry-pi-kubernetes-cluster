#!/usr/bin/env bash

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

section "Installing iSCSI"
apt-get install -y open-iscsi

section "Removing avahi-daemon to avoid conflicts with HomeBridge"
apt remove avahi-daemon -y

section "Adding Boot Options"

IS_CLUSTER_MASTER=$(ifconfig | grep ${CLUSTER_HOSTNETWORKINGIPADDRESS})

BOOT_OPTIONS_TO_ADD="rootwait cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1"

if [ "$IS_CLUSTER_MASTER" != "" ]
then
    log "Current node is the cluster master, disabling IPv6 for Homebridge"
    BOOT_OPTIONS_TO_ADD="${BOOT_OPTIONS_TO_ADD} ipv6.disable=1"
fi

sed -i "s/rootwait/${BOOT_OPTIONS_TO_ADD}/g" /boot/cmdline.txt

section "Rebooting"
reboot

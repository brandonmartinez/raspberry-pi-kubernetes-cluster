#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set run #
# SetupPiClusterOs-002.sh                        #
##################################################

echo "Adding pi User to Docker Group"
usermod -aG docker pi

echo "Installing Docker Compose"
apt-get install -y libffi-dev libssl-dev
apt-get install -y python3 python3-pip
apt-get remove python-configparser
pip3 -v install docker-compose

echo "Adding Boot Options"
sed -i "s/rootwait/rootwait cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/g" /boot/cmdline.txt

echo "Rebooting"
reboot

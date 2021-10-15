#!/usr/bin/env bash

##################################################
# Before running this script, be sure to set the #
# static IP address of the Pi, upload your SSH   #
# key to it, and connect for the first time.     #
# ssh-copy-id -i ~/.ssh/id_rsa.pub pi@X.X.X.X    #
##################################################

set -e

HOSTNAME=$1
PASSWORD=$2

echo "Setting Pi Hostname"
echo $HOSTNAME | tee /etc/hostname > /dev/null
sed -i "s/127.0.1.1.*raspberrypi/127.0.1.1\t$HOSTNAME/g" /etc/hosts
hostname -b "$HOSTNAME"

echo "Setting Pi Password"
(echo $PASSWORD; echo $PASSWORD) | passwd pi

echo "Expanding File System"
raspi-config --expand-rootfs

echo "Rebooting"
reboot

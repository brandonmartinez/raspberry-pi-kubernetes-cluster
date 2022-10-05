#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

HOSTNAME=$1
PASSWORD=$2

section "Setting Pi Hostname"
echo $HOSTNAME | tee /etc/hostname > /dev/null
sed -i "s/127.0.1.1.*raspberrypi/127.0.1.1\t$HOSTNAME/g" /etc/hosts
hostname -b "$HOSTNAME"

section "Setting Pi Password"
(echo $PASSWORD; echo $PASSWORD) | passwd pi

section "Expanding File System"
raspi-config --expand-rootfs

section "Rebooting"
reboot

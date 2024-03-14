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

if [ "$MOUNT_USB" = true ] ; then
    if [ "$MOUNT_USB_DRIVE_FORMAT" = true ] ; then
        section "Formatting attached USB Drive $MOUNT_USB_DRIVE_PATH with GPT partition table and ext4 volume"
        wipefs -af "$MOUNT_USB_DRIVE_PATH"
        sgdisk -n 0:0:0 -t 0:8300 -c 0:data "$MOUNT_USB_DRIVE_PATH"

        mkfs.ext4 -F "${MOUNT_USB_DRIVE_PATH}1"
    fi

    section "Mounting attached USB Drive ${MOUNT_USB_DRIVE_PATH}1 to $MOUNT_USB_MOUNT_PATH"
    mkdir -p "$MOUNT_USB_MOUNT_PATH"
    mount "${MOUNT_USB_DRIVE_PATH}1" "$MOUNT_USB_MOUNT_PATH"

    section "Setting up FSTAB entry for USB Drive"
    MOUNT_USB_UUID=$(lsblk -no UUID "${MOUNT_USB_DRIVE_PATH}1")
    echo "UUID=$MOUNT_USB_UUID $MOUNT_USB_MOUNT_PATH ext4 defaults,auto,users,rw,exec,nofail 0 0" | tee -a /etc/fstab
fi

section "Rebooting"
reboot

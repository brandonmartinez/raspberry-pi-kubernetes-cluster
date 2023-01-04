#!/usr/bin/env bash

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
apt update && apt full-upgrade -y

section "Installing Docker"
apt install apt-transport-https ca-certificates curl gnupg lsb-release -y
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
apt -y install docker-ce docker-ce-cli containerd.io

reboot

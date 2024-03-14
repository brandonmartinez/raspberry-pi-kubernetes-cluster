#!/usr/bin/env bash

set -e

set -o allexport
source ../../.env
source ../_shared/echo.sh
set +o allexport

PRIMARY_IP=$1
TOKEN=$2

section "Installing NFS Client and Configuring Cluster Share"
apt install nfs-common -y

# If there's no token, assume on the cluster master
if [ "$TOKEN" = "" ]
then
  section "Installing k3s"
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - --write-kubeconfig-mode 644 --kube-controller-manager-arg 'bind-address=0.0.0.0' --kube-proxy-arg 'metrics-bind-address=0.0.0.0' --kube-scheduler-arg 'bind-address=0.0.0.0' --prefer-bundled-bin

  section "Sleeping for 30 Seconds to Wait for k3s"

  sleep 30

  section "Installing Helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  section "Finished Installing k3s - Use the Following Token to Add Nodes"
  cat /var/lib/rancher/k3s/server/token
else
  section "Installing k3s Node"
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable K3S_URL=https://$PRIMARY_IP:6443 K3S_TOKEN=$TOKEN sh -s - --kube-proxy-arg 'metrics-bind-address=0.0.0.0'
fi

# Doing this after k3s setup to ensure that directories are created
if [ "$MOUNT_USB_STORE_CONTAINERS" = true ] ; then
  section "Configuring k3s to store data on external drive"

  K3S_EXT_DATA_DIR="$MOUNT_USB_MOUNT_PATH/k3s"
  K3S_EXT_DATA_RUN_DIR="$K3S_EXT_DATA_DIR/run"
  K3S_EXT_DATA_PODS_DIR="$K3S_EXT_DATA_DIR/pods"
  K3S_EXT_DATA_RANCHER_DIR="$K3S_EXT_DATA_DIR/rancher"
  mkdir -p "$K3S_EXT_DATA_DIR"

  if [ "$TOKEN" = "" ]
    systemctl stop k3s
  else
    systemctl stop k3s-agent
  fi
  /usr/local/bin/k3s-killall.sh

  mv /run/k3s/ "$K3S_EXT_DATA_RUN_DIR/"
  mv /var/lib/kubelet/pods/ "$K3S_EXT_DATA_PODS_DIR/"
  mv /var/lib/rancher/ "$K3S_EXT_DATA_RANCHER_DIR/"

  ln -s "$K3S_EXT_DATA_RUN_DIR/" /run/k3s
  ln -s "$K3S_EXT_DATA_PODS_DIR/" /var/lib/kubelet/pods
  ln -s "$K3S_EXT_DATA_RANCHER_DIR/" /var/lib/rancher

  if [ "$TOKEN" = "" ]
    systemctl start k3s
  else
    systemctl start k3s-agent
  fi

  section "Configuring docker to store data on external drive"

  systemctl stop docker
  systemctl stop docker.socket
  systemctl stop containerd

  DOCKER_EXT_DATA_DIR="$MOUNT_USB_MOUNT_PATH/docker"
  mv /var/lib/docker "$DOCKER_EXT_DATA_DIR"

  echo "{'data-root': '$DOCKER_EXT_DATA_DIR'}" | tee -a /etc/docker/daemon.json

  # if the following fails, try `sudo dockerd`` to see what the output is then try again
  systemctl start docker
fi

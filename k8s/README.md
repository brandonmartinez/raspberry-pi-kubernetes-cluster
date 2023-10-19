# raspberry-pi-kubernetes-cluster: k8s

## What's Included

There are multiple services that are installed on the cluster to provide
functionality to any network. More will be added in the future; if you have
suggestions, submit an issue.

### Chrony

[Chrony](https://chrony.tuxfamily.org) is a network time protocol (NTP) client
and server to provided synchronized time across your network and cluster.
Configure servers on your network to point to your cluster's master node IP
address to sync to the cluster's time.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/chrony)

### Deepstack

[Deepstack](https://deepstack.cc) is a deep learning object detection server,
providing a REST-based API for object detection and recognition. Can be used as
a standalone API, or integrated with systems like
[Blue Iris](https://blueirissoftware.com).

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/deepstack)

### kube-prometheus-stack

The
[kube-prometheus-stack](https://github.com/prometheus-operator/kube-prometheus)
is a pre-configured stack of monitoring tools for your Kubernetes cluster. There
are two primary services configured in the `monitoring` namespace:

- [Prometheus](https://prometheus.io): a monitoring and alerting toolkit
  designed to capture metrics from your cluster. It is configured specifically
  for k3s in this deployment (normally it would be k8s-ready).
- [Grafana](https://grafana.com): an observability platform that provides
  dashboards, visualizations, and graphs from multiple data sources. Dashboards
  have been setup specifically for k3s, but it can be configured further within
  the web interface.

[Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
|
[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/prometheus)

### Longhorn

[Longhorn](https://longhorn.io) is a distributed block storage system for
Kubernetes. It allows for the creation of persistent volumes that can be used
from multiple nodes in the cluster by maintaining distributed replicas.

[Helm Chart](https://github.com/longhorn/charts) |
[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/longhorn)

### Minecraft: Bedrock Dedicated Server

A dedicated
[Minecraft Bedrock](https://github.com/TheRemote/MinecraftBedrockServer) server
to help you pass the time and have some fun.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/minecraft)

### Pi-hole

[Pi-hole](https://pi-hole.net) is a DNS-based ad-blocking solution for your
network. It provides a DNS server that can be configured via a web interface to
block ads from publicly available ad lists. The following services are deployed
as part of the `pihole` namespace:

- [Pi-hole](https://pi-hole.net): an HA (highly available) deployment of
  Pi-hole, running 4 instances by default.
- [orbital-sync](https://github.com/mattwebbio/orbital-sync): a service to
  synchronize Pi-hole configurations across multiple instances of Pi-hole using
  the _teleporter_ functionality of Pi-hole.
- [unbound](https://github.com/MatthewVance/unbound-docker-rpi): unbound is a
  validating, recursive, and caching DNS resolver. Paired with pi-hole, it
  provides DNS caching and custom DNS records for your network and your cluster.

[Pi-hole Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/pihole)
|
[orbital-sync Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/orbitalsync)
|
[unbound Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/unbound)

### Portainer

[Portainer](https://www.portainer.io) is a web-based management tool for Docker
and Kubernetes. It provides an interface to manage your cluster, view logs, and
more.

[Kubernetes Manifests](https://github.com/brandonmartinez/raspberry-pi-kubernetes-cluster/tree/main/src/k8s/bases/portainer)
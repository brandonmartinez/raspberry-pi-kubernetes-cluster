# raspberry-pi-kubernetes-cluster: k8s

## What's Included

There are multiple services installed on the cluster to provide core
infrastructure and network applications. Use the root `.env` toggles (see
`.env.sample`) to control what gets deployed via `k8s/src/deploy.sh`.

### cert-manager

[cert-manager](https://cert-manager.io) automates TLS certificate provisioning
for Ingress resources.

[Helm Values](src/resources/cert-manager/helm-values.yml)

### ChangeDetection.io

[ChangeDetection.io](https://github.com/dgtlmoon/changedetection.io) monitors
web pages for changes and sends alerts when updates are detected.

[Kubernetes Manifests](src/resources/changedetection)

### Chrony

[Chrony](https://chrony.tuxfamily.org) is a network time protocol (NTP) client
and server to provide synchronized time across your network and cluster.
Configure servers on your network to point to your cluster's master node IP
address to sync to the cluster's time.

[Kubernetes Manifests](src/resources/chrony)

### Data (PostgreSQL + PgBouncer)

PostgreSQL is the shared database for cluster services, with PgBouncer providing
connection pooling.

[Kubernetes Manifests](src/resources/data)

### Descheduler

The Kubernetes [Descheduler](https://github.com/kubernetes-sigs/descheduler)
evicts pods to help rebalance cluster workloads based on policy.

[Helm Values](src/resources/descheduler/helm-values.yml)

[Kubernetes Manifests](src/resources/homebridge)

### kube-system addons

K3s metrics service plumbing for Prometheus scraping.

[Kubernetes Manifests](src/resources/kube-system)

### kube-prometheus-stack

The
[kube-prometheus-stack](https://github.com/prometheus-operator/kube-prometheus)
is a pre-configured stack of monitoring tools for your Kubernetes cluster. There
are two primary services configured in the `monitoring` namespace:

- [Prometheus](https://prometheus.io): a monitoring and alerting toolkit
  designed to capture metrics from your cluster, tuned for k3s.
- [Grafana](https://grafana.com): an observability platform that provides
  dashboards, visualizations, and graphs from multiple data sources.

[Helm Values](src/resources/monitoring/helm-values.yml) |
[Kubernetes Manifests](src/resources/monitoring)

### Local proxy

Reverse proxy for LAN-hosted services, exposed through cluster Ingress.

[Kubernetes Manifests](src/resources/localproxy)

### Longhorn

[Longhorn](https://longhorn.io) is a distributed block storage system for
Kubernetes. It allows the creation of persistent volumes that can be used from
multiple nodes by maintaining distributed replicas.

[Helm Values](src/resources/longhorn/helm-values.yml) |
[Kubernetes Manifests](src/resources/longhorn)

### Minecraft: Bedrock Dedicated Server

A dedicated
[Minecraft Bedrock](https://github.com/TheRemote/MinecraftBedrockServer) server
to help you pass the time and have some fun.

[Kubernetes Manifests](src/resources/minecraft)

### Nebula Sync

[Nebula Sync](https://github.com/lovelaze/nebula-sync) runs scheduled sync jobs
for personal media libraries.

[Kubernetes Manifests](src/resources/nebulasync)

### Pi-hole

[Pi-hole](https://pi-hole.net) is a DNS-based ad-blocking solution for your
network. It provides a DNS server that can be configured via a web interface to
block ads from publicly available ad lists. The deployment flushes FTL metrics
to disk every 15 minutes and trims historical data to seven days to minimize
SQLite contention; adjust `FTLCONF_database_DBinterval` and
`FTLCONF_database_maxDBdays` in `k8s/src/resources/pihole/.env` if you need
different retention, and use `FTLCONF_dns_rateLimit_count` /
`FTLCONF_dns_rateLimit_interval` to tune per-client query throttling. Upstream
resolution defaults to the in-cluster Unbound service using
`FTLCONF_dns_upstreams=10.43.100.20#53;1.1.1.1#53`.

[Kubernetes Manifests](src/resources/pihole)

### Pikaraoke

[Pikaraoke](https://github.com/vicwomg/pikaraoke) hosts a karaoke catalog and
web UI for party playlists.

[Kubernetes Manifests](src/resources/pikaraoke)

### Portainer

[Portainer](https://www.portainer.io) is a web-based management tool for Docker
and Kubernetes. It provides an interface to manage your cluster, view logs, and
more.

[Kubernetes Manifests](src/resources/portainer)

### Security

Security middleware, TLS issuers, and common Traefik policies (basic auth, HTTPS
redirects, size limits, websocket headers).

[Kubernetes Manifests](src/resources/security)

### Shlink

[Shlink](https://shlink.io) is a self-hosted URL shortener with a companion web
client.

[Kubernetes Manifests](src/resources/shlink)

### Unbound

[Unbound](https://www.nlnetlabs.nl/projects/unbound/about/) is a validating,
recursive, caching DNS resolver. Paired with Pi-hole, it provides DNS caching
and custom DNS records for your network and your cluster.

[Kubernetes Manifests](src/resources/unbound)

### Uptime Kuma

[Uptime Kuma](https://github.com/louislam/uptime-kuma) provides self-hosted
availability monitoring with status pages and alerting.

[Kubernetes Manifests](src/resources/uptime)

## Planned or Experimental

These resources exist in `k8s/src/resources` but are not currently wired into
`k8s/src/deploy.sh` or are placeholders.

- [Keycloak](https://www.keycloak.org): Helm values at
  `src/resources/keycloak/helm-values.yml`.
- Speedtest: empty resource folder reserved for future use.

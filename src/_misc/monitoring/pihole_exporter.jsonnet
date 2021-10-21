local utils = import '../utils.libsonnet';
local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';

{
  _config+:: {
    namespace: 'monitoring',

    pihole: {
      ips: ['${CLUSTER_HOSTNETWORKINGIPADDRESS}'],
    },

    // Add custom dashboards
    grafanaDashboards+:: {
      'pihole-dashboard.json': (import '../grafana-dashboards/pihole-dashboard.json'),
    },
  },

  piholeExporter+:: {
    serviceMonitor:
      utils.newServiceMonitor('pihole-exporter', $._config.namespace, { 'k8s-app': 'pihole-exporter' }, $._config.namespace, 'metrics', 'http'),

    service:
      local service = k.core.v1.service;
      local servicePort = k.core.v1.service.mixin.spec.portsType;

      local piholeExporterPort = servicePort.newNamed('metrics', 9617, 9617);

      service.new('pihole-exporter', null, piholeExporterPort) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.metadata.withLabels({ 'k8s-app': 'pihole-exporter' }) +
      service.mixin.spec.withClusterIp('None'),

    endpoints:
      utils.newEndpoint('pihole-exporter', $._config.namespace, $._config.pihole.ips, 'metrics', 9617),
  },
}

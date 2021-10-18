local utils = import '../utils.libsonnet';
local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';

{
  _config+:: {
    namespace: 'monitoring',

    wmi: {
      ips: ['${WMI_IP_ADDRESS}'],
    },

    // Add custom dashboards
    grafanaDashboards+:: {
      'wmi-dashboard.json': (import '../grafana-dashboards/wmi-dashboard.json'),
    },
  },

  wmiExporter+:: {
    serviceMonitor:
      utils.newServiceMonitor('wmi-exporter', $._config.namespace, { 'k8s-app': 'wmi-exporter' }, $._config.namespace, 'metrics', 'http'),

    service:
      local service = k.core.v1.service;
      local servicePort = k.core.v1.service.mixin.spec.portsType;

      local wmiExporterPort = servicePort.newNamed('metrics', 9182, 9182);

      service.new('wmi-exporter', null, wmiExporterPort) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.metadata.withLabels({ 'k8s-app': 'wmi-exporter' }) +
      service.mixin.spec.withClusterIp('None'),

    endpoints:
      utils.newEndpoint('wmi-exporter', $._config.namespace, $._config.wmi.ips, 'metrics', 9182),
  },
}

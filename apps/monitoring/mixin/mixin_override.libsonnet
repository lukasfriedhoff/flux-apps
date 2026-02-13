// explicitly imports instead of (import 'kubernetes-mixin/mixin.libsonnet')
// to ignore alerts for kube_apiserver, kube_controller_manager, kube_proxy and kube_scheduler (not used in pske cluster)
(import 'kubernetes-mixin/alerts/apps_alerts.libsonnet') +
(import 'kubernetes-mixin/alerts/resource_alerts.libsonnet') +
(import 'kubernetes-mixin/alerts/storage_alerts.libsonnet') +
(import 'kubernetes-mixin/alerts/system_alerts.libsonnet') +
(import 'kubernetes-mixin/alerts/kubelet.libsonnet') +
(import 'kubernetes-mixin/lib/add-runbook-links.libsonnet') +
// to ignore dashboards for above and windows components
(import 'kubernetes-mixin/dashboards/network.libsonnet') +
(import 'kubernetes-mixin/dashboards/persistentvolumesusage.libsonnet') +
(import 'kubernetes-mixin/dashboards/resources.libsonnet') +
(import 'kubernetes-mixin/dashboards/kubelet.libsonnet') +
(import 'kubernetes-mixin/dashboards/defaults.libsonnet') +
// rules don't hurt without base-metrics
(import 'kubernetes-mixin/rules/rules.libsonnet') +
(import 'kubernetes-mixin/config.libsonnet') +
// custom fixes
(import 'fixes/fixes.libsonnet') +
{
  _config+:: {
    cadvisorSelector: 'job="integrations/kubernetes/cadvisor"',  // metrics found => cadvisor instead of kubelet-cadvisor for less metrics in Networking/Namespaces dashboard
    kubeletSelector: 'job="integrations/kubernetes/kubelet"',  // metrics found
    kubeStateMetricsSelector: 'job="integrations/kubernetes/kube-state-metrics"',  // metrics found
    nodeExporterSelector: 'job="integrations/node_exporter"',  // metrics found
    kubeSchedulerSelector: 'job="kube-scheduler"',  // missing on cluster
    kubeControllerManagerSelector: 'job="kube-controller-manager"',  // missing on cluster
    kubeApiserverSelector: 'job="integrations/kubernetes/kube-apiserver"',  // missing on cluster
    kubeProxySelector: 'job="integrations/kubernetes/kube-proxy"',  // missing
    podLabel: 'pod',
    hostNetworkInterfaceSelector: 'device!~"veth.+"',  // irrelevant - nowhere found
    hostMountpointSelector: 'mountpoint="/"',  // irrelevant - nowhere found
    windowsExporterSelector: 'job="integrations/windows_exporter"',  // irrelevant
    containerfsSelector: 'container!=""',  // metrics found

    grafanaK8s+:: {
      dashboardNamePrefix: '',
      dashboardTags: ['kubernetes', 'infrastructure'],
    },
  },
}

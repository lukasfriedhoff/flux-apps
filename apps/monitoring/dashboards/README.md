# Grafana Dashboards

This directory provides GitOps-managed dashboards loaded by Grafana's sidecar.

## Sources
- Kubernetes mixin dashboards generated from `kubernetes-monitoring/kubernetes-mixin`.
- Node Exporter dashboards generated from `prometheus/node_exporter` (`docs/node-mixin`).
- CoreDNS dashboard generated from `povilasv/coredns-mixin`.
- Flux dashboards from `fluxcd/flux2-monitoring-example`.
- Traefik dashboard from `traefik/traefik` (contrib Grafana dashboard).
- Authelia dashboard from `authelia/authelia` (examples).
- Cert-manager dashboard from Grafana.com (dashboard ID 11001).
- CloudNativePG dashboard from `cloudnative-pg/grafana-dashboards`.
- Loki dashboards from `grafana/loki` mixin-compiled outputs.
- Mimir dashboards from `grafana/mimir` mixin-compiled outputs.
- Tempo dashboards from `grafana/tempo` mixin-compiled outputs.
- Nextcloud dashboard from `xperimental/nextcloud-exporter`.
- Valkey dashboard from `oliver006/redis_exporter`.
- Longhorn storage dashboard maintained locally around Longhorn manager metrics and kube-state-metrics PVC ownership data.

## Notes
- `kube-state-metrics` currently ships alerts/rules in its mixin, not Grafana dashboards.
- Grafana's own mixin dashboard is not included because Grafana self-metrics are not enabled in the chart values.
- Nextcloud dashboards require `nextcloud-exporter` metrics.
- Valkey dashboards expect `redis_exporter` compatible metrics.
- Longhorn dashboards require the Longhorn manager `/metrics` scrape annotations.
- Apps without maintained Prometheus dashboards stay status-page only until metrics and a dashboard source are wired.

# Grafana Dashboards

This directory provides GitOps-managed dashboards loaded by Grafana's sidecar.

## Sources
- Kubernetes mixin dashboards generated from `kubernetes-monitoring/kubernetes-mixin`.
- Traefik dashboard from `traefik/traefik` (contrib Grafana dashboard).
- Authelia dashboard from `authelia/authelia` (examples).
- Cert-manager dashboard from Grafana.com (dashboard ID 11001).
- CloudNativePG dashboard from `cloudnative-pg/grafana-dashboards`.
- Loki dashboards from `grafana/loki` mixin-compiled outputs.
- Mimir dashboards from `grafana/mimir` mixin-compiled outputs.
- Tempo dashboards from `grafana/tempo` mixin-compiled outputs.
- Ceph dashboards from `ceph/ceph` mixin outputs.
- Nextcloud dashboard from `xperimental/nextcloud-exporter`.
- Valkey dashboard from `oliver006/redis_exporter`.

## Notes
- Nextcloud dashboards require `nextcloud-exporter` metrics.
- Valkey dashboards expect `redis_exporter` compatible metrics.
- Ceph dashboards require Prometheus-enabled Ceph mgr exporters.
- No upstream dashboards were located yet for external-dns, cloudflared, collabora, reloader, or ceph-csi; add sources if you have preferred ones.

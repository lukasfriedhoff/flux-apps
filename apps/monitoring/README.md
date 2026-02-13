# Monitoring (LGTM)

This stack uses Grafana's `k8s-monitoring` chart to deploy Alloy collectors and wire metrics/logs/events to Mimir/Loki/Tempo.
Cluster-specific values live in `flux-cluster/base/configs/infra/monitoring/pre/k8s-monitoring-values.yaml` and are merged via Flux substitutions.

## Dashboards

Kubernetes mixin dashboards are generated from `apps/monitoring/mixin` and synced into `apps/monitoring/dashboards/kubernetes-mixin`.
Run `apps/monitoring/mixin/generate.sh generate` and commit updated JSON when bumping the mixin.

## Tests

`apps/monitoring/tests/verify-mimir-endpoints-job.yaml` is a manual diagnostic job you can apply when validating Mimir.

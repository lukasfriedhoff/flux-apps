# Dashboards

Build the dashboards via [kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) with a little hack as documented in [k8s-monitoring-issue](https://github.com/grafana/k8s-monitoring-helm/issues/1073).

## Prerequisites

- yq
- kubectl
- jsonnet & jsonnet-bundler: `brew install jsonnet jsonnet-bundler`

## Build

Use the script [generate.sh](generate.sh) to

- `load` the current version from kubernetes-mixin into `vendor`
- `jsonnet` creates yaml/json files via `jsonnet` from the var-configs in [mixin_override.libsonnet](mixin_override.libsonnet) into `tmp-files`
- `k8s` creates the kustomize-files into `files`, and syncs dashboards into `apps/monitoring/dashboards/kubernetes-mixin`
- `all` to run all steps as 1 command
- `generate` to run `jsonnet` and `k8s` as 1 command

```sh
./generate.sh load
./generate.sh jsonnet
./generate.sh k8s
```

The `k8s` step contains the "static" files:
- [dashboards/kustomization](dashboards/kustomization.yaml) in which only the configMapGenerator-part is modified
- [rules/kustomization](rules/kustomization.yaml) in which nothing gets modified

And the dynamic files, which gets regenerated every time:
- [dashboards/files/](dashboards/files/) with all json dashboards files from mixin
- [rules/files/](rules/files/) with the alert and rules yaml files from mixin

> [!WARNING]
> Be aware, that flux env substitution is disabled for dashboard config maps in `apps/monitoring/dashboards/kustomization.yaml` to workaround similar syntax for grafana and flux vars.
> If the dashboards land in the wrong namespace, adjust the dashboards config map generators rather than relying on postBuild.

## Usage

Dashboards are loaded via `apps/monitoring/dashboards/kustomization.yaml` in this repo. Regenerate and commit the JSON in `apps/monitoring/dashboards/kubernetes-mixin` when updating the mixin.

## Mixin Logic

See [presentation](https://grafana.com/blog/2018/09/13/everything-you-need-to-know-about-monitoring-mixins/).

## Local Structure and Overrides

The generation of mixins from libsonnet files to k8s yaml resources is built in multiple steps and a bit nested.

> [!WARNING]
> As we only commit results, you need to run the generation-steps first or most of the files won't exist.

Here is the way from the k8s-dashboard `k8s-mixin-namespace-by-workload` back to the original libsonnet file:
  - dashboard Namespace by Workload from [kustomization](files/dashboards/kustomization.yaml)
  - based on json [files namespace-by-workload.json](files/dashboards/namespace-by-workload.json) / [tmp-file](tmp-files/dashboards/namespace-by-workload.json)
  - generated via [mixin_override.libsonnet](mixin_override.libsonnet)
  - via [vendor mixin.libsonnet](vendor/kubernetes-mixin/mixin.libsonnet)
  - via [vendor dashboards.libsonnet](vendor/kubernetes-mixin/dashboards/dashboards.libsonnet)
  - via [vendor network.libsonnet](vendor/kubernetes-mixin/dashboards/network.libsonnet)
  - uses [vendor namespace-by-workload.libsonnet](vendor/kubernetes-mixin/dashboards/network-usage/namespace-by-workload.libsonnet)

So the panel `Current Status` in dashboard [namespace-by-workload](files/dashboards/namespace-by-workload.json) is by default defined in [namespace-by-workload.libsonnet](vendor/kubernetes-mixin/dashboards/network-usage/namespace-by-workload.libsonnet) near `table.new('Current Status')`.

To modify incompatible queries you can override a dashboard with [fixes](fixes/fixes.libsonnet)

- fix for [issue of TCP](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/949) via [cluster-total fix](fixes/cluster-total.libsonnet)

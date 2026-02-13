#!/bin/bash

load() {
  echo "Loading mixin dependencies into vendor"
  jb install https://github.com/kubernetes-monitoring/kubernetes-mixin
  echo "Loading complete, all dependencies are in vendor/."
}

generate_jsonnet() {
  if [ ! -d "vendor/kubernetes-mixin" ]; then
    echo "Dependencies not found. Please run '$0 load' first."
    exit 1
  fi
  echo "Cleaning up old tmp-files..."
  rm -rf tmp-files
  echo "Generating tmp-files with mixin.libsonnet..."
  mkdir -p tmp-files/dashboards
  jsonnet -J vendor -S -e 'std.manifestYamlDoc((import "mixin_override.libsonnet").prometheusAlerts)' | yq '.' -P > tmp-files/alerts.yaml
  echo "tmp-files/alerts.yaml"
  jsonnet -J vendor -S -e 'std.manifestYamlDoc((import "mixin_override.libsonnet").prometheusRules)' | yq '.' -P > tmp-files/rules.yaml
  echo "tmp-files/rules.yaml"
  jsonnet -J vendor -m tmp-files/dashboards -e '(import "mixin_override.libsonnet").grafanaDashboards'
  echo "Generated tmp-files with mixin.libsonnet, see tmp-files/ for output."
}

generate_k8s() {
  if [ ! -d "tmp-files" ]; then
    echo "Tmp files not found. Please run '$0 jsonnet' first."
    exit 1
  fi
  echo "Cleaning up generated files..."
  rm -f rules/files/*.yaml dashboards/files/*.json
  
  echo "Generating k8s rules resources..."

  cat <<EOF > rules/files/alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: k8s-mixin-alerts
  labels:
    role: alert-rules
spec:
  groups: []
EOF
  yq -i '.spec.groups += (load("tmp-files/alerts.yaml") | .groups)' rules/files/alerts.yaml
  echo "Generated rules/files/alerts.yaml"

  cat <<EOF > rules/files/rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: k8s-mixin-rules
  labels:
    role: recording-rules
spec:
  groups: []
EOF
  yq -i '.spec.groups += (load("tmp-files/rules.yaml") | .groups)' rules/files/rules.yaml
  echo "Generated rules/files/rules.yaml"
  echo "Generated all k8s rules resources"

  echo "Generating k8s dashboards resources..."
  cp tmp-files/dashboards/*.json dashboards/files/
  echo "Copied dashboards json files to dashboards/files/"

  echo "Syncing dashboards into apps/monitoring/dashboards/kubernetes-mixin"
  target_dir="../dashboards/kubernetes-mixin"
  mkdir -p "$target_dir"
  cp dashboards/files/*.json "$target_dir/"
  echo "Synced dashboards to $target_dir"
  
  cd dashboards
  echo "Removing all existing configMaps from dashboards/kustomization.yaml"
  yq -i 'del(.configMapGenerator)' kustomization.yaml
  echo "Adding all json files as configMap..."
  for f in files/*.json; do
    file="$(basename "$f")"
    name="${file%.json}"
    kustomize edit add configmap k8s-mixin-$name --from-file $f --disableNameSuffixHash
  done
  echo "Generated dashboards/kustomization.yaml"
  echo "Generated all k8s-resources and updated kustomizations, see dashboards/ and rules/."
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 load|jsonnet|k8s|generate|all"
  exit 1
fi

MODE=$1

if [ "$MODE" == "load" ]; then
  load
  echo "Please run '$0 jsonnet' to generate jsonnet files."
elif [ "$MODE" == "jsonnet" ]; then
  generate_jsonnet
  echo "Please run '$0 k8s' to generate k8s resources."
elif [ "$MODE" == "k8s" ]; then
  generate_k8s
elif [ "$MODE" == "generate" ]; then
  generate_jsonnet
  generate_k8s
elif [ "$MODE" == "all" ]; then
  load
  generate_jsonnet
  generate_k8s
else
  echo "Invalid mode. Use 'load' or 'jsonnet' or 'k8s' or 'generate' (jsonnet and k8s combined) or 'all'."
  exit 1
fi

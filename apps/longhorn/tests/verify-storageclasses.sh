#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

env \
  longhorn_namespace=longhorn-system \
  longhorn_default_replica_count=3 \
  quote='"' \
  kustomize build "${repo_root}/apps/longhorn" \
  | env \
      longhorn_namespace=longhorn-system \
      longhorn_default_replica_count=3 \
      quote='"' \
      flux envsubst --strict >"$rendered"

two_replica_count="$(
  yq -s \
    '[.[] | select(.kind == "StorageClass" and .parameters.numberOfReplicas == "2")] | length' \
    "$rendered"
)"
invalid_two_replica_count="$(
  yq -s \
    '[.[] | select(
      .kind == "StorageClass"
      and .parameters.numberOfReplicas == "2"
      and (
        .parameters.replicaSoftAntiAffinity != "disabled"
        or .parameters.replicaDiskSoftAntiAffinity != "disabled"
        or .metadata.annotations."kustomize.toolkit.fluxcd.io/force" != "enabled"
      )
    )] | length' \
    "$rendered"
)"

[ "$two_replica_count" -eq 8 ]
[ "$invalid_two_replica_count" -eq 0 ]

printf '[longhorn-storageclass-test] validated %s two-replica classes\n' "$two_replica_count"

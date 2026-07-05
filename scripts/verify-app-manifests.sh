#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
apps_dir="${repo_root}/apps"
examples_dir="${repo_root}/examples/apps"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[app-manifest-test] missing required command: %s\n' "$1" >&2
    exit 1
  }
}

fail() {
  printf '[app-manifest-test] FAIL: %s\n' "$*" >&2
  exit 1
}

need kustomize
need yq

for app_path in "${apps_dir}"/*; do
  [ -d "$app_path" ] || continue
  app="$(basename "$app_path")"
  kustomization="${app_path}/kustomization.yaml"
  rendered="$(mktemp)"
  trap 'rm -f "$rendered"' EXIT

  [ -f "$kustomization" ] || fail "apps/${app} is missing kustomization.yaml"
  [ -d "${examples_dir}/${app}" ] || fail "apps/${app} is missing examples/apps/${app}"
  [ -f "${examples_dir}/${app}/base-config.defaults.yaml" ] || fail "examples/apps/${app} is missing base-config.defaults.yaml"
  [ -f "${examples_dir}/${app}/flux-cluster-kustomization.yaml" ] || fail "examples/apps/${app} is missing flux-cluster-kustomization.yaml"

  kustomize build "$app_path" >"$rendered" || fail "apps/${app} failed kustomize build"
  [ -s "$rendered" ] || fail "apps/${app} rendered an empty manifest"

  yq -e 'select(has("apiVersion") and has("kind") and has("metadata"))' "$rendered" >/dev/null \
    || fail "apps/${app} rendered no Kubernetes resources with apiVersion/kind/metadata"

  if grep -Eq '\$\{[A-Za-z0-9_]+(:=[^}]*)?\}' "$rendered"; then
    printf '[app-manifest-test] apps/%s ok (contains postBuild substitutions)\n' "$app"
  else
    printf '[app-manifest-test] apps/%s ok\n' "$app"
  fi

  rm -f "$rendered"
  trap - EXIT
done

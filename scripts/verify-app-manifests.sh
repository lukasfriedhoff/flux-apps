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

  # Flux runs envsubst over the rendered manifest at reconcile time, and it
  # rejects anything that is not a parseable variable name - including a
  # literal ${...} written in a YAML comment, which reads as a variable named
  # "...". kustomize build is perfectly happy with that, so the failure only
  # ever showed up in the cluster as "unable to parse variable name" with no
  # hint of which line caused it. Replicate the pass here instead.
  # Resources annotated substitute: disabled are skipped by flux, so they may
  # legitimately contain text envsubst cannot parse - the Grafana dashboards in
  # apps/monitoring carry ${...} Grafana template vars for exactly that reason.
  # Filter them out the same way flux does before checking the rest.
  yq 'select(.metadata.annotations."kustomize.toolkit.fluxcd.io/substitute" != "disabled")' \
    "$rendered" >"${rendered}.sub" 2>/dev/null || cp "$rendered" "${rendered}.sub"

  if ! flux envsubst <"${rendered}.sub" >/dev/null 2>"${rendered}.err"; then
    printf '[app-manifest-test] apps/%s fails flux envsubst:\n' "$app" >&2
    sed 's/^/    /' "${rendered}.err" >&2
    printf '  A literal ${...} or $${...} in a comment is the usual cause.\n' >&2
    rm -f "${rendered}.err" "${rendered}.sub"
    fail "apps/${app} rendered a manifest flux cannot substitute"
  fi
  rm -f "${rendered}.err" "${rendered}.sub"

  if grep -Eq '\$\{[A-Za-z0-9_]+(:=[^}]*)?\}' "$rendered"; then
    printf '[app-manifest-test] apps/%s ok (contains postBuild substitutions)\n' "$app"
  else
    printf '[app-manifest-test] apps/%s ok\n' "$app"
  fi

  rm -f "$rendered"
  trap - EXIT
done

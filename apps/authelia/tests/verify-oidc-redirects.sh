#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
config_file="${repo_root}/apps/authelia/configmap.yaml"
defaults_file="${repo_root}/examples/apps/authelia/base-config.defaults.yaml"
expected_callback='- ${matrix_public_baseurl}/_synapse/client/oidc/callback'

matrix_client="$(
  sed -n \
    '/client_id: ${matrix_oidc_client_id:=matrix-synapse}/,/token_endpoint_auth_method: client_secret_post/p' \
    "$config_file"
)"

printf '%s\n' "$matrix_client" | grep -Fq -- "$expected_callback" || {
  printf '[authelia-oidc-test] Matrix callback must follow matrix_public_baseurl\n' >&2
  exit 1
}

grep -Fq 'matrix_public_baseurl:' "$defaults_file" || {
  printf '[authelia-oidc-test] authelia example defaults are missing matrix_public_baseurl\n' >&2
  exit 1
}

printf '[authelia-oidc-test] Matrix callback follows the canonical Synapse public base URL\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
config_file="${repo_root}/apps/cloudflared/configmap.yaml"
deployment_file="${repo_root}/apps/cloudflared/deployment.yaml"

fail() {
  printf '[cloudflared-test] FAIL: %s\n' "$*" >&2
  exit 1
}

command -v yq >/dev/null 2>&1 || fail "missing required command: yq"

config="$(yq -r '.data."config.yaml"' "$config_file")"
reloader_enabled="$(yq -r '.metadata.annotations."reloader.stakater.com/auto" // ""' "$deployment_file")"

[ "$reloader_enabled" = "true" ] || fail "cloudflared deployment must reload ConfigMap changes"

line_number() {
  local pattern="$1"
  printf '%s\n' "$config" | awk -v pattern="$pattern" 'index($0, pattern) { print NR; exit }'
}

apex_line="$(line_number 'hostname: "${delegating_domain}"')"
wildcard_line="$(line_number 'hostname: "*.${delegating_domain}"')"
fallback_line="$(line_number 'service: http_status:404')"

[ -n "$apex_line" ] || fail "missing apex-domain tunnel route"
[ -n "$wildcard_line" ] || fail "missing wildcard tunnel route"
[ -n "$fallback_line" ] || fail "missing terminal 404 route"

if [ "$apex_line" -ge "$wildcard_line" ]; then
  fail "apex-domain route must precede wildcard route"
fi

if [ "$wildcard_line" -ge "$fallback_line" ]; then
  fail "wildcard route must precede terminal 404 route"
fi

printf '%s\n' "$config" | awk '
  /hostname: "\$\{delegating_domain\}"/ { apex = 1 }
  apex && /service: https:\/\/traefik\.traefik\.svc\.cluster\.local:443/ { service = 1 }
  END { exit !(apex && service) }
' || fail "apex-domain route does not target Traefik"

printf '[cloudflared-test] apex and wildcard routes are ordered correctly\n'

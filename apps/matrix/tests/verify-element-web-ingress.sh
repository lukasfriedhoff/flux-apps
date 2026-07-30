#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
element_web="${repo_root}/apps/matrix/element-web.yaml"

fail() {
  printf '[matrix-element-ingress-test] FAIL: %s\n' "$*" >&2
  exit 1
}

ingress_block="$(
  awk '
    /^kind: Ingress$/ { capture=1 }
    capture { print }
  ' "$element_web"
)"

grep -Fq 'path: /_matrix' <<<"$ingress_block" \
  || fail 'chat ingress must route Matrix API/media paths'
grep -Fq 'path: /_synapse' <<<"$ingress_block" \
  || fail 'chat ingress must route Synapse admin paths'

matrix_path_line="$(grep -nF 'path: /_matrix' <<<"$ingress_block" | head -n1 | cut -d: -f1)"
root_path_line="$(grep -nF 'path: /' <<<"$ingress_block" | tail -n1 | cut -d: -f1)"

[[ -n "$matrix_path_line" && -n "$root_path_line" ]] \
  || fail 'chat ingress must include both Matrix and Element routes'

(( matrix_path_line < root_path_line )) \
  || fail 'Matrix API/media path should be listed before the Element root route'

printf '[matrix-element-ingress-test] ok\n'

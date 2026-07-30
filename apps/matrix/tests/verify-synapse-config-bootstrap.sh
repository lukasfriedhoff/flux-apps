#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
synapse="${repo_root}/apps/matrix/synapse.yaml"

fail() {
  printf '[matrix-synapse-config-test] FAIL: %s\n' "$*" >&2
  exit 1
}

init_script="$(
  awk '
    /- name: synapse-config-bootstrap/ { capture=1 }
    capture { print }
    capture && /env:/ { exit }
  ' "$synapse"
)"

grep -Fq 'enable_authenticated_media: false' <<<"$init_script" \
  || fail 'Synapse must keep legacy unauthenticated media URLs working'

grep -Fq 'sed -i' <<<"$init_script" \
  || fail 'Synapse config bootstrap must update existing seed values'

printf '[matrix-synapse-config-test] ok\n'

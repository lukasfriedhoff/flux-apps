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

normalize_line="$(
  grep -nF "Some encrypted seed configs do not end with a newline" <<<"$init_script" \
    | head -n1 \
    | cut -d: -f1
)"
authenticated_media_line="$(
  grep -nF 'enable_authenticated_media:' <<<"$init_script" \
    | head -n1 \
    | cut -d: -f1
)"

[[ -n "$normalize_line" ]] \
  || fail 'Synapse config bootstrap must normalize seed file newline before appending keys'

[[ -n "$authenticated_media_line" ]] \
  || fail 'Synapse config bootstrap must configure authenticated media'

(( normalize_line < authenticated_media_line )) \
  || fail 'Synapse config bootstrap must normalize newline before enable_authenticated_media'

printf '[matrix-synapse-config-test] ok\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
bridges="${repo_root}/apps/matrix/bridges.yaml"

fail() {
  printf '[matrix-bridge-config-test] FAIL: %s\n' "$*" >&2
  exit 1
}

telegram_init="$(
  awk '
    /- name: telegram-config-bootstrap/ { capture=1 }
    capture { print }
    capture && /volumeMounts:/ { exit }
  ' "$bridges"
)"

grep -Fq 'cp /seed/config.yaml /data/config.yaml' <<<"$telegram_init" \
  || fail 'Telegram does not refresh config.yaml from its Secret'
grep -Fq 'cp /seed/registration.yaml /data/registration.yaml' <<<"$telegram_init" \
  || fail 'Telegram does not refresh registration.yaml from its Secret'

if grep -Fq 'if [ ! -s /data/config.yaml ]' <<<"$telegram_init"; then
  fail 'Telegram retains stale config.yaml when the Secret changes'
fi
if grep -Fq 'if [ ! -s /data/registration.yaml ]' <<<"$telegram_init"; then
  fail 'Telegram retains stale registration.yaml when the Secret changes'
fi

printf '[matrix-bridge-config-test] ok\n'

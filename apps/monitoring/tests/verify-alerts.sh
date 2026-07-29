#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
alerts="${repo_root}/apps/monitoring/rules-sync/alerts.yaml"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[alert-test] missing required command: %s\n' "$1" >&2
    exit 1
  }
}

fail() {
  printf '[alert-test] FAIL: %s\n' "$*" >&2
  exit 1
}

need yq

yq -e '.' "$alerts" >/dev/null || fail "alerts manifest is invalid YAML"

for alert in LonghornVolumeDegraded LonghornVolumeDegradedTooLong LonghornVolumeFaulted; do
  count="$(yq -r "[.groups[].rules[] | select(.alert == \"${alert}\")] | length" "$alerts")"
  [ "$count" = "1" ] || fail "${alert} must exist exactly once"
done

if grep -Eq 'longhorn_volume_robustness[[:space:]]*==[[:space:]]*[0-9]' "$alerts"; then
  fail "Longhorn robustness alerts must use state labels"
fi

grep -q 'longhorn_volume_robustness{state="degraded"}' "$alerts" \
  || fail "degraded Longhorn state is not monitored"
grep -q 'longhorn_volume_robustness{state="faulted"}' "$alerts" \
  || fail "faulted Longhorn state is not monitored"

printf '[alert-test] alerts ok\n'

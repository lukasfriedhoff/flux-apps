#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"

fail() {
  printf '[qbittorrent-policy-test] FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'Session\\GlobalMaxRatio.*-1' "$rendered" \
  || fail 'qBittorrent config init does not force GlobalMaxRatio=-1'
grep -q '"max_ratio_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_ratio_enabled'
grep -q '"max_ratio": -1' "$rendered" \
  || fail 'qBittorrent API policy does not force max_ratio=-1'
grep -q '"max_seeding_time_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_seeding_time_enabled'
grep -q '"max_inactive_seeding_time_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_inactive_seeding_time_enabled'
grep -q '"add_trackers_from_url_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable automatic tracker URL appends'

if grep -q 'QBITTORRENT_DEFAULT_SEED_RATIO' "$rendered"; then
  fail 'legacy QBITTORRENT_DEFAULT_SEED_RATIO must not be rendered'
fi

printf '[qbittorrent-policy-test] ok\n'

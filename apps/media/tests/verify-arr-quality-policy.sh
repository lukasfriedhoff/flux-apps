#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"

fail() {
  printf '[arr-quality-policy-test] FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'ARR_QUALITY_PROFILE_NAME="\$${ARR_QUALITY_PROFILE_NAME:-HD/4K - German+English}"' "$rendered" \
  || fail 'Prowlarr bootstrap does not default the managed quality profile name'
grep -q 'arr_quality_profile_name="\$${ARR_QUALITY_PROFILE_NAME:-HD/4K - German+English}"' "$rendered" \
  || fail 'Jellyseerr config sync does not default the managed quality profile name'
profile_default_count="$(grep -c 'arr_quality_profile_name="\$${ARR_QUALITY_PROFILE_NAME:-HD/4K - German+English}"' "$rendered" || true)"
if [ "$profile_default_count" -lt 2 ]; then
  fail 'Jellyseerr bootstrap and config sync must both use the managed quality profile name'
fi
grep -q '\[jellyseerr-config-sync\] managed settings unchanged' "$rendered" \
  || fail 'Jellyseerr config sync must skip restarts when managed settings are unchanged'
grep -q 'Created Sonarr quality profile .*\$ARR_QUALITY_PROFILE_NAME' "$rendered" \
  || fail 'Sonarr bootstrap does not create the managed quality profile'
grep -q 'Updated Sonarr quality profile .*\$ARR_QUALITY_PROFILE_NAME' "$rendered" \
  || fail 'Sonarr bootstrap does not update the managed quality profile'
grep -q 'Created Radarr quality profile .*\$ARR_QUALITY_PROFILE_NAME' "$rendered" \
  || fail 'Radarr bootstrap does not create the managed quality profile'
grep -q 'Updated Radarr quality profile .*\$ARR_QUALITY_PROFILE_NAME' "$rendered" \
  || fail 'Radarr bootstrap does not update the managed quality profile'
grep -q 'cutoff = cutoff_id' "$rendered" \
  || fail 'ARR quality profile does not set a best-quality cutoff'
grep -q '720p|1080p|2160p|4k|uhd' "$rendered" \
  || fail 'ARR quality profile does not allow HD and 4K quality matching'
grep -q 'minFormatScore = 100' "$rendered" \
  || fail 'ARR quality profile does not enforce the dual-audio minimum score'
grep -q -- '--arg preferred "$arr_quality_profile_name"' "$rendered" \
  || fail 'Jellyseerr does not prefer the managed ARR quality profile'
grep -q 'is4k: false' "$rendered" \
  || fail 'Jellyseerr should keep single Radarr/Sonarr services as non-4K services'

printf '[arr-quality-policy-test] ok\n'

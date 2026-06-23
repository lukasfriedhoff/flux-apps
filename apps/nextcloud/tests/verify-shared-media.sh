#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
helm_release="${repo_root}/apps/nextcloud/helm-release.yaml"
memes_cron="${repo_root}/apps/nextcloud/shared-memes-userdirs-cronjob.yaml"
photos_cron="${repo_root}/apps/nextcloud/shared-photos-userdirs-cronjob.yaml"

fail() {
  printf '[nextcloud-shared-media-test] %s\n' "$*" >&2
  exit 1
}

grep -q 'NEXTCLOUD_EXTERNAL_PHOTOS_ENABLED' "$helm_release" || fail "missing external Photos link environment"
grep -q 'NEXTCLOUD_EXTERNAL_MEMES_ENABLED' "$helm_release" || fail "missing external Memes link environment"
grep -q 'configure_shared_photos_storage' "$helm_release" || fail "missing shared Photos storage bootstrap"
grep -q 'configure_shared_memes_storage' "$helm_release" || fail "missing shared Memes storage bootstrap"
grep -q 'mountPath: /shared-photos' "$helm_release" || fail "missing /shared-photos mount"
grep -q 'mountPath: /shared-memes' "$helm_release" || fail "missing /shared-memes mount"
grep -q 'subPath: memes' "$helm_release" || fail "Memes must be isolated as a subdirectory of the shared media volume"
grep -q 'claimName: ${nextcloud_memes_claim_name:=nextcloud-photos-shared}' "$helm_release" || fail "Memes mount must use the configurable shared-media PVC"

grep -q 'files/Memes' "$memes_cron" || fail "missing Memes user directory scan cron"
grep -q '/shared-memes' "$memes_cron" || fail "missing Memes user directory creation"
grep -q 'files/Photos' "$photos_cron" || fail "missing Photos user directory scan cron"
grep -q '/shared-photos' "$photos_cron" || fail "missing Photos user directory creation"

printf '[nextcloud-shared-media-test] shared media wiring ok\n'

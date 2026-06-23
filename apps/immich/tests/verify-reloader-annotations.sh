#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

fail() {
  printf '[immich-reloader-test] FAIL: %s\n' "$*" >&2
  exit 1
}

check_file() {
  local file=$1
  local deployment=$2
  if ! grep -q 'reloader.stakater.com/auto: "true"' "$file"; then
    fail "${deployment} is missing reloader.stakater.com/auto annotation"
  fi
  if ! grep -q 'maxSurge: 0' "$file"; then
    fail "${deployment} must disable rollout surge to avoid resource deadlocks"
  fi
  if ! grep -q 'maxUnavailable: 1' "$file"; then
    fail "${deployment} must allow one unavailable pod during replacement"
  fi
  printf '[immich-reloader-test] %s ok\n' "$deployment"
}

check_file "${repo_root}/apps/immich/server.yaml" immich-server
check_file "${repo_root}/apps/immich-photos/server.yaml" immich-photos-server

photos_kustomization="${repo_root}/apps/immich-photos/kustomization.yaml"
photos_pvc="${repo_root}/apps/immich-photos/pvc-photos.yaml"
if ! grep -q 'pv-photos.yaml' "$photos_kustomization"; then
  fail "immich-photos kustomization must include the static Nextcloud photos PV"
fi
if ! grep -q 'storageClassName: ""' "$photos_pvc"; then
  fail "immich-photos shared PVC must bind to a static NFS PV, not provision its own volume"
fi
if ! grep -q 'volumeName: ${immich_photos_shared_pv_name:=immich-photos-shared-pv}' "$photos_pvc"; then
  fail "immich-photos shared PVC must pin the configured static PV name"
fi
printf '[immich-reloader-test] immich-photos shared storage ok\n'

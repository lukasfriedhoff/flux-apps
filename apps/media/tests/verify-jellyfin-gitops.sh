#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
bootstrap_script="$(mktemp --suffix=.py)"
jellyfin_release="$(mktemp)"
transcode_cache_pvc="$(mktemp)"
cleanup_script="$(mktemp --suffix=.py)"
cleanup_test_directory="$(mktemp -d)"
active_process_pid=""
if command -v python3 >/dev/null 2>&1; then
  python_command=(python3)
elif command -v python >/dev/null 2>&1; then
  python_command=(python)
else
  python_command=(nix shell nixpkgs#python3 -c python)
fi

cleanup() {
  if [[ -n "$active_process_pid" ]]; then
    kill "$active_process_pid" 2>/dev/null || true
    wait "$active_process_pid" 2>/dev/null || true
  fi
  rm -f \
    "$rendered" \
    "$bootstrap_script" \
    "$jellyfin_release" \
    "$transcode_cache_pvc" \
    "$cleanup_script"
  rm -rf "$cleanup_test_directory"
}
trap cleanup EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"
yq -y 'select(.kind == "HelmRelease" and .metadata.name == "jellyfin")' \
  "$rendered" >"$jellyfin_release"
yq -y 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "jellyfin-transcode-cache")' \
  "$rendered" >"$transcode_cache_pvc"
yq -r 'select(.kind == "ConfigMap" and .metadata.name == "jellyfin-transcode-cleanup") | .data["cleanup.py"]' \
  "$rendered" >"$cleanup_script"

fail() {
  printf '[jellyfin-gitops-test] FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'name: jellyfin-admin-sync' "$rendered" \
  || fail 'Jellyfin admin sync job is not rendered'
awk '
  /^kind: HelmRelease$/ {in_hr=1; in_jellyfin=0; middleware=0}
  in_hr && /^  name: jellyfin$/ {in_jellyfin=1}
  in_jellyfin && /traefik\.ingress\.kubernetes\.io\/router\.middlewares: traefik-authelia-forwardauth-redirect@kubernetescrd/ {middleware=1}
  in_hr && /^---$/ {
    if (in_jellyfin && middleware) found=1
    in_hr=0; in_jellyfin=0; middleware=0
  }
  END {
    if (in_jellyfin && middleware) found=1
    exit found ? 1 : 0
  }
' "$rendered" \
  || fail 'Jellyfin ingress must not use Authelia forward-auth; native clients use Jellyfin OIDC'
grep -q 'kind: ClusterRole' "$rendered" \
  || fail 'Jellyfin admin sync must use a ClusterRole for cross-namespace Authelia secret reads'
grep -q 'resourceNames:' "$rendered" && grep -q -- '- authelia-users' "$rendered" \
  || fail 'Jellyfin admin sync cannot read the Authelia users secret'
grep -q 'JELLYFIN_ADMIN_GROUPS' "$rendered" \
  || fail 'Jellyfin admin sync has no admin group configuration'
grep -q 'jellyfin-admins,admins' "$rendered" \
  || fail 'Jellyfin admin sync does not default to jellyfin-admins/admins'
grep -q '/Users/.*/Policy' "$rendered" \
  || fail 'Jellyfin admin sync does not update Jellyfin user policy'
grep -q 'Other Downloads' "$rendered" \
  || fail 'Jellyfin bootstrap does not create the Other Downloads library'
grep -q '/media/downloads/other' "$rendered" \
  || fail 'Jellyfin Other Downloads library path is not rendered under /media/downloads'
grep -q 'LIBRARY_DISPLAY_ORDER' "$rendered" \
  || fail 'Jellyfin bootstrap does not define a stable library display order'
grep -q 'E2E Movies' "$rendered" && grep -q 'E2E TV' "$rendered" && grep -q 'E2E Music' "$rendered" \
  || fail 'Jellyfin library display order does not keep E2E libraries managed'
grep -q 'ensure_user_library_display_order' "$rendered" \
  || fail 'Jellyfin bootstrap does not apply the library display order'
grep -q 'OrderedViews' "$rendered" \
  || fail 'Jellyfin bootstrap does not update Jellyfin OrderedViews'
awk '
  /^  bootstrap.py: \|-$/ {flag=1; next}
  flag && /^---$/ {flag=0}
  flag && /^[^ ]/ {flag=0}
  flag && /^  [^ ]/ {flag=0}
  flag {sub(/^    /, ""); print}
' "$rendered" >"$bootstrap_script"
"${python_command[@]}" -m py_compile "$bootstrap_script" \
  || fail 'Jellyfin bootstrap Python does not compile'
"${python_command[@]}" -m py_compile "$cleanup_script" \
  || fail 'Jellyfin transcode cleanup Python does not compile'
grep -q 'existingClaim: arr-media-v2' "$rendered" \
  || fail 'media apps do not mount arr-media-v2'
grep -q 'existingClaim: jellyfin-transcode-cache' "$jellyfin_release" \
  || fail 'Jellyfin does not mount its persistent transcode cache PVC'
grep -q 'path: /transcode' "$jellyfin_release" \
  || fail 'Jellyfin transcode cache is not mounted at /transcode'
grep -q 'path: /config/cache/transcodes' "$jellyfin_release" \
  || fail 'Jellyfin transcode cache is not mounted at /config/cache/transcodes'
grep -q 'shareProcessNamespace: true' "$jellyfin_release" \
  || fail 'Jellyfin cleanup sidecar cannot inspect active transcode processes'
grep -q 'transcode-cleanup:' "$jellyfin_release" \
  || fail 'Jellyfin transcode cleanup sidecar is not configured'
grep -q 'name: jellyfin-transcode-cleanup' "$jellyfin_release" \
  || fail 'Jellyfin transcode cleanup script is not mounted'
if grep -q 'type: emptyDir' "$jellyfin_release"; then
  fail 'Jellyfin transcode cache must not use emptyDir'
fi
grep -Fq 'storage: ${jellyfin_transcode_cache_size:=100Gi}' "$transcode_cache_pvc" \
  || fail 'Jellyfin transcode cache PVC must default to 100Gi'
grep -Fq 'storageClassName: ${arr_config_storage_class_name}' "$transcode_cache_pvc" \
  || fail 'Jellyfin transcode cache PVC must use the app-data SSD storage class'
grep -q -- '- ReadWriteOnce' "$transcode_cache_pvc" \
  || fail 'Jellyfin transcode cache PVC must be single-writer'
grep -q 'recurring-job-group.longhorn.io/default: disabled' "$transcode_cache_pvc" \
  || fail 'Disposable Jellyfin transcode cache must not receive Longhorn backups'
grep -Fq 'size: ${jellyfin_config_size:=10Gi}' "$rendered" \
  || fail 'Jellyfin config PVC must default to 10Gi'
if grep -q 'mountPath: /downloads\|path: /downloads\|subPath: downloads' "$rendered"; then
  fail 'downloads must not be mounted separately from arr-media-v2'
fi
if grep -q 'existingClaim: arr-downloads' "$rendered"; then
  fail 'arr-downloads must not be mounted by media apps after downloads migration'
fi
grep -Fq 'Downloads\SavePath=/media/downloads/other' "$rendered" \
  || fail 'qBittorrent static config does not default unsorted downloads to /media/downloads/other'
grep -q '"save_path": "/media/downloads/other"' "$rendered" \
  || fail 'qBittorrent API policy does not enforce /media/downloads/other as default save path'

stale_file="${cleanup_test_directory}/stale.ts"
fresh_file="${cleanup_test_directory}/fresh.ts"
active_file="${cleanup_test_directory}/active-session.m3u8"
printf 'stale\n' >"$stale_file"
printf 'fresh\n' >"$fresh_file"
touch -d '2 minutes ago' "$stale_file"

"${python_command[@]}" -c \
  'import time; time.sleep(30)' "$active_file" &
active_process_pid=$!
sleep 1

TRANSCODE_CACHE_DIR="$cleanup_test_directory" \
TRANSCODE_CACHE_ALIASES="$cleanup_test_directory" \
TRANSCODE_MAX_AGE_SECONDS=60 \
TRANSCODE_CLEANUP_INTERVAL_SECONDS=1 \
  "${python_command[@]}" "$cleanup_script" --once

[[ -f "$stale_file" ]] \
  || fail 'Jellyfin cleanup deleted stale files while a transcode process was active'

kill "$active_process_pid"
wait "$active_process_pid" 2>/dev/null || true
active_process_pid=""

TRANSCODE_CACHE_DIR="$cleanup_test_directory" \
TRANSCODE_CACHE_ALIASES="$cleanup_test_directory" \
TRANSCODE_MAX_AGE_SECONDS=60 \
TRANSCODE_CLEANUP_INTERVAL_SECONDS=1 \
  "${python_command[@]}" "$cleanup_script" --once

[[ ! -e "$stale_file" ]] \
  || fail 'Jellyfin cleanup did not remove an inactive stale transcode file'
[[ -f "$fresh_file" ]] \
  || fail 'Jellyfin cleanup removed a fresh transcode file'

printf '[jellyfin-gitops-test] ok\n'

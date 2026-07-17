#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
bootstrap_script="$(mktemp --suffix=.py)"
trap 'rm -f "$rendered" "$bootstrap_script"' EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"

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
nix shell nixpkgs#python3 -c python -m py_compile "$bootstrap_script" \
  || fail 'Jellyfin bootstrap Python does not compile'
grep -q 'existingClaim: arr-media-v2' "$rendered" \
  || fail 'media apps do not mount arr-media-v2'
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

printf '[jellyfin-gitops-test] ok\n'

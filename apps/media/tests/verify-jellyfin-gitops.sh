#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"

fail() {
  printf '[jellyfin-gitops-test] FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'name: jellyfin-admin-sync' "$rendered" \
  || fail 'Jellyfin admin sync job is not rendered'
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
grep -q '/downloads/other' "$rendered" \
  || fail 'Jellyfin Other Downloads library path is not rendered'
grep -q 'existingClaim: arr-downloads' "$rendered" \
  || fail 'Jellyfin does not mount arr-downloads'

printf '[jellyfin-gitops-test] ok\n'

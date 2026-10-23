#!/usr/bin/env bash
# Check every Nextcloud app pinned in apps/nextcloud/helm-release.yaml against
# the appstore compatibility matrix for the Nextcloud version the custom image
# is built from (the FROM tag in containers/nextcloud/Dockerfile).
#
# This is the guard that caught nothing when external v10 / impersonate v6 /
# richdocuments v12 (all NC35-only) were offered by Renovate against NC34:
# a pin whose version the appstore does not list as compatible with the target
# Nextcloud fails the check BEFORE the bump merges, instead of breaking the
# app-seed initContainer at rollout.
#
# Exit codes: 0 all pins OK (warnings allowed), 1 at least one incompatible pin.
# Apps absent from the appstore (bespoke/unlisted) only warn: the appstore
# cannot vouch for them either way — verify-custom-apps covers their integrity.
set -euo pipefail

HELM_RELEASE=${1:-apps/nextcloud/helm-release.yaml}
DOCKERFILE=${2:-containers/nextcloud/Dockerfile}

NC_TAG=$(awk -F: '/^FROM/ {print $2; exit}' "$DOCKERFILE")
NC_VER=${NC_TAG%-apache}
if [ -z "$NC_VER" ]; then
  echo "could not derive the Nextcloud version from $DOCKERFILE" >&2
  exit 1
fi
echo "Target Nextcloud: $NC_VER (image tag $NC_TAG)"

APPS_JSON=$(mktemp)
trap 'rm -f "$APPS_JSON"' EXIT
curl -fsSL --retry 3 \
  "https://apps.nextcloud.com/api/v1/platform/${NC_VER}/apps.json" -o "$APPS_JSON"

# fetch_app blocks are backslash-continued argument lists:
#   fetch_app \
#     <app id> \
#     <tarball url> \
#     <sha256> \
#     <marker file> \
#     <version>
pins=$(awk '
  /fetch_app \\$/ {
    getline id; getline url; getline sha; getline marker; getline ver
    gsub(/[[:space:]\\]/, "", id); gsub(/[[:space:]\\]/, "", ver)
    print id, ver
  }' "$HELM_RELEASE")

if [ -z "$pins" ]; then
  echo "no fetch_app pins found in $HELM_RELEASE — parser or layout drifted" >&2
  exit 1
fi

fail=0
while read -r id ver; do
  releases=$(jq -r --arg id "$id" \
    '.[] | select(.id == $id) | .releases[].version' "$APPS_JSON")
  if [ -z "$releases" ]; then
    echo "WARN  $id $ver — not in the appstore listing for NC $NC_VER; verify manually"
  elif printf '%s\n' "$releases" | grep -qx "$ver"; then
    echo "OK    $id $ver"
  else
    compat=$(printf '%s\n' "$releases" | head -1)
    echo "FAIL  $id $ver — appstore lists no NC-$NC_VER-compatible release at this version (newest compatible: $compat)"
    fail=1
  fi
done <<< "$pins"

exit "$fail"

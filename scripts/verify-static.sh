#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

./scripts/verify-app-manifests.sh
./apps/authelia/tests/verify-oidc-redirects.sh
./apps/monitoring/tests/verify-dashboards.sh

./apps/cloudflared/tests/verify-ingress-hosts.sh
./apps/immich/tests/verify-nextcloud-storage.sh
./apps/immich/tests/verify-reloader-annotations.sh
./apps/longhorn/tests/verify-storageclasses.sh
./apps/matrix/tests/verify-bridge-config-authority.sh
./apps/nextcloud/tests/verify-shared-media.sh
./apps/media/tests/verify-prowlarr-private-only.sh
./apps/media/tests/verify-qbittorrent-policy.sh

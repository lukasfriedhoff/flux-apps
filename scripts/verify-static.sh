#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

./scripts/verify-app-manifests.sh
./apps/monitoring/tests/verify-dashboards.sh

./apps/immich/tests/verify-nextcloud-storage.sh
./apps/immich/tests/verify-reloader-annotations.sh
./apps/nextcloud/tests/verify-shared-media.sh
./apps/media/tests/verify-prowlarr-private-only.sh
./apps/media/tests/verify-qbittorrent-policy.sh

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

# Two unrelated tools are both called `yq`. These tests are written against
# mikefarah/yq v4 (Go); kislyuk/yq (Python, a YAML wrapper around jq) takes
# different flags and dies with an argparse usage dump that says nothing about
# the real problem. Check up front so the message is actionable.
if ! yq --version 2>&1 | grep -q 'mikefarah'; then
  echo "error: these tests need mikefarah/yq v4, found: $(yq --version 2>&1 | head -1)" >&2
  echo "       nix: nix shell nixpkgs#yq-go   (or see .github/workflows/verify.yml)" >&2
  exit 1
fi

./scripts/verify-app-manifests.sh
./apps/authelia/tests/verify-oidc-redirects.sh
./apps/monitoring/tests/verify-alerts.sh
./apps/monitoring/tests/verify-dashboards.sh

./apps/cloudflared/tests/verify-ingress-hosts.sh
./apps/status-dashboard/tests/verify-status-coverage.sh
./apps/immich/tests/verify-nextcloud-storage.sh
./apps/immich/tests/verify-reloader-annotations.sh
./apps/longhorn/tests/verify-storageclasses.sh
./apps/matrix/tests/verify-bridge-config-authority.sh
./apps/nextcloud/tests/verify-shared-media.sh

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
helm_release="${repo_root}/apps/nextcloud/helm-release.yaml"
verify_job="${repo_root}/apps/nextcloud/verify-custom-apps.yaml"
office_check="${repo_root}/apps/nextcloud/office-check.yaml"
kustomization="${repo_root}/apps/nextcloud/kustomization.yaml"

fail() {
  printf '[nextcloud-office-test] %s\n' "$*" >&2
  exit 1
}

# The seed initContainer and the verify job must pin the same richdocuments
# release; a drifting pair is exactly how Office silently broke on NC 34.
seed_url="$(grep -A2 'fetch_app \\' "$helm_release" | grep -o 'https://[^ ]*richdocuments[^ ]*\.tar\.gz' | head -1)"
verify_url="$(grep -o 'https://[^ ]*richdocuments[^ ]*\.tar\.gz' "$verify_job" | head -1)"
[ -n "$seed_url" ] || fail "no richdocuments pin found in helm-release.yaml"
[ "$seed_url" = "$verify_url" ] || fail "pin drift: seed=$seed_url verify=$verify_url"

seed_sha="$(grep -A3 "richdocuments \\\\" "$helm_release" | grep -oE '[0-9a-f]{64}' | head -1)"
verify_sha="$(grep -A3 "richdocuments \\\\" "$verify_job" | grep -oE '[0-9a-f]{64}' | head -1)"
[ "$seed_sha" = "$verify_sha" ] || fail "sha drift: seed=$seed_sha verify=$verify_sha"

# The runtime canary must stay wired into the kustomization.
grep -q 'office-check.yaml' "$kustomization" || fail "office-check.yaml not in kustomization"
grep -q 'richdocuments enabled' "$office_check" || fail "office-check missing enabled probe"
grep -q 'hosting/discovery' "$office_check" || fail "office-check missing discovery probe"

printf '[nextcloud-office-test] OK: pin %s\n' "${seed_url##*/}"

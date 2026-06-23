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
  if ! grep -q 'type: Recreate' "$file"; then
    fail "${deployment} must use Recreate strategy to avoid surge deadlocks with RWO/stateful mounts"
  fi
  printf '[immich-reloader-test] %s ok\n' "$deployment"
}

check_file "${repo_root}/apps/immich/server.yaml" immich-server
check_file "${repo_root}/apps/immich-photos/server.yaml" immich-photos-server

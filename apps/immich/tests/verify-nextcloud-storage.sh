#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
immich_kustomization="${repo_root}/apps/immich/kustomization.yaml"
immich_server="${repo_root}/apps/immich/server.yaml"
immich_bootstrap="${repo_root}/apps/immich/bootstrap-config.yaml"
immich_pv="${repo_root}/apps/immich/pv-memes.yaml"
immich_pvc="${repo_root}/apps/immich/pvc-memes.yaml"
photos_server="${repo_root}/apps/immich-photos/server.yaml"
photos_pv="${repo_root}/apps/immich-photos/pv-photos.yaml"
photos_pvc="${repo_root}/apps/immich-photos/pvc-photos.yaml"

fail() {
  printf '[immich-nextcloud-storage-test] %s\n' "$*" >&2
  exit 1
}

grep -q 'pv-memes.yaml' "$immich_kustomization" || fail "immich kustomization must include the Memes static PV"
grep -q 'pvc-memes.yaml' "$immich_kustomization" || fail "immich kustomization must include the Memes static PVC"
grep -q 'mountPath: /usr/src/app/external' "$immich_server" || fail "immich server must mount external Memes path"
grep -q 'claimName: ${immich_memes_shared_claim_name:=immich-memes-shared}' "$immich_server" || fail "immich server must use configurable Memes shared PVC"
grep -q 'storageClassName: ""' "$immich_pvc" || fail "Memes shared PVC must bind to a static NFS PV"
grep -q 'volumeName: ${immich_memes_shared_pv_name:=immich-memes-shared-pv}' "$immich_pvc" || fail "Memes shared PVC must pin the configured static PV"
grep -q 'server: ${memes_shared_nfs_server}' "$immich_pv" || fail "Memes PV must use cluster-provided NFS server"
grep -q 'path: ${memes_shared_nfs_path:=/export}' "$immich_pv" || fail "Memes PV must use cluster-provided NFS path"
grep -q 'Nextcloud Memes' "$immich_bootstrap" || fail "immich bootstrap must configure Nextcloud Memes external libraries"
grep -q 'external/memes/' "$immich_bootstrap" || fail "immich bootstrap must import only the Memes subdirectory"
grep -Fq 'cronExpression = "*/15 * * * *"' "$immich_bootstrap" || fail "immich bootstrap must enable recurring library scans"

grep -q 'mountPath: /usr/src/app/external' "$photos_server" || fail "immich-photos server must mount external Photos path"
grep -q 'storageClassName: ""' "$photos_pvc" || fail "Photos shared PVC must bind to a static NFS PV"
grep -q 'server: ${photos_shared_nfs_server}' "$photos_pv" || fail "Photos PV must use cluster-provided NFS server"

printf '[immich-nextcloud-storage-test] nextcloud external library wiring ok\n'

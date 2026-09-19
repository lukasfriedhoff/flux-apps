#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
app="${repo_root}/apps/icarus"

fail() {
  printf '[icarus-stack-test] %s\n' "$*" >&2
  exit 1
}

# Steam must stay off the server's startup path (the old stack's worst outage):
# the updater only runs when the game is missing or explicitly forced.
grep -q 'ICARUS_UPDATE_ON_START' "${app}/deployment.yaml" || fail "updater must be gated behind icarus_update_on_start"
grep -q 'IcarusServer-Win64-Shipping.exe' "${app}/deployment.yaml" || fail "updater must skip when the game is already installed"

# Steam advertises whatever port the process binds; the LB service ports must
# stay equal to the container ports (same variable on port and targetPort).
[ "$(grep -ci 'port: ${icarus_game_port' "${app}/service-game.yaml")" -eq 2 ] || fail "game service port and targetPort must both use icarus_game_port"
[ "$(grep -ci 'port: ${icarus_query_port' "${app}/service-game.yaml")" -eq 2 ] || fail "query service port and targetPort must both use icarus_query_port"
# Player source IPs must reach the server; Local also pins the announcement
# to the node running the pod.
grep -q 'externalTrafficPolicy: Local' "${app}/service-game.yaml" || fail "game service must use externalTrafficPolicy Local"

# The image is imported node-locally; a registry pull would always fail.
grep -q 'imagePullPolicy: Never' "${app}/deployment.yaml" || fail "image must be node-local (imagePullPolicy Never)"
grep -q 'kubernetes.io/hostname: ${icarus_node}' "${app}/deployment.yaml" || fail "server must pin to the node holding the image"

# Real healthchecks, not process liveness.
grep -q 'healthcheck.sh' "${app}/deployment.yaml" || fail "probes must use the a2s healthcheck"

# Saves are precious: second Longhorn replica must be pinned via annotation.
grep -q 'longhorn.h4xx.io/replica-count: "2"' "${app}/pvc-data.yaml" || fail "data PVC needs the replica-count annotation"

# Backups: retention and read-only data mount.
grep -q 'restic forget --keep-daily' "${app}/backup-cronjob.yaml" || fail "backup must apply retention"
grep -q 'readOnly: true' "${app}/backup-cronjob.yaml" || fail "backup must mount data read-only"

# Restore must never run against a live server.
grep -q 'scale deployment/icarus --replicas=0' "${app}/webui-olivetin.yaml" || fail "restore must stop the server first"

# Both UI hosts sit behind authelia; filebrowser is unauthenticated by itself.
count="$(grep -c 'traefik-authelia-forwardauth@kubernetescrd' "${app}/ingress.yaml" || true)"
[ "${count}" -ge 1 ] || fail "webui ingress must use the authelia forwardauth middleware"
grep -q -- '--noauth' "${app}/webui-filebrowser.yaml" && grep -q 'authelia' "${app}/ingress.yaml" || fail "filebrowser --noauth requires the authelia middleware on its ingress"

printf '[icarus-stack-test] icarus stack wiring ok\n'

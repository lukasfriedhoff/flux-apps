#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
app="${repo_root}/apps/valheim"

fail() {
  printf '[valheim-stack-test] %s\n' "$*" >&2
  exit 1
}

# Steam advertises whatever port the server binds; the LB service ports must
# stay equal to the container ports (same variable on port and targetPort).
[ "$(grep -ci 'port: ${valheim_game_port' "${app}/service-game.yaml")" -eq 2 ] || fail "game service port and targetPort must both use valheim_game_port"
[ "$(grep -ci 'port: ${valheim_query_port' "${app}/service-game.yaml")" -eq 2 ] || fail "query service port and targetPort must both use valheim_query_port"
# Player source IPs must reach the server; Local also pins the announcement
# to the node running the pod.
grep -q 'externalTrafficPolicy: Local' "${app}/service-game.yaml" || fail "game service must use externalTrafficPolicy Local"

# Probes must prove the game answers, not just that a process exists: a wedged
# server keeps its PID and its HTTP status page while refusing every join.
grep -q 'TSource Engine Query' "${app}/deployment.yaml" || fail "probes must use a live A2S query, not a process/HTTP check"
[ "$(grep -c 'TSource Engine Query' "${app}/deployment.yaml")" -eq 2 ] || fail "both startupProbe and livenessProbe must use the A2S check"

# One world, one writer: a second replica would corrupt the save.
grep -q 'type: Recreate' "${app}/deployment.yaml" || fail "deployment must use the Recreate strategy"

# Updates must not kick players mid-session.
grep -q 'UPDATE_IF_IDLE' "${app}/deployment.yaml" || fail "update checks must be gated on an idle server"

# kustomize drops source quotes it deems unnecessary, so a value that only
# becomes YAML-significant AFTER substitution (a cron starting with '*', an
# empty string) must re-insert them with ${quote} or the Kustomization fails
# with "did not find expected alphabetic or numeric character".
for v in valheim_update_cron valheim_internal_backups_cron valheim_backup_cron; do
  if grep -rq "\${$v" "${app}"; then
    grep -rq "\${quote}\${$v}\${quote}" "${app}" || fail "$v must be wrapped in \${quote} (cron values can start with '*')"
  fi
done

# Saves are precious: second Longhorn replica must be pinned via annotation.
grep -q 'longhorn.h4xx.io/replica-count: "2"' "${app}/pvc-config.yaml" || fail "config PVC needs the replica-count annotation"

# Backups: an S3 outage must never be mistaken for an uninitialised repo
# (restic exit 10 is the only code that may trigger init).
grep -q 'rc" -eq 10' "${app}/backup-cronjob.yaml" || fail "backup must only init on restic exit code 10"
grep -q 'restic forget --keep-daily' "${app}/backup-cronjob.yaml" || fail "backup must apply retention"
grep -q 'readOnly: true' "${app}/backup-cronjob.yaml" || fail "backup must mount config read-only"

# Restore must never run against a live server.
grep -q 'scale deployment/valheim --replicas=0' "${app}/webui-olivetin.yaml" || fail "restore must stop the server first"

# Both UI hosts sit behind authelia; filebrowser is unauthenticated by itself.
count="$(grep -c 'traefik-authelia-forwardauth@kubernetescrd' "${app}/ingress.yaml" || true)"
[ "${count}" -ge 1 ] || fail "webui ingress must use the authelia forwardauth middleware"
grep -q -- '--noauth' "${app}/webui-filebrowser.yaml" && grep -q 'authelia' "${app}/ingress.yaml" || fail "filebrowser --noauth requires the authelia middleware on its ingress"

# The status endpoint carries player names — cluster-internal only.
grep -q 'kind: Ingress' "${app}/service-game.yaml" && fail "status service must never be exposed via ingress"

printf '[valheim-stack-test] valheim stack wiring ok\n'

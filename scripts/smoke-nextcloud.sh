#!/usr/bin/env bash
set -euo pipefail

context="${1:-}"
namespace="${2:-nextcloud}"

if [[ -z "$context" ]]; then
  echo "usage: $0 <kubectl-context> [namespace]" >&2
  exit 2
fi

kubectl --context "$context" get namespace "$namespace" >/dev/null

echo "[nextcloud-smoke] context=$context namespace=$namespace"

if kubectl --context "$context" -n flux-system get kustomization nextcloud-app >/dev/null 2>&1; then
  ready="$(kubectl --context "$context" -n flux-system get kustomization nextcloud-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  if [[ "$ready" != *True* ]]; then
    kubectl --context "$context" -n flux-system get kustomization nextcloud-app -o wide >&2
    echo "nextcloud-app kustomization is not Ready" >&2
    exit 1
  fi
fi

if kubectl --context "$context" -n "$namespace" get helmrelease nextcloud >/dev/null 2>&1; then
  ready="$(kubectl --context "$context" -n "$namespace" get helmrelease nextcloud -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  if [[ "$ready" != *True* ]]; then
    kubectl --context "$context" -n "$namespace" get helmrelease nextcloud -o wide >&2
    echo "nextcloud HelmRelease is not Ready" >&2
    exit 1
  fi
fi

kubectl --context "$context" -n "$namespace" rollout status deploy/nextcloud --timeout=5m

available="$(kubectl --context "$context" -n "$namespace" get deploy nextcloud -o jsonpath='{.status.availableReplicas}')"
if [[ "${available:-0}" -lt 1 ]]; then
  kubectl --context "$context" -n "$namespace" get deploy,pods -l app.kubernetes.io/instance=nextcloud -o wide >&2
  echo "nextcloud has no available app pod" >&2
  exit 1
fi

pod="$(kubectl --context "$context" -n "$namespace" get pods \
  -l app.kubernetes.io/instance=nextcloud,app.kubernetes.io/component=app \
  --no-headers | awk '$3 == "Running" { print $1; exit }')"
if [[ -z "$pod" ]]; then
  kubectl --context "$context" -n "$namespace" get pods -l app.kubernetes.io/instance=nextcloud -o wide >&2
  echo "no running Nextcloud app pod found" >&2
  exit 1
fi

kubectl --context "$context" -n "$namespace" exec "$pod" -- /bin/sh -s <<'SCRIPT'
set -eu
status="$(php /var/www/html/occ status --output=json)"
echo "$status"
echo "$status" | grep -q '"installed":true'
echo "$status" | grep -q '"maintenance":false'
echo "$status" | grep -q '"needsDbUpgrade":false'
php /var/www/html/occ app:list | grep -q ' - oidc_login:'
mount_json="$(php /var/www/html/occ files_external:list --output=json)"
echo "$mount_json" | grep -q '"mount_point":"\\/Photos"'
echo "$mount_json" | grep -q '"datadir":"\\/shared-photos\\/\$user"'
if [ ! -d /shared-photos ]; then
  echo "/shared-photos is not mounted" >&2
  exit 1
fi
php /var/www/html/occ user:list --output=json \
  | php -r '
    $users = json_decode(file_get_contents("php://stdin"), true);
    if (!is_array($users)) {
      fwrite(STDERR, "cannot parse user list\n");
      exit(1);
    }
    foreach (array_keys($users) as $user) {
      echo $user . "\n";
    }
  ' \
  | while IFS= read -r user_id; do
    case "$user_id" in
      ""|*/*|*..*) continue ;;
    esac
    if [ ! -d "/shared-photos/$user_id" ]; then
      echo "missing Shared Photos user directory: /shared-photos/$user_id" >&2
      exit 1
    fi
  done
SCRIPT

echo "[nextcloud-smoke] ok"

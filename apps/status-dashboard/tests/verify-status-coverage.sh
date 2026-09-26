#!/usr/bin/env bash
# Every user-facing ingress must appear on the status dashboard.
#
# This exists because the dashboard silently drifted: by 2026-09-24 it was
# missing 17 live services (Forgejo, Home Assistant, Harbor, LLDAP, MAS ...)
# and still monitoring two that had been removed. Nobody noticed, because
# adding an app and adding its status entry were separate acts of memory.
# Now adding an ingress without a status entry fails the build.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
config_file="${repo_root}/apps/status-dashboard/configmap.yaml"

fail() {
  printf '[status-coverage] FAIL: %s\n' "$*" >&2
  exit 1
}

command -v yq >/dev/null 2>&1 || fail "missing required command: yq"
[ -f "$config_file" ] || fail "missing $config_file"

# Hosts that intentionally have no status entry. Keep the reason with the
# entry - an unexplained exemption is how drift starts again.
is_exempt() {
  case "$1" in
    # Monitoring itself from itself proves nothing.
    status) return 0 ;;
    # Machine-to-machine receiver (Flux notifications), not a service anyone
    # visits; it 404s by design unless POSTed to with a valid signature.
    flux-webhook) return 0 ;;
    # Catalog-only: these live in this repo but have no Kustomization in
    # flux-cluster, so they are not deployed on homelab-prod and monitoring
    # them would show a permanent red. flux-apps is a cluster-agnostic
    # catalog, so "declared here" does not imply "running somewhere".
    # If you wire one into a cluster, drop it from this list.
    moonlight | valhalla | valhalla-gpx) return 0 ;;
    # Reached over SSH via the cloudflared tunnel (ssh:// service), not HTTP,
    # so an HTTP probe cannot express its health.
    nix-builder) return 0 ;;
    # Not a service host: a path-scoped Traefik route for Matrix login
    # compat that rides on an existing host (the apex in homelab). The
    # default is an unroutable sentinel so the route stays unmatched until a
    # cluster opts in. MAS itself is monitored as "Matrix Auth (MAS)".
    mas-compat-disabled) return 0 ;;
    # KNOWN DISCREPANCY, not a clean exemption: the homelab overlay sets
    # logday_suspend=false and logday_repo_suspend=false, so this is supposed
    # to be running - but on 2026-09-24 there was no Kustomization, no pods
    # and no ingress, only an empty 113-day-old namespace. Either deploy it
    # (then add a status entry and delete this case) or suspend it properly
    # in flux-cluster. Left exempt so CI is not permanently red.
    logday) return 0 ;;
    *) return 1 ;;
  esac
}

# Any hostname of the form <prefix>${public_host_suffix} referenced anywhere in
# the app manifests. Deliberately NOT limited to "- host:" lines: Helm-based
# apps never write those. Harbor declares its hostname as `externalURL:` and
# `core:`, Grafana as a bare list item - an earlier version of this check
# matched only raw Ingress manifests and silently passed while Harbor was
# missing from the dashboard.
#
# Over-matching is the safe direction: a hostname referenced but not monitored
# fails loudly and is either added or exempted, whereas under-matching hides
# exactly the drift this test exists to catch.
declared="$(grep -rhoE '[a-z0-9][a-z0-9-]*\$\{public_host_suffix\}' \
  "${repo_root}/apps" --include='*.yaml' --exclude-dir=status-dashboard 2>/dev/null \
  | sed -E 's/\$\{public_host_suffix\}//' \
  | sort -u)"

[ -n "$declared" ] || fail "found no ingress hosts - has the manifest shape changed?"

# Some apps name their host with a single whole-host variable (${uptime_kuma_host})
# instead of the <prefix>${public_host_suffix} pattern. Those were invisible to
# BOTH lists above, so a missing entry cancelled itself out and passed. Resolve
# them through examples/apps/*/base-config.defaults.yaml, which is required to
# carry every ${...} key an app consumes, and compare on the resolved prefix.
resolve_host_var() {
  local var="$1" val
  val="$(grep -rhE "^  ${var}: " "${repo_root}"/examples/apps/*/base-config.defaults.yaml 2>/dev/null \
    | head -1 | sed -E 's/^[^:]+: *//; s/^"//; s/"$//')"
  # strip the domain, leaving the prefix the two lists are compared on
  printf '%s' "${val%%.*}"
}

declared_var_hosts="$(grep -rhoE '\$\{[a-z0-9_]+_host(:=[^}]*)?\}' \
  "${repo_root}/apps" --include='*.yaml' --exclude-dir=status-dashboard 2>/dev/null \
  | sed -E 's/^\$\{//; s/(:=[^}]*)?\}$//' | sort -u)"

while IFS= read -r var; do
  [ -n "$var" ] || continue
  prefix="$(resolve_host_var "$var")"
  [ -n "$prefix" ] && declared="${declared}"$'\n'"${prefix}"
done <<<"$declared_var_hosts"
declared="$(printf '%s\n' "$declared" | sort -u | sed '/^$/d')"

monitored="$(yq -r '.data."config.yaml"' "$config_file" \
  | grep -oE 'https://([a-z0-9-]+\$\{public_host_suffix\}|\$\{[a-z0-9_]+_host\})' \
  | sed -E 's|https://||' \
  | while IFS= read -r h; do
      case "$h" in
        '${'*) resolve_host_var "$(printf '%s' "$h" | sed -E 's/^\$\{//; s/\}$//')"; printf '\n' ;;
        *) printf '%s\n' "$h" | sed -E 's/\$\{public_host_suffix\}//' ;;
      esac
    done \
  | sort -u | sed '/^$/d')"

[ -n "$monitored" ] || fail "status dashboard lists no endpoints"

missing=()
while IFS= read -r host; do
  [ -n "$host" ] || continue
  is_exempt "$host" && continue
  printf '%s\n' "$monitored" | grep -qxF "$host" || missing+=("$host")
done <<<"$declared"

if [ "${#missing[@]}" -gt 0 ]; then
  printf '[status-coverage] these ingress hosts have no status-dashboard entry:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  printf '\nAdd them to apps/status-dashboard/configmap.yaml, or exempt them in\n' >&2
  printf 'this script with a reason.\n' >&2
  exit 1
fi

# Deliberately one-directional. The reverse check ("a status entry with no
# ingress is stale") cannot be decided from this repo: the media stack
# (jellyfin, sonarr, radarr, prowlarr, ...) is declared in the separate
# flux-app-media repo, so those entries look orphaned here when they are
# perfectly valid. Catching stale entries is left to the dashboard itself -
# a removed service turns red, which is visible by design.
printf '[status-coverage] OK: %s ingress hosts declared here are all monitored\n' \
  "$(printf '%s\n' "$declared" | grep -c .)"

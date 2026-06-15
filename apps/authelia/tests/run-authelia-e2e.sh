#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST_SUFFIX="${PUBLIC_HOST_SUFFIX:--testing}"
DELEGATING_DOMAIN="${DELEGATING_DOMAIN:-h4xx.io}"
STATUS_HOST="${STATUS_HOST:-${PUBLIC_HOST_SUFFIX#-}.${DELEGATING_DOMAIN}}"

AUTHELIA_BASE="${AUTHELIA_BASE:-https://auth${PUBLIC_HOST_SUFFIX}.${DELEGATING_DOMAIN}}"
AUTHELIA_USER="${AUTHELIA_USER:-testuser}"
AUTHELIA_PASSWORD="${AUTHELIA_PASSWORD:-}"
AUTHELIA_TARGET_URL="${AUTHELIA_TARGET_URL:-https://${STATUS_HOST}/}"
AUTHELIA_LOCAL_TIMEOUT="${AUTHELIA_LOCAL_TIMEOUT:-30}"
AUTHELIA_REQUIRE_PASSWORD="${AUTHELIA_REQUIRE_PASSWORD:-false}"
JELLYSEERR_PORT_FORWARD_NAMESPACE="${JELLYSEERR_PORT_FORWARD_NAMESPACE:-media}"
JELLYSEERR_PORT_FORWARD_LOCAL_PORT="${JELLYSEERR_PORT_FORWARD_LOCAL_PORT:-15075}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

for cmd in curl jq sed rg; do
  need "$cmd"
done

AUTH_HOST="$(printf '%s' "$AUTHELIA_BASE" | sed -E 's#https?://([^/]+).*#\1#')"
COOKIE_JAR="$(mktemp)"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -f "$COOKIE_JAR"
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
  printf '[authelia-e2e] %s\n' "$*"
}

fail() {
  printf '[authelia-e2e] FAIL: %s\n' "$*" >&2
  exit 1
}

cluster_host() {
  local app="$1"
  printf '%s%s.%s' "$app" "$PUBLIC_HOST_SUFFIX" "$DELEGATING_DOMAIN"
}

host_from_url() {
  printf '%s' "$1" | sed -E 's#https?://([^/]+).*#\1#'
}

query_param() {
  local url="$1"
  local key="$2"
  printf '%s' "$url" | sed -n "s#.*[?&]${key}=\\([^&]*\\).*#\\1#p"
}

location_from_headers() {
  local headers_file="$1"
  awk 'tolower($1)=="location:"{print $2}' "$headers_file" | tr -d '\r' | head -n1
}

curl_follow() {
  local url="$1"
  local body_file="$2"
  local final_url
  final_url="$(curl -ksS -L --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o "$body_file" -w '%{url_effective}' "$url")"
  printf '%s' "$final_url"
}

authelia_login() {
  local login_payload login_code
  login_payload="$(jq -cn \
    --arg username "$AUTHELIA_USER" \
    --arg password "$AUTHELIA_PASSWORD" \
    --arg target "$AUTHELIA_TARGET_URL" \
    '{username:$username,password:$password,targetURL:$target}')"

  login_code="$(curl -ksS \
    --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -H 'Content-Type: application/json' \
    -X POST "${AUTHELIA_BASE}/api/firstfactor" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -o "${WORK_DIR}/firstfactor.json" \
    -w '%{http_code}' \
    --data "$login_payload")"

  [ "$login_code" = "200" ] || fail "firstfactor failed with HTTP ${login_code}"
  jq -e '.status == "OK"' "${WORK_DIR}/firstfactor.json" >/dev/null || fail "firstfactor returned non-OK status"

  curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    "${AUTHELIA_BASE}/api/state" > "${WORK_DIR}/state.json"

  jq -e '.status == "OK"' "${WORK_DIR}/state.json" >/dev/null || fail "state endpoint returned non-OK status"
  jq -e '.data.username == "'"${AUTHELIA_USER}"'"' "${WORK_DIR}/state.json" >/dev/null || fail "state user mismatch"
  jq -e '.data.authentication_level >= 1' "${WORK_DIR}/state.json" >/dev/null || fail "authentication level is not one_factor"
}

assert_auth_gate() {
  local name="$1"
  local url="$2"
  local headers_file code location location_host

  headers_file="$(mktemp)"
  code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -o /dev/null -D "$headers_file" -w '%{http_code}' "$url")"
  location="$(location_from_headers "$headers_file")"
  rm -f "$headers_file"

  case "$code" in
    401|403|302) ;;
    *) fail "${name}: expected auth gate status 401/403/302 from ${url}, got ${code}" ;;
  esac

  if [ -n "$location" ]; then
    location_host="$(host_from_url "$location")"
    [ "$location_host" = "$AUTH_HOST" ] || fail "${name}: expected redirect to ${AUTH_HOST}, got ${location}"
  fi

  log "${name}: auth gate status=${code}"
}

assert_redirect_to_auth() {
  local name="$1"
  local url="$2"
  local expected_client_id="$3"
  local headers_file code location location_host

  headers_file="$(mktemp)"
  code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -o /dev/null -D "$headers_file" -w '%{http_code}' "$url")"
  location="$(location_from_headers "$headers_file")"
  rm -f "$headers_file"

  [ "$code" = "302" ] || fail "${name}: expected HTTP 302 from ${url}, got ${code}"
  [ -n "$location" ] || fail "${name}: missing Location header from ${url}"

  location_host="$(host_from_url "$location")"
  [ "$location_host" = "$AUTH_HOST" ] || fail "${name}: expected redirect host ${AUTH_HOST}, got ${location}"
  printf '%s' "$location" | rg -q "client_id=${expected_client_id}" || \
    fail "${name}: redirect does not contain client_id=${expected_client_id}: ${location}"

  log "${name}: redirect to auth with ${expected_client_id}"
}

assert_public_http_200() {
  local name="$1"
  local url="$2"
  local code

  code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -o "${WORK_DIR}/${name}.html" -w '%{http_code}' "$url")"
  [ "$code" = "200" ] || fail "${name}: expected HTTP 200 from ${url}, got ${code}"
  log "${name}: HTTP 200"
}

complete_oidc_consent() {
  local start_url="$1"
  local expected_host="$2"
  local app_name="$3"
  local final_url flow_id consent_json client_id claims subflow user_code payload post_json redirect_url

  final_url="$(curl_follow "$start_url" "${WORK_DIR}/${app_name}-oidc-start.html")"
  if ! printf '%s' "$final_url" | rg -q '/consent/openid/decision'; then
    [ "$(host_from_url "$final_url")" = "$expected_host" ] || fail "${app_name}: unexpected host without consent page (${final_url})"
    log "${app_name}: OIDC start reached ${final_url}"
    return 0
  fi

  flow_id="$(query_param "$final_url" "flow_id")"
  [ -n "$flow_id" ] || fail "${app_name}: missing flow_id in consent URL"

  consent_json="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    "${AUTHELIA_BASE}/api/oidc/consent?flow=openid_connect&flow_id=${flow_id}")"

  client_id="$(printf '%s' "$consent_json" | jq -r '.data.client_id // empty')"
  claims="$(printf '%s' "$consent_json" | jq -c '.data.claims // []')"
  subflow="$(printf '%s' "$consent_json" | jq -r '.data.subflow // empty')"
  user_code="$(printf '%s' "$consent_json" | jq -r '.data.user_code // empty')"
  [ -n "$client_id" ] || fail "${app_name}: consent details missing client_id"

  payload="$(jq -cn \
    --arg flow_id "$flow_id" \
    --arg client_id "$client_id" \
    --argjson claims "$claims" \
    --arg subflow "$subflow" \
    --arg user_code "$user_code" \
    '{flow_id:$flow_id,client_id:$client_id,consent:true,pre_configure:true,claims:$claims}
      + (if $subflow != "" then {subflow:$subflow} else {} end)
      + (if $user_code != "" then {user_code:$user_code} else {} end)')"

  post_json="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -H 'Content-Type: application/json' \
    -X POST "${AUTHELIA_BASE}/api/oidc/consent" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    --data "$payload")"

  redirect_url="$(printf '%s' "$post_json" | jq -r '.data.redirect_uri // .data.redirect // empty')"
  [ -n "$redirect_url" ] || fail "${app_name}: consent response did not include redirect URI"

  final_url="$(curl_follow "$redirect_url" "${WORK_DIR}/${app_name}-oidc-final.html")"
  [ "$(host_from_url "$final_url")" = "$expected_host" ] || fail "${app_name}: final host mismatch (${final_url})"
  log "${app_name}: OIDC consent complete (${final_url})"
}

complete_oidc_consent_from_json_start() {
  local start_url="$1"
  local expected_host="$2"
  local app_name="$3"
  local start_json redirect_url

  start_json="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    "$start_url")"

  redirect_url="$(printf '%s' "$start_json" | jq -r '.redirectUrl // .redirect_uri // .redirect // empty')"
  [ -n "$redirect_url" ] || fail "${app_name}: start endpoint did not return redirect URL"

  complete_oidc_consent "$redirect_url" "$expected_host" "$app_name"
}

assert_http_200() {
  local name="$1"
  local url="$2"
  local code
  code="$(curl -ksS -L --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -o "${WORK_DIR}/${name}.html" -w '%{http_code}' "$url")"
  [ "$code" = "200" ] || fail "${name}: expected HTTP 200 from ${url}, got ${code}"
  log "${name}: HTTP 200"
}

assert_post_json_200() {
  local name="$1"
  local url="$2"
  local payload="$3"
  local code
  code="$(curl -ksS -L --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
    -H 'Content-Type: application/json' \
    -X POST \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -o "${WORK_DIR}/${name}.json" -w '%{http_code}' \
    --data "$payload" \
    "$url")"
  [ "$code" = "200" ] || fail "${name}: expected HTTP 200 from ${url}, got ${code}"
  log "${name}: HTTP 200"
}

check_jellyseerr_oidc_public_settings() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log "kubectl not found; skipping jellyseerr public settings check."
    return 0
  fi

  if ! kubectl -n "$JELLYSEERR_PORT_FORWARD_NAMESPACE" get svc jellyseerr >/dev/null 2>&1; then
    log "service jellyseerr not found in namespace ${JELLYSEERR_PORT_FORWARD_NAMESPACE}; skipping."
    return 0
  fi

  (
    set -euo pipefail
    local pf_log pf_pid public_json base_url

    pf_log="$(mktemp)"
    kubectl -n "$JELLYSEERR_PORT_FORWARD_NAMESPACE" \
      port-forward svc/jellyseerr "${JELLYSEERR_PORT_FORWARD_LOCAL_PORT}:5055" >"$pf_log" 2>&1 &
    pf_pid=$!
    trap 'kill "$pf_pid" >/dev/null 2>&1 || true; wait "$pf_pid" >/dev/null 2>&1 || true; rm -f "$pf_log"' EXIT

    base_url="http://127.0.0.1:${JELLYSEERR_PORT_FORWARD_LOCAL_PORT}"
    for _ in $(seq 1 30); do
      if curl -fsS "${base_url}/api/v1/settings/public" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    public_json="$(curl -fsS "${base_url}/api/v1/settings/public")"
    printf '%s' "$public_json" | jq -e '.initialized == true' >/dev/null || fail "jellyseerr: initialized=false"
    printf '%s' "$public_json" | jq -e '((.openIdProviders // [])[] | select(.slug == "authelia"))' >/dev/null || \
      fail "jellyseerr: missing authelia OIDC provider in public settings"
  )

  log "jellyseerr: public OIDC provider check passed"
}

log "Running unauthenticated login-surface checks"

assert_public_http_200 authelia_home "${AUTHELIA_BASE}/"

for host in \
  "$(cluster_host dashboard)" \
  "$(cluster_host moonlight)" \
  "$(cluster_host logs)" \
  "$(cluster_host metrics)" \
  "$(cluster_host traces)" \
  "$(cluster_host jellyfin)" \
  "$(cluster_host jellyseerr)" \
  "$(cluster_host sonarr)" \
  "$(cluster_host radarr)" \
  "$(cluster_host lidarr)" \
  "$(cluster_host readarr)" \
  "$(cluster_host prowlarr)" \
  "$(cluster_host bazarr)" \
  "$(cluster_host qbittorrent)" \
  "$(cluster_host profilarr)"
do
  assert_auth_gate "$host" "https://${host}/"
done

assert_redirect_to_auth nextcloud_oidc_entry "https://$(cluster_host nextcloud)/index.php/apps/oidc_login/oidc" "nextcloud"
assert_redirect_to_auth grafana_oidc_entry "https://$(cluster_host grafana)/login/generic_oauth" "grafana"
assert_redirect_to_auth matrix_oidc_entry \
  "https://$(cluster_host matrix)/_matrix/client/v3/login/sso/redirect?redirectUrl=https%3A%2F%2F$(cluster_host chat)%2F" \
  "matrix-synapse"

matrix_login_json="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" "https://$(cluster_host matrix)/_matrix/client/v3/login")"
printf '%s' "$matrix_login_json" | jq -e '.flows[] | select(.type=="m.login.sso") | .identity_providers[] | select(.id=="oidc-authelia")' >/dev/null || \
  fail "matrix: missing oidc-authelia provider in login flows"
log "matrix: login flows expose oidc-authelia provider"

assert_public_http_200 status_dashboard "https://${STATUS_HOST}/"
assert_public_http_200 element_web "https://$(cluster_host chat)/"
assert_public_http_200 immich_login "https://$(cluster_host meme)/auth/login"
assert_public_http_200 collabora_public "https://$(cluster_host collabora)/"
check_jellyseerr_oidc_public_settings

if [ -z "${AUTHELIA_PASSWORD}" ]; then
  if [ "${AUTHELIA_REQUIRE_PASSWORD}" = "true" ]; then
    fail "AUTHELIA_PASSWORD is required when AUTHELIA_REQUIRE_PASSWORD=true"
  fi
  log "AUTHELIA_PASSWORD not set; skipping authenticated checks after validating all login surfaces."
  exit 0
fi

log "Authenticating to Authelia as ${AUTHELIA_USER}"
authelia_login
log "Authelia session established"

# Session-backed checks across protected ingress hosts.
assert_http_200 traefik_dashboard "https://$(cluster_host dashboard)/"
assert_http_200 grafana "https://$(cluster_host grafana)/"
assert_http_200 jellyseerr "https://$(cluster_host jellyseerr)/"
assert_http_200 sonarr "https://$(cluster_host sonarr)/"
assert_http_200 radarr "https://$(cluster_host radarr)/"
assert_http_200 lidarr "https://$(cluster_host lidarr)/"
assert_http_200 readarr "https://$(cluster_host readarr)/"
assert_http_200 prowlarr "https://$(cluster_host prowlarr)/"
assert_http_200 bazarr "https://$(cluster_host bazarr)/"
assert_http_200 qbittorrent "https://$(cluster_host qbittorrent)/"
assert_http_200 profilarr "https://$(cluster_host profilarr)/"
assert_http_200 moonlight_web "https://$(cluster_host moonlight)/"
assert_http_200 collabora "https://$(cluster_host collabora)/"
assert_http_200 immich_login_authed "https://$(cluster_host meme)/auth/login"
assert_http_200 element_web_authed "https://$(cluster_host chat)/"
assert_http_200 status_dashboard_authed "https://${STATUS_HOST}/"

assert_http_200 logs_ready "https://$(cluster_host logs)/loki/api/v1/status/buildinfo"
assert_http_200 metrics_ready "https://$(cluster_host metrics)/ready"
assert_post_json_200 traces_otlp "https://$(cluster_host traces)/v1/traces" '{}'

# OIDC login flows.
complete_oidc_consent \
  "https://$(cluster_host nextcloud)/index.php/apps/oidc_login/oidc" \
  "$(cluster_host nextcloud)" \
  "nextcloud"

complete_oidc_consent \
  "https://$(cluster_host jellyfin)/sso/OID/start/authelia" \
  "$(cluster_host jellyfin)" \
  "jellyfin"

complete_oidc_consent \
  "https://$(cluster_host grafana)/login/generic_oauth" \
  "$(cluster_host grafana)" \
  "grafana"

complete_oidc_consent \
  "https://$(cluster_host matrix)/_matrix/client/v3/login/sso/redirect?redirectUrl=https%3A%2F%2F$(cluster_host chat)%2F" \
  "$(cluster_host chat)" \
  "matrix"

complete_oidc_consent_from_json_start \
  "https://$(cluster_host jellyseerr)/api/v1/auth/oidc/login/authelia?returnUrl=%2F" \
  "$(cluster_host jellyseerr)" \
  "jellyseerr"

# Application-specific smoke checks after auth.
grafana_health_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/grafana-health.json" -w '%{http_code}' \
  "https://$(cluster_host grafana)/api/health")"
[ "$grafana_health_code" = "200" ] || fail "grafana: /api/health returned ${grafana_health_code}"
jq -e '.database == "ok"' "${WORK_DIR}/grafana-health.json" >/dev/null || fail "grafana: health payload does not report database=ok"
log "grafana: health API check passed"

nextcloud_dashboard_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/nextcloud-dashboard.html" -w '%{http_code}' \
  "https://$(cluster_host nextcloud)/apps/dashboard/")"
[ "$nextcloud_dashboard_code" = "200" ] || fail "nextcloud: dashboard returned ${nextcloud_dashboard_code}"
if rg -q "An exception occurred while executing a query|Undefined table" "${WORK_DIR}/nextcloud-dashboard.html"; then
  fail "nextcloud: SQL error detected in dashboard response"
fi
log "nextcloud: dashboard check passed"

jellyfin_info_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/jellyfin-info.json" -w '%{http_code}' \
  "https://$(cluster_host jellyfin)/System/Info/Public")"
[ "$jellyfin_info_code" = "200" ] || fail "jellyfin: System/Info/Public returned ${jellyfin_info_code}"
jq -e '.ProductName | contains("Jellyfin")' "${WORK_DIR}/jellyfin-info.json" >/dev/null || fail "jellyfin: unexpected System/Info/Public payload"
log "jellyfin: public info API check passed"

jellyseerr_me_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/jellyseerr-me.json" -w '%{http_code}' \
  "https://$(cluster_host jellyseerr)/api/v1/auth/me")"
[ "$jellyseerr_me_code" = "200" ] || fail "jellyseerr: /api/v1/auth/me returned ${jellyseerr_me_code}"
jq -e '.id != null' "${WORK_DIR}/jellyseerr-me.json" >/dev/null || fail "jellyseerr: auth/me missing user id"
log "jellyseerr: auth/me check passed"

matrix_versions_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/matrix-versions.json" -w '%{http_code}' \
  "https://$(cluster_host matrix)/_matrix/client/versions")"
[ "$matrix_versions_code" = "200" ] || fail "matrix: client versions returned ${matrix_versions_code}"
jq -e '.versions | length > 0' "${WORK_DIR}/matrix-versions.json" >/dev/null || fail "matrix: versions payload is empty"
log "matrix: versions API check passed"

element_config_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/element-config.json" -w '%{http_code}' \
  "https://$(cluster_host chat)/config.json")"
[ "$element_config_code" = "200" ] || fail "element: config.json returned ${element_config_code}"
jq -e '.default_server_config."m.homeserver".base_url == "https://'"$(cluster_host matrix)"'"' "${WORK_DIR}/element-config.json" >/dev/null \
  || fail "element: config.json homeserver does not point to expected matrix host"
log "element: config check passed"

immich_ping_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/immich-ping.json" -w '%{http_code}' \
  "https://$(cluster_host meme)/api/server/ping")"
[ "$immich_ping_code" = "200" ] || fail "immich: /api/server/ping returned ${immich_ping_code}"
jq -e '.res == "pong"' "${WORK_DIR}/immich-ping.json" >/dev/null || fail "immich: ping payload is unexpected"
log "immich: ping API check passed"

log "All Authelia E2E checks passed."

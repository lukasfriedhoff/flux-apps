#!/usr/bin/env bash
set -euo pipefail

AUTHELIA_BASE="${AUTHELIA_BASE:-https://auth-testing.h4xx.io}"
AUTHELIA_USER="${AUTHELIA_USER:-testuser}"
AUTHELIA_PASSWORD="${AUTHELIA_PASSWORD:-}"
AUTHELIA_TARGET_URL="${AUTHELIA_TARGET_URL:-https://testing.h4xx.io/}"
AUTHELIA_LOCAL_TIMEOUT="${AUTHELIA_LOCAL_TIMEOUT:-30}"

if [ -z "${AUTHELIA_PASSWORD}" ]; then
  echo "error: AUTHELIA_PASSWORD is required" >&2
  exit 1
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

for cmd in curl jq sed rg; do
  need "$cmd"
done

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

host_from_url() {
  printf '%s' "$1" | sed -E 's#https?://([^/]+).*#\1#'
}

query_param() {
  local url="$1"
  local key="$2"
  printf '%s' "$url" | sed -n "s#.*[?&]${key}=\\([^&]*\\).*#\\1#p"
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

log "Authenticating to Authelia as ${AUTHELIA_USER}"
authelia_login
log "Authelia session established"

# ForwardAuth-protected ingresses.
assert_http_200 grafana "https://grafana-testing.h4xx.io/"
assert_http_200 status_dashboard "https://testing.h4xx.io/"
assert_http_200 jellyseerr "https://jellyseerr-testing.h4xx.io/"
assert_http_200 sonarr "https://sonarr-testing.h4xx.io/"
assert_http_200 radarr "https://radarr-testing.h4xx.io/"
assert_http_200 lidarr "https://lidarr-testing.h4xx.io/"
assert_http_200 readarr "https://readarr-testing.h4xx.io/"
assert_http_200 prowlarr "https://prowlarr-testing.h4xx.io/"
assert_http_200 bazarr "https://bazarr-testing.h4xx.io/"
assert_http_200 qbittorrent "https://qbittorrent-testing.h4xx.io/"
assert_http_200 collabora "https://collabora-testing.h4xx.io/"
assert_http_200 immich_login "https://meme-testing.h4xx.io/auth/login"
assert_http_200 element_web "https://chat-testing.h4xx.io/"

# OIDC app logins.
complete_oidc_consent \
  "https://nextcloud-testing.h4xx.io/index.php/apps/oidc_login/oidc" \
  "nextcloud-testing.h4xx.io" \
  "nextcloud"

complete_oidc_consent \
  "https://jellyfin-testing.h4xx.io/sso/OID/start/authelia" \
  "jellyfin-testing.h4xx.io" \
  "jellyfin"

# Application-specific smoke checks after auth.
grafana_health_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/grafana-health.json" -w '%{http_code}' \
  "https://grafana-testing.h4xx.io/api/health")"
[ "$grafana_health_code" = "200" ] || fail "grafana: /api/health returned ${grafana_health_code}"
jq -e '.database == "ok"' "${WORK_DIR}/grafana-health.json" >/dev/null || fail "grafana: health payload does not report database=ok"
log "grafana: health API check passed"

nextcloud_dashboard_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/nextcloud-dashboard.html" -w '%{http_code}' \
  "https://nextcloud-testing.h4xx.io/apps/dashboard/")"
[ "$nextcloud_dashboard_code" = "200" ] || fail "nextcloud: dashboard returned ${nextcloud_dashboard_code}"
if rg -q "An exception occurred while executing a query|Undefined table" "${WORK_DIR}/nextcloud-dashboard.html"; then
  fail "nextcloud: SQL error detected in dashboard response"
fi
log "nextcloud: dashboard check passed"

jellyfin_info_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -o "${WORK_DIR}/jellyfin-info.json" -w '%{http_code}' \
  "https://jellyfin-testing.h4xx.io/System/Info/Public")"
[ "$jellyfin_info_code" = "200" ] || fail "jellyfin: System/Info/Public returned ${jellyfin_info_code}"
jq -e '.ProductName | contains("Jellyfin")' "${WORK_DIR}/jellyfin-info.json" >/dev/null || fail "jellyfin: unexpected System/Info/Public payload"
log "jellyfin: public info API check passed"

matrix_versions_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/matrix-versions.json" -w '%{http_code}' \
  "https://matrix-testing.h4xx.io/_matrix/client/versions")"
[ "$matrix_versions_code" = "200" ] || fail "matrix: client versions returned ${matrix_versions_code}"
jq -e '.versions | length > 0' "${WORK_DIR}/matrix-versions.json" >/dev/null || fail "matrix: versions payload is empty"
log "matrix: versions API check passed"

element_config_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/element-config.json" -w '%{http_code}' \
  "https://chat-testing.h4xx.io/config.json")"
[ "$element_config_code" = "200" ] || fail "element: config.json returned ${element_config_code}"
jq -e '.default_server_config."m.homeserver".base_url == "https://matrix-testing.h4xx.io"' "${WORK_DIR}/element-config.json" >/dev/null \
  || fail "element: config.json homeserver does not point to matrix-testing.h4xx.io"
log "element: config check passed"

immich_ping_code="$(curl -ksS --connect-timeout "$AUTHELIA_LOCAL_TIMEOUT" \
  -o "${WORK_DIR}/immich-ping.json" -w '%{http_code}' \
  "https://meme-testing.h4xx.io/api/server/ping")"
[ "$immich_ping_code" = "200" ] || fail "immich: /api/server/ping returned ${immich_ping_code}"
jq -e '.res == "pong"' "${WORK_DIR}/immich-ping.json" >/dev/null || fail "immich: ping payload is unexpected"
log "immich: ping API check passed"

log "All Authelia E2E checks passed."

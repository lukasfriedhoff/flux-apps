#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build "${repo_root}/apps/media" >"$rendered"

fail() {
  printf '[qbittorrent-policy-test] FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'Session\\GlobalMaxRatio.*-1' "$rendered" \
  || fail 'qBittorrent config init does not force GlobalMaxRatio=-1'
grep -q '"max_ratio_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_ratio_enabled'
grep -q '"max_ratio": -1' "$rendered" \
  || fail 'qBittorrent API policy does not force max_ratio=-1'
grep -q '"max_seeding_time_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_seeding_time_enabled'
grep -q '"max_inactive_seeding_time_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable max_inactive_seeding_time_enabled'
grep -q '"add_trackers_from_url_enabled": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable automatic tracker URL appends'
grep -q 'QBITTORRENT_ALLOWED_TRACKER_MARKERS' "$rendered" \
  || fail 'qBittorrent tracker allowlist is not rendered'
grep -q '/api/v2/torrents/removeTrackers' "$rendered" \
  || fail 'qBittorrent policy does not prune disallowed torrent trackers'
grep -q 'rocket-hd.cc,flood.st' "$rendered" \
  || fail 'qBittorrent tracker allowlist does not default to private tracker markers'
grep -q '/api/v2/torrents/start' "$rendered" \
  || fail 'qBittorrent policy does not restart completed stopped torrents'
if grep -q 'ROCKETHD_QUOTA_BYTES\\|pause_incomplete_rockethd\\|start_incomplete_rockethd' "$rendered"; then
  fail 'qBittorrent policy still contains RocketHD quota enforcement'
fi
grep -q '"current_network_interface": "tun0"' "$rendered" \
  || fail 'qBittorrent API policy does not force tun0 interface binding'
grep -Fq 'Session\Interface=tun0' "$rendered" \
  || fail 'qBittorrent static config does not force tun0 interface binding'
grep -Fq "Session\\\\Interface' 'tun0'" "$rendered" \
  || fail 'qBittorrent config init does not force tun0 interface binding'
grep -q '"current_interface_name": "tun0"' "$rendered" \
  || fail 'qBittorrent port sync does not force current_interface_name=tun0'
grep -q '"random_port": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable random port'
grep -q '"upnp": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable UPnP'
grep -q '"lsd": False' "$rendered" \
  || fail 'qBittorrent API policy does not disable local peer discovery'
grep -q '"auto_tmm_enabled": True' "$rendered" \
  || fail 'qBittorrent API policy does not enable automatic torrent management for category save paths'
grep -q '"/api/v2/torrents/editCategory"' "$rendered" \
  || fail 'qBittorrent policy does not enforce category save paths'
grep -q 'qbt_post_ignore_conflict("/api/v2/torrents/editCategory"' "$rendered" \
  || fail 'qBittorrent category edit conflicts are not handled idempotently'
grep -q '"radarr": "/downloads/radarr"' "$rendered" \
  || fail 'qBittorrent policy does not set Radarr category save path'
grep -q '"sonarr": "/downloads/sonarr"' "$rendered" \
  || fail 'qBittorrent policy does not set Sonarr category save path'
grep -q '"radarr-imported": "/media/staged/movies"' "$rendered" \
  || fail 'qBittorrent policy does not set Radarr imported category save path'
grep -q '"sonarr-imported": "/media/staged/tv"' "$rendered" \
  || fail 'qBittorrent policy does not set Sonarr imported category save path'
grep -Fq 'Session\LSDEnabled=false' "$rendered" \
  || fail 'qBittorrent static config does not disable local peer discovery'
grep -Fq "Session\\\\LSDEnabled' 'false'" "$rendered" \
  || fail 'qBittorrent config init does not disable local peer discovery'
grep -q 'name: qbittorrent-egress' "$rendered" \
  || fail 'qBittorrent egress NetworkPolicy is not rendered'
grep -q 'cidr: .*qbittorrent_vpn_endpoint_cidr' "$rendered" \
  || fail 'qBittorrent NetworkPolicy does not use the VPN endpoint CIDR substitution'

if grep -q 'QBITTORRENT_DEFAULT_SEED_RATIO' "$rendered"; then
  fail 'legacy QBITTORRENT_DEFAULT_SEED_RATIO must not be rendered'
fi

printf '[qbittorrent-policy-test] ok\n'

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
grep -q '"stoppeddl"' "$rendered" \
  || fail 'qBittorrent policy does not restart stopped downloads'
if grep -q 'progress", 0) >= 1' "$rendered"; then
  fail 'qBittorrent stopped torrent policy still only restarts completed torrents'
fi
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
grep -q '/api/v2/torrents/setLocation' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy per-torrent /downloads locations'
grep -q '/api/v2/torrents/setAutoManagement' "$rendered" \
  || fail 'qBittorrent policy does not enable AutoTMM for imported torrents'
grep -q '"/media/downloads/radarr": "/media/downloads/movies"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Radarr per-torrent save paths'
grep -q '"/media/downloads/sonarr": "/media/downloads/tv"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Sonarr per-torrent save paths'
grep -q '"/media/downloads/movies-imported": "/media/downloads/movies"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy movies-imported per-torrent save paths under download movies'
grep -q '"/media/downloads/tv-imported": "/media/downloads/tv"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy tv-imported per-torrent save paths under download tv'
grep -q '"/media/downloads/music-imported": "/media/downloads/music"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy music-imported per-torrent save paths under download music'
grep -q '"/media/downloads/books-imported": "/media/downloads/books"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy books-imported per-torrent save paths under download books'
grep -q '"/media/downloads/radarr-imported": "/media/downloads/movies"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Radarr imported per-torrent save paths under download movies'
grep -q '"/media/downloads/sonarr-imported": "/media/downloads/tv"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Sonarr imported per-torrent save paths under download tv'
grep -q '"/media/downloads/lidarr-imported": "/media/downloads/music"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Lidarr imported per-torrent save paths under download music'
grep -q '"/media/downloads/readarr-imported": "/media/downloads/books"' "$rendered" \
  || fail 'qBittorrent policy does not migrate legacy Readarr imported per-torrent save paths under download books'
grep -q '"radarr": "/media/downloads/movies"' "$rendered" \
  || fail 'qBittorrent policy does not set Radarr category save path under /media/downloads/movies'
grep -q '"sonarr": "/media/downloads/tv"' "$rendered" \
  || fail 'qBittorrent policy does not set Sonarr category save path under /media/downloads/tv'
grep -q '"radarr-imported": "/media/downloads/movies"' "$rendered" \
  || fail 'qBittorrent policy does not set Radarr imported category save path under /media/downloads/movies'
grep -q '"sonarr-imported": "/media/downloads/tv"' "$rendered" \
  || fail 'qBittorrent policy does not set Sonarr imported category save path under /media/downloads/tv'
grep -q '"lidarr-imported": "/media/downloads/music"' "$rendered" \
  || fail 'qBittorrent policy does not set Lidarr imported category save path under /media/downloads/music'
grep -q '"readarr-imported": "/media/downloads/books"' "$rendered" \
  || fail 'qBittorrent policy does not set Readarr imported category save path under /media/downloads/books'
grep -Fq 'Session\LSDEnabled=false' "$rendered" \
  || fail 'qBittorrent static config does not disable local peer discovery'
grep -Fq "Session\\\\LSDEnabled' 'false'" "$rendered" \
  || fail 'qBittorrent config init does not disable local peer discovery'
grep -q 'replicas: .*qbittorrent_replicas' "$rendered" \
  || fail 'qBittorrent replica count is not configurable for migrations'
grep -q 'existingClaim: arr-media-v2' "$rendered" \
  || fail 'qBittorrent does not mount arr-media-v2'
grep -q '"save_path": "/media/downloads/other"' "$rendered" \
  || fail 'qBittorrent API policy does not set default save path under /media/downloads'
grep -q 'Downloads\\SavePath=/media/downloads/other' "$rendered" \
  || fail 'qBittorrent static config does not set default save path under /media/downloads'
grep -q 'ln -s /media/downloads /downloads' "$rendered" \
  || fail 'qBittorrent container does not create legacy /downloads compatibility symlink'
grep -q 'link_empty_dir /media/downloads/radarr /media/downloads/movies' "$rendered" \
  || fail 'qBittorrent init does not alias legacy Radarr folder to movies'
grep -q 'link_empty_dir /media/downloads/sonarr /media/downloads/tv' "$rendered" \
  || fail 'qBittorrent init does not alias legacy Sonarr folder to tv'
grep -q 'link_empty_dir /media/downloads/radarr-imported /media/downloads/movies' "$rendered" \
  || fail 'qBittorrent init does not alias legacy imported Radarr folder to download movies'
grep -q 'link_empty_dir /media/downloads/sonarr-imported /media/downloads/tv' "$rendered" \
  || fail 'qBittorrent init does not alias legacy imported Sonarr folder to download tv'
grep -q 'link_empty_dir /media/downloads/lidarr-imported /media/downloads/music' "$rendered" \
  || fail 'qBittorrent init does not alias legacy imported Lidarr folder to download music'
grep -q 'link_empty_dir /media/downloads/readarr-imported /media/downloads/books' "$rendered" \
  || fail 'qBittorrent init does not alias legacy imported Readarr folder to download books'
if grep -q '"radarr-imported": "/media/movies"\\|"sonarr-imported": "/media/tv"\\|"lidarr-imported": "/media/music"\\|"readarr-imported": "/media/books"' "$rendered"; then
  fail 'qBittorrent imported categories must not point at Jellyfin library roots'
fi
grep -q 'Deleted Radarr stale /downloads remote path mapping' "$rendered" \
  || fail 'Arr bootstrap does not prune stale /downloads remote path mappings'
if grep -q 'mountPath: /downloads\|path: /downloads\|subPath: downloads' "$rendered"; then
  fail 'media apps still mount downloads as a separate mountpoint'
fi
grep -q 'ensure_radarr_download_path_mapping' "$rendered" \
  || fail 'Radarr remote path mapping is not bootstrapped'
grep -q 'ensure_sonarr_download_path_mapping' "$rendered" \
  || fail 'Sonarr remote path mapping is not bootstrapped'
grep -q 'ensure_lidarr_download_path_mapping' "$rendered" \
  || fail 'Lidarr remote path mapping is not bootstrapped'
grep -q 'ensure_readarr_download_path_mapping' "$rendered" \
  || fail 'Readarr remote path mapping is not bootstrapped'
if grep -q 'existingClaim: arr-downloads' "$rendered"; then
  fail 'media apps still mount legacy arr-downloads PVC'
fi
grep -q 'name: qbittorrent-egress' "$rendered" \
  || fail 'qBittorrent egress NetworkPolicy is not rendered'
grep -q 'cidr: .*qbittorrent_vpn_endpoint_cidr' "$rendered" \
  || fail 'qBittorrent NetworkPolicy does not use the VPN endpoint CIDR substitution'

if grep -q 'QBITTORRENT_DEFAULT_SEED_RATIO' "$rendered"; then
  fail 'legacy QBITTORRENT_DEFAULT_SEED_RATIO must not be rendered'
fi

printf '[qbittorrent-policy-test] ok\n'

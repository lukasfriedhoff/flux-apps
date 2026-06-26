#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
bootstrap="$repo_root/apps/media/prowlarr-bootstrap-config.yaml"

fail() {
  echo "verify-prowlarr-private-only: $*" >&2
  exit 1
}

public_patterns=(
  'ensure_indexer "Knaben" "Knaben" true'
  'ensure_indexer "TorrentsCSV" "TorrentsCSV" true'
  'ensure_cardigann_indexer "LimeTorrents" "LimeTorrents" true'
  'ensure_cardigann_indexer "TorrentDownload" "TorrentDownload" true'
  'ensure_indexer "SubsPlease" "SubsPlease" true'
  'ensure_cardigann_indexer "The Pirate Bay" "The Pirate Bay" true'
  'ensure_cardigann_indexer "YTS" "YTS" true'
  'ensure_cardigann_indexer "Nyaa.si" "Nyaa.si" true'
  'ensure_cardigann_indexer "Internet Archive" "Internet Archive" true'
)

for pattern in "${public_patterns[@]}"; do
  if grep -Fq "$pattern" "$bootstrap"; then
    fail "public indexer is enabled by bootstrap: $pattern"
  fi
done

required_disabled=(
  'ensure_indexer "Knaben" "Knaben" false'
  'ensure_indexer "TorrentsCSV" "TorrentsCSV" false'
  'ensure_cardigann_indexer "LimeTorrents" "LimeTorrents" false'
  'ensure_cardigann_indexer "TorrentDownload" "TorrentDownload" false'
  'ensure_indexer "SubsPlease" "SubsPlease" false'
  'ensure_cardigann_indexer "The Pirate Bay" "The Pirate Bay" false'
  'ensure_cardigann_indexer "YTS" "YTS" false'
  'ensure_cardigann_indexer "Nyaa.si" "Nyaa.si" false'
  'ensure_cardigann_indexer "Internet Archive" "Internet Archive" false'
)

for pattern in "${required_disabled[@]}"; do
  grep -Fq "$pattern" "$bootstrap" || fail "public indexer is not explicitly disabled: $pattern"
done
